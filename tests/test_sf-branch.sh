#!/bin/bash
# ==============================================================================
# test_sf-branch.sh - sf-branch.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-branch.sh ===${CLR_RST}"

# --- ヘルパー ---
# sf-branch.sh に番号入力を渡して実行（対話プロンプトへの自動応答）
run_sf_branch() {
    local td="$1" input="$2" mb="$3" mh="$4"
    echo "$input" | (cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-branch.sh" 2>&1)
}

# 構成変更確認 + 番号入力（既に設定済みの場合）
run_sf_branch_with_confirm() {
    local td="$1" confirm="$2" choice="$3" mb="$4" mh="$5"
    printf '%s\n%s\n' "$confirm" "$choice" | (cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-branch.sh" 2>&1)
}

# branches.txt からアクティブ行（コメント・空行以外）を取得
get_active_branches() {
    grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' | tr -d '\r'
}

# ------------------------------------------------------------------------------
# テストケース
# ------------------------------------------------------------------------------

# [1] 選択 → main / staging / develop が branches.txt に書き込まれる
test_pattern1_creates_three_branches() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    # branches.txt を空（コメントのみ）にする
    cp "$SF_TOOLS_DIR/templates/sf-tools/config/branches.txt" "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch "$td" "1" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "パターン1 選択 → 正常終了"

    local branches; branches=$(get_active_branches "$td/sf-tools/config/branches.txt")
    assert_output_contains "$branches" "main"    "branches.txt に main がある"
    assert_output_contains "$branches" "staging" "branches.txt に staging がある"
    assert_output_contains "$branches" "develop" "branches.txt に develop がある"
    teardown "$td" "$mb" "$mh"
}

# [2] 選択 → main / staging が書き込まれる
test_pattern2_creates_two_branches() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    cp "$SF_TOOLS_DIR/templates/sf-tools/config/branches.txt" "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch "$td" "2" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "パターン2 選択 → 正常終了"

    local branches; branches=$(get_active_branches "$td/sf-tools/config/branches.txt")
    assert_output_contains "$branches" "main"    "branches.txt に main がある"
    assert_output_contains "$branches" "staging" "branches.txt に staging がある"
    echo "$branches" | grep -q "develop" || pass "branches.txt に develop がない" && true || fail "develop が含まれている"
    teardown "$td" "$mb" "$mh"
}

# [3] 選択 → main のみ
test_pattern3_creates_one_branch() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    cp "$SF_TOOLS_DIR/templates/sf-tools/config/branches.txt" "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch "$td" "3" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "パターン3 選択 → 正常終了"

    local branches; branches=$(get_active_branches "$td/sf-tools/config/branches.txt")
    assert_output_contains "$branches" "main" "branches.txt に main がある"
    echo "$branches" | grep -q "staging" || pass "branches.txt に staging がない" && true || fail "staging が含まれている"
    echo "$branches" | grep -q "develop" || pass "branches.txt に develop がない" && true || fail "develop が含まれている"
    teardown "$td" "$mb" "$mh"
}

# 無効な番号 → エラー終了
test_invalid_choice() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    cp "$SF_TOOLS_DIR/templates/sf-tools/config/branches.txt" "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch "$td" "9" "$mb" "$mh")
    local ec=$?

    assert_exit_fail $ec "無効な番号 → エラー終了"
    teardown "$td" "$mb" "$mh"
}

