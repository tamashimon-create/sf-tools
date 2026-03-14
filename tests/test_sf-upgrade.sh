#!/bin/bash
# ==============================================================================
# test_sf-upgrade.sh - sf-upgrade.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-upgrade.sh ===${CLR_RST}"

# 正常実行 → npm / sf / git が呼び出される
test_normal_run() {
    local td mb
    td=$(mktemp -d "${TMPDIR:-/tmp}/test-upgrade-XXXX")
    mkdir -p "$td/logs"
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-upgrade.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "正常実行 → 終了コード 0"
    assert_file_contains "$MOCK_CALL_LOG" "npm install" "npm が呼び出された"
    assert_file_contains "$MOCK_CALL_LOG" "sf update" "sf update が呼び出された"
    assert_file_contains "$MOCK_CALL_LOG" "git update-git-for-windows" "git update が呼び出された"
    teardown "$td" "$mb"
}

# npm が存在しない → WARNING で続行、正常終了
test_no_npm() {
    local td mb
    td=$(mktemp -d "${TMPDIR:-/tmp}/test-upgrade-XXXX")
    mkdir -p "$td/logs"
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    # npm モックを作成しない（PATH に npm が存在しない状態）
    create_mock_git "$mb"
    create_mock_sf "$mb"
    create_mock_code "$mb"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-upgrade.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "npm なし → 正常終了（続行）"
    echo "$out" | grep -q "WARNING" && pass "WARNING ログが出力された" || fail "WARNING ログが出力された"
    teardown "$td" "$mb"
}

# sf が存在しない → WARNING で続行、正常終了
test_no_sf() {
    local td mb
    td=$(mktemp -d "${TMPDIR:-/tmp}/test-upgrade-XXXX")
    mkdir -p "$td/logs"
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    # sf モックを作成しない
    create_mock_git "$mb"
    create_mock_npm "$mb"
    create_mock_code "$mb"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-upgrade.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "sf なし → 正常終了（続行）"
    echo "$out" | grep -q "WARNING" && pass "WARNING ログが出力された" || fail "WARNING ログが出力された"
    teardown "$td" "$mb"
}

# git update-git-for-windows は npm・sf の後に実行される（順序確認）
test_git_update_is_last() {
    local td mb
    td=$(mktemp -d "${TMPDIR:-/tmp}/test-upgrade-XXXX")
    mkdir -p "$td/logs"
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"

    cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-upgrade.sh" 2>&1 >/dev/null

    local npm_line sf_line git_line
    npm_line=$(grep -n "npm install" "$MOCK_CALL_LOG" | head -1 | cut -d: -f1)
    sf_line=$(grep -n "sf update" "$MOCK_CALL_LOG" | head -1 | cut -d: -f1)
    git_line=$(grep -n "git update-git-for-windows" "$MOCK_CALL_LOG" | head -1 | cut -d: -f1)

    if [[ -n "$npm_line" && -n "$sf_line" && -n "$git_line" ]] \
        && [[ $npm_line -lt $git_line && $sf_line -lt $git_line ]]; then
        pass "git update は npm・sf の後に実行された"
    else
        fail "git update は npm・sf の後に実行された" "npm:$npm_line sf:$sf_line git:$git_line"
    fi
    teardown "$td" "$mb"
}

test_normal_run
test_no_npm
test_no_sf
test_git_update_is_last

print_summary
