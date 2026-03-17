#!/bin/bash
# ==============================================================================
# test_sf-deploy.sh - sf-deploy.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-deploy.sh ===${CLR_RST}"

# 機能ブランチ → sf-release.sh が --release --force で呼び出される
test_feature_branch() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    setup_release_dir "$td" "feature/deploy-test"

    export MOCK_GIT_BRANCH="feature/deploy-test"
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-deploy.sh" --no-open 2>&1)
    local ec=$?

    assert_exit_ok $ec "機能ブランチ → 終了コード 0"
    # sf-release.sh が --release --force で呼ばれたことを確認（deploy コマンドが実行されログに残る）
    assert_file_contains "$MOCK_CALL_LOG" "project deploy" "sf-release.sh が呼び出された（deploy 実行）"
    grep "project deploy" "$MOCK_CALL_LOG" | grep -qv "\-\-dry-run" \
        && pass "--release が渡された（dry-run なし）" || fail "--release が渡された（dry-run なし）"
    grep "project deploy" "$MOCK_CALL_LOG" | grep -q "\-\-ignore-conflicts" \
        && pass "--force が渡された（ignore-conflicts）" || fail "--force が渡された（ignore-conflicts）"
    unset MOCK_GIT_BRANCH MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# main ブランチ → エラー終了
test_main_branch_blocked() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    export MOCK_GIT_BRANCH="main"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-deploy.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "main ブランチ → エラー終了"
    ! grep -q "project deploy" "$MOCK_CALL_LOG" 2>/dev/null \
        && pass "main ブランチ → デプロイは実行されない" \
        || fail "main ブランチ → デプロイは実行されない"
    unset MOCK_GIT_BRANCH
    teardown "$td" "$mb"
}

# staging ブランチ → エラー終了
test_staging_branch_blocked() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    export MOCK_GIT_BRANCH="staging"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-deploy.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "staging ブランチ → エラー終了"
    unset MOCK_GIT_BRANCH
    teardown "$td" "$mb"
}

# develop ブランチ → エラー終了
test_development_branch_blocked() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"
    export MOCK_GIT_BRANCH="develop"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-deploy.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "develop ブランチ → エラー終了"
    unset MOCK_GIT_BRANCH
    teardown "$td" "$mb"
}

# force-* 以外で実行 → エラー
test_outside_force_dir() {
    local rd mb
    rd=$(setup_regular_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_all_mocks "$mb"

    local out; out=$(cd "$rd" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-deploy.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "force-* 外 → エラー終了"
    teardown "$rd" "$mb"
}

test_feature_branch
test_main_branch_blocked
test_staging_branch_blocked
test_development_branch_blocked
test_outside_force_dir

print_summary
