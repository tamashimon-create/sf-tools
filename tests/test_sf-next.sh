#!/bin/bash
# ==============================================================================
# test_sf-next.sh - sf-next.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-next.sh ===${CLR_RST}"

# git モックに merge-base --is-ancestor / remote get-url を追加
create_mock_git_with_remote() {
    local bin_dir="$1"
    cat > "$bin_dir/git" << 'EOF'
#!/bin/bash
echo "git $*" >> "${MOCK_CALL_LOG:-/dev/null}"
case "$1" in
    symbolic-ref)   echo "${MOCK_GIT_BRANCH:-feature/test}"; exit 0 ;;
    remote)
        if [[ "$2" == "get-url" ]]; then
            echo "https://github.com/test-owner/force-tama.git"
        fi
        exit 0 ;;
    fetch)          exit 0 ;;
    merge-base)
        # merge-base --is-ancestor HEAD origin/<target>
        if [[ "$2" == "--is-ancestor" ]]; then
            target="${4#origin/}"
            for mb in ${MOCK_GIT_MERGED_TARGETS:-}; do
                [[ "$mb" == "$target" ]] && exit 0
            done
            exit 1
        fi
        exit 0 ;;
    *)              exit 0 ;;
esac
EOF
    chmod +x "$bin_dir/git"
}

# --- 3ブランチ構成: develop マージ済み → 次は staging ---
test_next_is_staging() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GIT_MERGED_TARGETS="develop"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "develop 済み → 終了コード 0"
    echo "$out" | grep -q "✓.*develop" \
        && pass "develop が ✓ (マージ済み)" || fail "develop が ✓ (マージ済み)"
    echo "$out" | grep -q "▶.*staging" \
        && pass "staging が ▶ (次のPR先)" || fail "staging が ▶ (次のPR先)"
    echo "$out" | grep -q "✗.*main" \
        && pass "main が ✗ (未着手)" || fail "main が ✗ (未着手)"

    unset MOCK_GIT_BRANCH MOCK_GIT_MERGED_TARGETS
    teardown "$td" "$mb"
}

# --- 3ブランチ構成: develop+staging マージ済み → 次は main ---
test_next_is_main() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GIT_MERGED_TARGETS="develop staging"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "develop+staging 済み → 終了コード 0"
    echo "$out" | grep -q "✓.*develop" \
        && pass "develop が ✓ (マージ済み)" || fail "develop が ✓ (マージ済み)"
    echo "$out" | grep -q "✓.*staging" \
        && pass "staging が ✓ (マージ済み)" || fail "staging が ✓ (マージ済み)"
    echo "$out" | grep -q "▶.*main" \
        && pass "main が ▶ (次のPR先)" || fail "main が ▶ (次のPR先)"

    unset MOCK_GIT_BRANCH MOCK_GIT_MERGED_TARGETS
    teardown "$td" "$mb"
}

# --- 3ブランチ構成: 全ブランチマージ済み → 完了メッセージ ---
test_all_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GIT_MERGED_TARGETS="develop staging main"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "全ブランチマージ済み → 終了コード 0"
    echo "$out" | grep -q "全ブランチへのマージが完了" \
        && pass "完了メッセージが表示される" || fail "完了メッセージが表示される"

    unset MOCK_GIT_BRANCH MOCK_GIT_MERGED_TARGETS
    teardown "$td" "$mb"
}

# --- 3ブランチ構成: 未マージ → 次は develop ---
test_none_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GIT_MERGED_TARGETS=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "未マージ → 終了コード 0"
    echo "$out" | grep -q "▶.*develop" \
        && pass "develop が ▶ (次のPR先)" || fail "develop が ▶ (次のPR先)"
    echo "$out" | grep -q "✗.*staging" \
        && pass "staging が ✗ (未着手)" || fail "staging が ✗ (未着手)"
    echo "$out" | grep -q "✗.*main" \
        && pass "main が ✗ (未着手)" || fail "main が ✗ (未着手)"

    unset MOCK_GIT_BRANCH MOCK_GIT_MERGED_TARGETS
    teardown "$td" "$mb"
}

# --- 2ブランチ構成（main + staging）: 未マージ → 次は staging ---
test_two_branches_none_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    # branches.txt を2ブランチに上書き
    printf 'main\nstaging\n' > "$td/sf-tools/config/branches.txt"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GIT_MERGED_TARGETS=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "2ブランチ未マージ → 終了コード 0"
    echo "$out" | grep -q "▶.*staging" \
        && pass "staging が ▶ (次のPR先)" || fail "staging が ▶ (次のPR先)"
    echo "$out" | grep -q "✗.*main" \
        && pass "main が ✗ (未着手)" || fail "main が ✗ (未着手)"

    unset MOCK_GIT_BRANCH MOCK_GIT_MERGED_TARGETS
    teardown "$td" "$mb"
}

# --- 保護ブランチから実行 → エラー ---
test_protected_branch_blocked() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="main"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "保護ブランチ → エラー終了"
    echo "$out" | grep -q "保護ブランチ" \
        && pass "エラーメッセージが表示される" || fail "エラーメッセージが表示される"

    unset MOCK_GIT_BRANCH
    teardown "$td" "$mb"
}

# --- 1ブランチ構成（main のみ）: 未マージ → main が次のPR先 ---
test_single_branch_none_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    # branches.txt を1ブランチに上書き
    printf 'main\n' > "$td/sf-tools/config/branches.txt"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GIT_MERGED_TARGETS=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "1ブランチ未マージ → 終了コード 0"
    echo "$out" | grep -q "▶.*main" \
        && pass "main が ▶ (次のPR先)" || fail "main が ▶ (次のPR先)"

    unset MOCK_GIT_BRANCH MOCK_GIT_MERGED_TARGETS
    teardown "$td" "$mb"
}

# --- 1ブランチ構成（main のみ）: マージ済み → 完了 ---
test_single_branch_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    printf 'main\n' > "$td/sf-tools/config/branches.txt"
    create_mock_git_with_remote "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GIT_MERGED_TARGETS="main"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "1ブランチマージ済み → 終了コード 0"
    echo "$out" | grep -q "✓.*main" \
        && pass "main が ✓ (マージ済み)" || fail "main が ✓ (マージ済み)"
    echo "$out" | grep -q "全ブランチへのマージが完了" \
        && pass "完了メッセージが表示される" || fail "完了メッセージが表示される"

    unset MOCK_GIT_BRANCH MOCK_GIT_MERGED_TARGETS
    teardown "$td" "$mb"
}

test_next_is_staging
test_next_is_main
test_all_merged
test_none_merged
test_two_branches_none_merged
test_protected_branch_blocked
test_single_branch_none_merged
test_single_branch_merged

print_summary