# force-* 以外で実行 → エラー
test_outside_force_dir() {
    local rd mb mh
    rd=$(setup_regular_dir); mb=$(setup_mock_bin); mh=$(setup_mock_home)
    export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"

    local out; out=$(echo "1" | (cd "$rd" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-branch.sh" 2>&1))
    local ec=$?

    assert_exit_fail $ec "force-* 外 → エラー終了"
    teardown "$rd" "$mb" "$mh"
}

# コメントヘッダーが保持される
test_comment_header_preserved() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    # テンプレートのコメント付き branches.txt を使用
    cp "$SF_TOOLS_DIR/templates/sf-tools/config/branches.txt" "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch "$td" "1" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "コメント付きファイルで正常終了"
    assert_file_contains "$td/sf-tools/config/branches.txt" "# branches.txt" "コメントヘッダーが保持されている"
    assert_file_contains "$td/sf-tools/config/branches.txt" "#   - main は必須です" "ルール説明コメントが保持されている"
    assert_file_contains "$td/sf-tools/config/branches.txt" "main" "ブランチ名も書き込まれている"
    teardown "$td" "$mb" "$mh"
}

# 既存設定ありで N 回答 → 変更なしで終了
test_existing_config_decline() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    # 既にアクティブなブランチが設定済み
    printf 'main\nstaging\n' > "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch_with_confirm "$td" "N" "" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "変更拒否 → 正常終了"
    local branches; branches=$(get_active_branches "$td/sf-tools/config/branches.txt")
    assert_output_contains "$branches" "staging" "既存設定が維持された"
    teardown "$td" "$mb" "$mh"
}

# 既存設定ありで Y 回答 → 構成変更可能
test_existing_config_accept() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    # 3階層 → 1階層にダウングレード
    printf 'main\nstaging\ndevelop\n' > "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch_with_confirm "$td" "Y" "3" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "構成変更 → 正常終了"
    local branches; branches=$(get_active_branches "$td/sf-tools/config/branches.txt")
    assert_output_contains "$branches" "main" "main が残っている"
    echo "$branches" | grep -q "staging" || pass "staging が除外された" && true || fail "staging が残っている"
    teardown "$td" "$mb" "$mh"
}

# ダウングレード時に削除対象ブランチが案内される
test_downgrade_shows_removed_branches() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"

    # 3階層 → 1階層
    printf 'main\nstaging\ndevelop\n' > "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch_with_confirm "$td" "Y" "3" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "ダウングレード → 正常終了"
    assert_output_contains "$out" "staging" "staging の削除案内が表示された"
    assert_output_contains "$out" "develop" "develop の削除案内が表示された"
    teardown "$td" "$mb" "$mh"
}

# git ls-remote が成功 → ブランチ作成をスキップ
test_existing_remote_branch_skipped() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"
    export MOCK_GIT_LS_REMOTE_EXIT=0  # リモートにブランチが存在する

    cp "$SF_TOOLS_DIR/templates/sf-tools/config/branches.txt" "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch "$td" "1" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "既存ブランチスキップ → 正常終了"
    assert_output_contains "$out" "スキップ" "スキップメッセージが表示された"
    teardown "$td" "$mb" "$mh"
}

# git ls-remote が失敗 → ブランチ作成が実行される
test_new_branch_created() {
    local td mb mh
    setup_std_env td mb mh
    create_all_mocks "$mb"
    export MOCK_GIT_LS_REMOTE_EXIT=2  # リモートにブランチが存在しない

    cp "$SF_TOOLS_DIR/templates/sf-tools/config/branches.txt" "$td/sf-tools/config/branches.txt"

    local out; out=$(run_sf_branch "$td" "2" "$mb" "$mh")
    local ec=$?

    assert_exit_ok $ec "新規ブランチ作成 → 正常終了"
    grep -q "git checkout -b staging" "$mb/calls.log" && pass "git checkout -b staging が呼ばれた" || fail "git checkout -b staging が呼ばれていない"
    grep -q "git push --no-verify -u origin staging" "$mb/calls.log" && pass "git push --no-verify -u origin staging が呼ばれた" || fail "git push --no-verify -u origin staging が呼ばれていない"
    teardown "$td" "$mb" "$mh"
}

# ------------------------------------------------------------------------------
# テスト実行
# ------------------------------------------------------------------------------
test_pattern1_creates_three_branches
test_pattern2_creates_two_branches
test_pattern3_creates_one_branch
test_invalid_choice
test_outside_force_dir
test_comment_header_preserved
test_existing_config_decline
test_existing_config_accept
test_downgrade_shows_removed_branches
test_existing_remote_branch_skipped
test_new_branch_created

print_summary
