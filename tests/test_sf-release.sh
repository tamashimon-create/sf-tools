#!/bin/bash
# ==============================================================================
# test_sf-release.sh - sf-release.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-release.sh ===${CLR_RST}"

# デフォルト（dry-run）実行 → sf deploy に --dry-run が渡される
test_dry_run_default() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    setup_release_dir "$td"
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-release.sh" 2>&1 >/dev/null

    assert_file_contains "$MOCK_CALL_LOG" "project deploy" "デプロイコマンドが呼び出された"
    grep "project deploy" "$MOCK_CALL_LOG" | grep -q "\-\-dry-run" \
        && pass "--dry-run が渡された" || fail "--dry-run が渡された"
    unset MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# --release フラグ → --dry-run なしで実行
test_release_mode() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    setup_release_dir "$td"
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-release.sh" --release --no-open 2>&1 >/dev/null

    grep "project deploy" "$MOCK_CALL_LOG" | grep -qv "\-\-dry-run" \
        && pass "--release → --dry-run なし" || fail "--release → --dry-run なし"
    unset MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# --force フラグ → --ignore-conflicts が渡される
test_force_flag() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    setup_release_dir "$td"
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-release.sh" --force --no-open 2>&1 >/dev/null

    grep "project deploy" "$MOCK_CALL_LOG" | grep -q "\-\-ignore-conflicts" \
        && pass "--force → --ignore-conflicts が渡された" || fail "--force → --ignore-conflicts が渡された"
    unset MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# --target オプション → 指定した組織エイリアスが使われる
test_target_option() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    setup_release_dir "$td"

    cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-release.sh" --target myorg --no-open 2>&1 >/dev/null

    grep "project deploy" "$MOCK_CALL_LOG" | grep -q "myorg" \
        && pass "--target → 指定エイリアスが使われた" || fail "--target → 指定エイリアスが使われた"
    teardown "$td" "$mb"
}

# デプロイ対象が空（コメント行のみ）→ 早期終了
test_empty_deploy_target() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    mkdir -p "$td/release/feature/test"
    echo "feature/test" > "$td/release/branch_name.txt"
    printf '# コメントのみ\n' > "$td/release/feature/test/deploy-target.txt"
    printf '# コメントのみ\n' > "$td/release/feature/test/remove-target.txt"
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-release.sh" --no-open 2>&1)

    echo "$out" | grep -q "デプロイ対象がありません" \
        && pass "対象なし → 警告メッセージが表示された" || fail "対象なし → 警告メッセージが表示された"
    unset MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# 不明なオプション → エラー終了
test_unknown_option() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    setup_release_dir "$td"
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-release.sh" --unknown-option 2>&1)
    local ec=$?

    assert_exit_fail $ec "不明オプション → エラー終了"
    unset MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# force-* 以外で実行 → エラー
test_outside_force_dir() {
    local rd mb
    rd=$(setup_regular_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"

    local out; out=$(cd "$rd" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-release.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "force-* 外 → エラー終了"
    teardown "$rd" "$mb"
}

test_dry_run_default
test_release_mode
test_force_flag
test_target_option
test_empty_deploy_target
test_unknown_option
test_outside_force_dir

print_summary
