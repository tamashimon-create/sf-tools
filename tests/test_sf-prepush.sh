#!/bin/bash
# ==============================================================================
# test_sf-prepush.sh - sf-prepush.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-prepush.sh ===${CLR_RST}"

# ------------------------------------------------------------------------------
# ヘルパー: sf-prepush.sh を force-* ディレクトリで実行
# ------------------------------------------------------------------------------
run_prepush() {
    local td="$1" mb="$2"
    cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-prepush.sh" 2>&1
}

# ------------------------------------------------------------------------------
# main ブランチへの直接プッシュを禁止
# ------------------------------------------------------------------------------
test_block_push_to_main() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="main"
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_fail $ec "main への直接プッシュ → エラー終了"
    echo "$out" | grep -q "禁止" && pass "main プッシュ禁止メッセージが出る" \
                                  || fail "main プッシュ禁止メッセージが出る"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH
}

# ------------------------------------------------------------------------------
# 自ブランチ・main ともに同期済み → 正常終了
# ------------------------------------------------------------------------------
test_all_synced() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_LOG_BRANCH_OUTPUT=""
    export MOCK_GIT_LOG_MAIN_OUTPUT=""
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_ok $ec "全同期済み → 正常終了"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LOG_BRANCH_OUTPUT MOCK_GIT_LOG_MAIN_OUTPUT
}

# ------------------------------------------------------------------------------
# 自ブランチのリモートがまだ存在しない → スキップして正常終了
# ------------------------------------------------------------------------------
test_own_branch_not_on_remote() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/new"
    export MOCK_GIT_LS_REMOTE_EXIT=2   # ls-remote が失敗 → リモートにブランチなし
    export MOCK_GIT_LOG_MAIN_OUTPUT=""
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_ok $ec "自ブランチがリモートにない → スキップして正常終了"
    grep -q "merge" "$mb/calls.log" \
        && fail "自ブランチのマージが呼ばれていない" \
        || pass "自ブランチのマージが呼ばれていない"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LS_REMOTE_EXIT MOCK_GIT_LOG_MAIN_OUTPUT
}

# ------------------------------------------------------------------------------
# 自ブランチに未取り込みコミットあり → マージ成功
# ------------------------------------------------------------------------------
test_own_branch_behind_merge_ok() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_LOG_BRANCH_OUTPUT="abc1234 someone else's commit"
    export MOCK_GIT_LOG_MAIN_OUTPUT=""
    export MOCK_GIT_MERGE_EXIT=0
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_ok $ec "自ブランチのマージ成功 → 正常終了"
    grep -q "git-merge-arg: origin/feature/test" "$mb/calls.log" \
        && pass "origin/feature/test をマージした" \
        || fail "origin/feature/test をマージした"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LOG_BRANCH_OUTPUT MOCK_GIT_LOG_MAIN_OUTPUT MOCK_GIT_MERGE_EXIT
}

# ------------------------------------------------------------------------------
# 自ブランチのマージ失敗 → merge --abort が呼ばれてエラー終了
# ------------------------------------------------------------------------------
test_own_branch_merge_conflict() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_LOG_BRANCH_OUTPUT="abc1234 conflicting commit"
    export MOCK_GIT_LOG_MAIN_OUTPUT=""
    export MOCK_GIT_MERGE_EXIT=1
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_fail $ec "自ブランチのマージ失敗 → エラー終了"
    grep -q "git merge --abort" "$mb/calls.log" \
        && pass "merge --abort が呼ばれた" \
        || fail "merge --abort が呼ばれた"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LOG_BRANCH_OUTPUT MOCK_GIT_LOG_MAIN_OUTPUT MOCK_GIT_MERGE_EXIT
}

# ------------------------------------------------------------------------------
# main に未取り込みコミットあり → マージ成功
# ------------------------------------------------------------------------------
test_main_behind_merge_ok() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_LOG_BRANCH_OUTPUT=""
    export MOCK_GIT_LOG_MAIN_OUTPUT="def5678 main update"
    export MOCK_GIT_MERGE_EXIT=0
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_ok $ec "main のマージ成功 → 正常終了"
    grep -q "git-merge-arg: origin/main" "$mb/calls.log" \
        && pass "origin/main をマージした" \
        || fail "origin/main をマージした"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LOG_BRANCH_OUTPUT MOCK_GIT_LOG_MAIN_OUTPUT MOCK_GIT_MERGE_EXIT
}

