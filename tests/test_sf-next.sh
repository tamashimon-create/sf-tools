#!/bin/bash
# ==============================================================================
# test_sf-next.sh - sf-next.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-next.sh ===${CLR_RST}"

# gh モック生成（MOCK_GH_* 環境変数で挙動を制御）
create_mock_gh() {
    local bin_dir="$1"
    cat > "$bin_dir/gh" << 'GHEOF'
#!/bin/bash
echo "gh $*" >> "${MOCK_CALL_LOG:-/dev/null}"
# gh pr list --head <branch> --base <target> --state merged/open
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    base="" state=""
    prev=""
    for arg in "$@"; do
        [[ "$prev" == "--base" ]]  && base="$arg"
        [[ "$prev" == "--state" ]] && state="$arg"
        prev="$arg"
    done
    # MOCK_GH_MERGED_BASES: マージ済みのベースブランチ（スペース区切り）
    # MOCK_GH_OPEN_BASES: オープン中のベースブランチ（スペース区切り）
    if [[ "$state" == "merged" ]]; then
        for mb in ${MOCK_GH_MERGED_BASES:-}; do
            if [[ "$mb" == "$base" ]]; then
                echo '{"number":100}'
                exit 0
            fi
        done
        echo ""
        exit 0
    fi
    if [[ "$state" == "open" ]]; then
        for ob in ${MOCK_GH_OPEN_BASES:-}; do
            if [[ "$ob" == "$base" ]]; then
                echo '{"number":200}'
                exit 0
            fi
        done
        echo ""
        exit 0
    fi
fi
exit 0
GHEOF
    chmod +x "$bin_dir/gh"
}

# git モックに remote get-url を追加
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
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GH_MERGED_BASES="develop"
    export MOCK_GH_OPEN_BASES=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "develop 済み → 終了コード 0"
    echo "$out" | grep -q "✅.*develop" \
        && pass "develop が ✅ (マージ済み)" || fail "develop が ✅ (マージ済み)"
    echo "$out" | grep -q "⏭️.*staging" \
        && pass "staging が ⏭️ (次のPR先)" || fail "staging が ⏭️ (次のPR先)"
    echo "$out" | grep -q "⬜.*main" \
        && pass "main が ⬜ (未着手)" || fail "main が ⬜ (未着手)"

    unset MOCK_GIT_BRANCH MOCK_GH_MERGED_BASES MOCK_GH_OPEN_BASES
    teardown "$td" "$mb"
}

# --- 3ブランチ構成: develop+staging マージ済み → 次は main ---
test_next_is_main() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GH_MERGED_BASES="develop staging"
    export MOCK_GH_OPEN_BASES=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "develop+staging 済み → 終了コード 0"
    echo "$out" | grep -q "✅.*develop" \
        && pass "develop が ✅ (マージ済み)" || fail "develop が ✅ (マージ済み)"
    echo "$out" | grep -q "✅.*staging" \
        && pass "staging が ✅ (マージ済み)" || fail "staging が ✅ (マージ済み)"
    echo "$out" | grep -q "⏭️.*main" \
        && pass "main が ⏭️ (次のPR先)" || fail "main が ⏭️ (次のPR先)"

    unset MOCK_GIT_BRANCH MOCK_GH_MERGED_BASES MOCK_GH_OPEN_BASES
    teardown "$td" "$mb"
}

# --- 3ブランチ構成: 全ブランチマージ済み → 完了メッセージ ---
test_all_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GH_MERGED_BASES="develop staging main"
    export MOCK_GH_OPEN_BASES=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "全ブランチマージ済み → 終了コード 0"
    echo "$out" | grep -q "全ブランチへのマージが完了" \
        && pass "完了メッセージが表示される" || fail "完了メッセージが表示される"

    unset MOCK_GIT_BRANCH MOCK_GH_MERGED_BASES MOCK_GH_OPEN_BASES
    teardown "$td" "$mb"
}

# --- 3ブランチ構成: 未マージ → 次は develop ---
test_none_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GH_MERGED_BASES=""
    export MOCK_GH_OPEN_BASES=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "未マージ → 終了コード 0"
    echo "$out" | grep -q "⏭️.*develop" \
        && pass "develop が ⏭️ (次のPR先)" || fail "develop が ⏭️ (次のPR先)"
    echo "$out" | grep -q "⬜.*staging" \
        && pass "staging が ⬜ (未着手)" || fail "staging が ⬜ (未着手)"
    echo "$out" | grep -q "⬜.*main" \
        && pass "main が ⬜ (未着手)" || fail "main が ⬜ (未着手)"

    unset MOCK_GIT_BRANCH MOCK_GH_MERGED_BASES MOCK_GH_OPEN_BASES
    teardown "$td" "$mb"
}

# --- オープン中のPR表示 ---
test_open_pr() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GH_MERGED_BASES="develop"
    export MOCK_GH_OPEN_BASES="staging"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "オープンPR → 終了コード 0"
    echo "$out" | grep -q "✅.*develop" \
        && pass "develop が ✅ (マージ済み)" || fail "develop が ✅ (マージ済み)"
    echo "$out" | grep -q "staging.*オープン中" \
        && pass "staging が 🔄 (オープン中)" || fail "staging が 🔄 (オープン中)"

    unset MOCK_GIT_BRANCH MOCK_GH_MERGED_BASES MOCK_GH_OPEN_BASES
    teardown "$td" "$mb"
}

# --- 2ブランチ構成（main + staging）: 未マージ → 次は staging ---
test_two_branches_none_merged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    # branches.txt を2ブランチに上書き
    printf 'main\nstaging\n' > "$td/sf-tools/config/branches.txt"
    create_mock_git_with_remote "$mb"
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"
    export MOCK_GH_MERGED_BASES=""
    export MOCK_GH_OPEN_BASES=""

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "2ブランチ未マージ → 終了コード 0"
    echo "$out" | grep -q "⏭️.*staging" \
        && pass "staging が ⏭️ (次のPR先)" || fail "staging が ⏭️ (次のPR先)"
    echo "$out" | grep -q "⬜.*main" \
        && pass "main が ⬜ (未着手)" || fail "main が ⬜ (未着手)"

    unset MOCK_GIT_BRANCH MOCK_GH_MERGED_BASES MOCK_GH_OPEN_BASES
    teardown "$td" "$mb"
}

# --- 保護ブランチから実行 → エラー ---
test_protected_branch_blocked() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_git_with_remote "$mb"
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="main"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "保護ブランチ → エラー終了"
    echo "$out" | grep -q "保護ブランチ" \
        && pass "エラーメッセージが表示される" || fail "エラーメッセージが表示される"

    unset MOCK_GIT_BRANCH
    teardown "$td" "$mb"
}

# --- 1ブランチ構成（main のみ）→ main にPR ---
test_single_branch() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    # branches.txt を1ブランチに上書き
    printf 'main\n' > "$td/sf-tools/config/branches.txt"
    create_mock_git_with_remote "$mb"
    create_mock_gh "$mb"

    export MOCK_GIT_BRANCH="feature/my-feature"

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-next.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "1ブランチ → 終了コード 0"
    echo "$out" | grep -q "main にPRを出してください" \
        && pass "main へのPR案内が表示される" || fail "main へのPR案内が表示される"

    unset MOCK_GIT_BRANCH
    teardown "$td" "$mb"
}

test_next_is_staging
test_next_is_main
test_all_merged
test_none_merged
test_open_pr
test_two_branches_none_merged
test_protected_branch_blocked
test_single_branch

print_summary