# ------------------------------------------------------------------------------
# main のマージ失敗 → merge --abort が呼ばれてエラー終了
# ------------------------------------------------------------------------------
test_main_merge_conflict() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_LOG_BRANCH_OUTPUT=""
    export MOCK_GIT_LOG_MAIN_OUTPUT="def5678 main conflicting commit"
    export MOCK_GIT_MERGE_EXIT=1
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_fail $ec "main のマージ失敗 → エラー終了"
    grep -q "git merge --abort" "$mb/calls.log" \
        && pass "merge --abort が呼ばれた" \
        || fail "merge --abort が呼ばれた"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LOG_BRANCH_OUTPUT MOCK_GIT_LOG_MAIN_OUTPUT MOCK_GIT_MERGE_EXIT
}

# ------------------------------------------------------------------------------
# 自ブランチ・main 両方に更新あり → 順番通りにマージ
# ------------------------------------------------------------------------------
test_both_behind_merge_order() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_LOG_BRANCH_OUTPUT="abc1234 branch update"
    export MOCK_GIT_LOG_MAIN_OUTPUT="def5678 main update"
    export MOCK_GIT_MERGE_EXIT=0
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_ok $ec "両方マージ成功 → 正常終了"
    # 自ブランチ → main の順でマージされていることを確認
    local branch_line main_line
    branch_line=$(grep -n "git-merge-arg: origin/feature/test" "$mb/calls.log" | cut -d: -f1)
    main_line=$(grep -n "git-merge-arg: origin/main" "$mb/calls.log" | cut -d: -f1)
    [[ -n "$branch_line" && -n "$main_line" && "$branch_line" -lt "$main_line" ]] \
        && pass "自ブランチ → main の順でマージされた" \
        || fail "自ブランチ → main の順でマージされた"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LOG_BRANCH_OUTPUT MOCK_GIT_LOG_MAIN_OUTPUT MOCK_GIT_MERGE_EXIT
}

# ------------------------------------------------------------------------------
# staging / develop への直接プッシュを禁止
# ------------------------------------------------------------------------------
test_block_push_to_staging() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="staging"
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_fail $ec "staging への直接プッシュ → エラー終了"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH
}

test_block_push_to_develop() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="develop"
    create_mock_git "$mb"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_fail $ec "develop への直接プッシュ → エラー終了"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH
}

# ------------------------------------------------------------------------------
# 構文エラーあり → プッシュを中断
# ------------------------------------------------------------------------------
test_syntax_error_blocks_push() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    create_mock_git "$mb"

    # 存在しないパスを記述した deploy-target.txt を作成
    mkdir -p "$td/sf-tools/release/feature/test"
    echo "feature/test" > "$td/sf-tools/release/branch_name.txt"
    printf '[files]\nforce-app/main/default/classes/NotExist.cls\n' \
        > "$td/sf-tools/release/feature/test/deploy-target.txt"
    printf '[files]\n' > "$td/sf-tools/release/feature/test/remove-target.txt"

    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_fail $ec "構文エラーあり → プッシュを中断"
    echo "$out" | grep -q "構文エラー" \
        && pass "構文エラーメッセージが表示された" \
        || fail "構文エラーメッセージが表示された"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH
}

# ------------------------------------------------------------------------------
# branch_name.txt がない → スキップして正常終了
# ------------------------------------------------------------------------------
test_syntax_skip_when_no_branch_name() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_LOG_BRANCH_OUTPUT=""
    export MOCK_GIT_LOG_MAIN_OUTPUT=""
    create_mock_git "$mb"

    # branch_name.txt を作成しない（setup_force_dir のデフォルト状態）
    local out; out=$(run_prepush "$td" "$mb")
    local ec=$?

    assert_exit_ok $ec "branch_name.txt なし → スキップして正常終了"
    teardown "$td" "$mb"
    unset MOCK_GIT_BRANCH MOCK_GIT_LOG_BRANCH_OUTPUT MOCK_GIT_LOG_MAIN_OUTPUT
}

# ------------------------------------------------------------------------------
# 実行
# ------------------------------------------------------------------------------
test_block_push_to_main
test_block_push_to_staging
test_block_push_to_develop
test_syntax_error_blocks_push
test_syntax_skip_when_no_branch_name
test_all_synced
test_own_branch_not_on_remote
test_own_branch_behind_merge_ok
test_own_branch_merge_conflict
test_main_behind_merge_ok
test_main_merge_conflict
test_both_behind_merge_order

print_summary
