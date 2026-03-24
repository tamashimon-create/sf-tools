#!/bin/bash
# ==============================================================================
# test_helper.sh - sf-tools テスト共通ユーティリティ
# ==============================================================================

SF_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

CLR_PASS='\033[32m'
CLR_FAIL='\033[31m'
CLR_HEAD='\033[36m'
CLR_RST='\033[0m'

# ------------------------------------------------------------------------------
# アサーション関数
# ------------------------------------------------------------------------------
pass() { echo -e "  ${CLR_PASS}[PASS]${CLR_RST} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo -e "  ${CLR_FAIL}[FAIL]${CLR_RST} $1${2:+  → $2}"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { echo -e "  \033[33m[SKIP]\033[0m $1"; }

assert_exit_ok()         { [[ $1 -eq 0 ]]  && pass "$2" || fail "$2" "終了コード: $1（期待: 0）"; }
assert_exit_fail()       { [[ $1 -ne 0 ]]  && pass "$2" || fail "$2" "終了コード 0（期待: 非ゼロ）"; }
assert_file_exists()     { [[ -f "$1" ]]   && pass "$2" || fail "$2" "ファイルが存在しない: $1"; }
assert_file_not_exists() { [[ ! -f "$1" ]] && pass "$2" || fail "$2" "ファイルが存在する: $1"; }
assert_dir_exists()      { [[ -d "$1" ]]   && pass "$2" || fail "$2" "ディレクトリが存在しない: $1"; }
assert_dir_not_exists()  { [[ ! -d "$1" ]] && pass "$2" || fail "$2" "ディレクトリが存在する: $1"; }
assert_file_contains()   { grep -qF -- "$2" "$1" 2>/dev/null && pass "$3" || fail "$3" "'$2' が '$1' に含まれていない"; }
assert_file_not_contains() { ! grep -qF -- "$2" "$1" 2>/dev/null && pass "$3" || fail "$3" "'$2' が '$1' に含まれている"; }
assert_executable()      { [[ -x "$1" ]]   && pass "$2" || fail "$2" "実行権限がない: $1"; }
assert_equals()          { [[ "$1" == "$2" ]] && pass "$3" || fail "$3" "期待: '$2'  実際: '$1'"; }

# ------------------------------------------------------------------------------
# テスト環境セットアップ
# ------------------------------------------------------------------------------

# force-* テスト用ディレクトリを作成（.git/hooks 付き）
setup_force_dir() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/force-test-XXXX")
    mkdir -p "$dir/logs" "$dir/.git/hooks" "$dir/.sf" "$dir/.sfdx" \
             "$dir/sf-tools/config" "$dir/sf-tools/release" "$dir/sf-tools/logs"
    echo "ApexClass" > "$dir/sf-tools/config/metadata.txt"
    printf 'main\nstaging\ndevelop\n' > "$dir/sf-tools/config/branches.txt"
    echo "$dir"
}

# force-* でない通常ディレクトリを作成
setup_regular_dir() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/regular-test-XXXX")
    mkdir -p "$dir/logs"
    echo "$dir"
}

# モックバイナリディレクトリを作成して返す
# 呼び出し元で必ず export MOCK_CALL_LOG="$mb/calls.log" を行うこと
setup_mock_bin() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/mock-bin-XXXX")
    echo "$dir"
}

# HOME 用の仮ディレクトリを作成し、sf-tools 一式をコピー
setup_mock_home() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/mock-home-XXXX")
    mkdir -p "$dir/sf-tools"
    # .git / logs は不要なので除外してコピー（tar で高速化）
    (cd "$SF_TOOLS_DIR" && tar cf - \
        --exclude='.git' \
        --exclude='logs' \
        . ) | tar xf - -C "$dir/sf-tools/"
    mkdir -p "$dir/sf-tools/logs" "$dir/sf-tools/config"
    echo "$dir"
}

# テスト環境を一括クリーンアップ（可変長引数）
teardown() {
    local arg
    for arg in "$@"; do
        [[ -n "$arg" ]] && rm -rf "$arg" 2>/dev/null
    done
}

# リリースディレクトリとターゲットリストを生成
setup_release_dir() {
    local td="$1" branch="${2:-feature/test}"
    mkdir -p "$td/sf-tools/release/$branch"
    echo "$branch" > "$td/sf-tools/release/branch_name.txt"
    # sf-check.sh のファイル存在チェックを通すため、参照ファイルを実際に作成する
    mkdir -p "$td/force-app/main/default/classes"
    touch "$td/force-app/main/default/classes/TestClass.cls"
    printf '[files]\nforce-app/main/default/classes/TestClass.cls\n' \
        > "$td/sf-tools/release/$branch/deploy-target.txt"
    printf '[files]\n' > "$td/sf-tools/release/$branch/remove-target.txt"
}

# ------------------------------------------------------------------------------
# 標準モックスクリプト生成
# ------------------------------------------------------------------------------

# git モック（MOCK_GIT_* 環境変数で挙動を制御）
create_mock_git() {
    local bin_dir="$1"
    cat > "$bin_dir/git" << 'EOF'
#!/bin/bash
echo "git $*" >> "${MOCK_CALL_LOG:-/dev/null}"
case "$1" in
    -C)
        case "$3" in
            pull) exit "${MOCK_GIT_PULL_EXIT:-0}" ;;
            symbolic-ref) echo "${MOCK_GIT_BRANCH:-feature/test}"; exit 0 ;;
            *) exit 0 ;;
        esac ;;
    symbolic-ref)   echo "${MOCK_GIT_BRANCH:-feature/test}"; exit 0 ;;
    pull)           exit "${MOCK_GIT_PULL_EXIT:-0}" ;;
    log)
        if [[ "$*" == *"..origin/main"* ]]; then
            echo "${MOCK_GIT_LOG_MAIN_OUTPUT:-}"
        else
            echo "${MOCK_GIT_LOG_BRANCH_OUTPUT:-}"
        fi
        exit 0 ;;
    fetch)          exit 0 ;;
    push)           exit "${MOCK_GIT_PUSH_EXIT:-0}" ;;
    stash)          exit 0 ;;
    rebase)         exit "${MOCK_GIT_REBASE_EXIT:-0}" ;;
    merge)
        echo "git-merge-arg: $2" >> "${MOCK_CALL_LOG:-/dev/null}"
        exit "${MOCK_GIT_MERGE_EXIT:-0}" ;;
    checkout)
        if [[ -n "${MOCK_GIT_CHECKOUT_FAIL_BRANCH:-}" && "$2" == "${MOCK_GIT_CHECKOUT_FAIL_BRANCH}" ]]; then
            exit 1
        fi
        exit "${MOCK_GIT_CHECKOUT_EXIT:-0}" ;;
    status)         exit 0 ;;
    clone)
        _dest=""
        for _a in "$@"; do _dest="$_a"; done
        mkdir -p "$_dest/.git" "$_dest/sf-tools/config" \
                 "$_dest/sf-tools/release" "$_dest/sf-tools/logs" "$_dest/logs"
        exit "${MOCK_GIT_CLONE_EXIT:-0}" ;;
    add)            exit 0 ;;
    commit)         exit 0 ;;
    diff-index)
        if [[ -n "${MOCK_GIT_DIFF_EXIT_2ND:-}" ]]; then
            _cnt_file="${MOCK_CALL_LOG%/*}/diffidx.cnt"
            _cnt=$(cat "$_cnt_file" 2>/dev/null || echo 0)
            _cnt=$((_cnt + 1))
            echo "$_cnt" > "$_cnt_file"
            [[ $_cnt -ge 2 ]] && exit "${MOCK_GIT_DIFF_EXIT_2ND}"
        fi
        exit "${MOCK_GIT_DIFF_EXIT:-0}" ;;
    config)         exit 0 ;;
    remote)         echo "https://github.com/mock-owner/mock-repo.git"; exit 0 ;;
    ls-remote)      exit "${MOCK_GIT_LS_REMOTE_EXIT:-0}" ;;
    update-git-for-windows) exit 0 ;;
    *)              exit 0 ;;
esac
EOF
    chmod +x "$bin_dir/git"
}

# sf（Salesforce CLI）モック
create_mock_sf() {
    local bin_dir="$1"
    cat > "$bin_dir/sf" << 'EOF'
#!/bin/bash
echo "sf $*" >> "${MOCK_CALL_LOG:-/dev/null}"
case "$1 $2" in
    "org display")
        # sf-start.sh の grep/cut パース（各キーが1行前提）に対応するため
        # コンパクト JSON を , と { で改行展開して出力する
        echo "${MOCK_SF_ORG_JSON:-{\"result\":{\"alias\":\"testorg\",\"id\":\"00D000000000001AAA\"}}}" \
            | sed 's/[,{]/&\n/g'
        exit "${MOCK_SF_ORG_DISPLAY_EXIT:-0}" ;;
    "org login")    exit "${MOCK_SF_LOGIN_EXIT:-0}" ;;
    "org logout")   exit 0 ;;
    "org open")     exit 0 ;;
    "alias unset")  exit 0 ;;
    "config set")   exit 0 ;;
    "update"|"update --no-prompt") exit 0 ;;
    "sgd source")
        OUT_DIR=""
        PREV=""
        for arg in "$@"; do
            [[ "$PREV" == "--output-dir" ]] && OUT_DIR="$arg"
            PREV="$arg"
        done
        [[ -n "$OUT_DIR" ]] && mkdir -p "$OUT_DIR/package" && echo '<Package/>' > "$OUT_DIR/package/package.xml"
        exit "${MOCK_SF_SGD_EXIT:-0}" ;;
    "project retrieve") exit 0 ;;
    "project generate")
        OUT_DIR=""; OUT_NAME="package.xml"; PREV=""
        for arg in "$@"; do
            [[ "$PREV" == "--output-dir" ]] && OUT_DIR="$arg"
            [[ "$PREV" == "--name" ]] && OUT_NAME="$arg"
            PREV="$arg"
        done
        [[ -n "$OUT_DIR" ]] && mkdir -p "$OUT_DIR" && \
            printf '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>60.0</version></Package>\n' \
            > "$OUT_DIR/$OUT_NAME"
        exit 0 ;;
    "project deploy")
        echo '{"status":0,"result":{"success":true}}'
        exit "${MOCK_SF_DEPLOY_EXIT:-0}" ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$bin_dir/sf"
}

# npm モック
create_mock_npm() {
    local bin_dir="$1"
    cat > "$bin_dir/npm" << 'EOF'
#!/bin/bash
echo "npm $*" >> "${MOCK_CALL_LOG:-/dev/null}"
exit "${MOCK_NPM_EXIT:-0}"
EOF
    chmod +x "$bin_dir/npm"
}

# code（VS Code）モック
create_mock_code() {
    local bin_dir="$1"
    cat > "$bin_dir/code" << 'EOF'
#!/bin/bash
echo "code $*" >> "${MOCK_CALL_LOG:-/dev/null}"
exit 0
EOF
    chmod +x "$bin_dir/code"
}

# gh（GitHub CLI）モック（MOCK_GH_* 環境変数で挙動を制御）
create_mock_gh() {
    local bin_dir="$1"
    cat > "$bin_dir/gh" << 'EOF'
#!/bin/bash
echo "gh $*" >> "${MOCK_CALL_LOG:-/dev/null}"
case "$1 $2" in
    "auth status") exit "${MOCK_GH_AUTH_STATUS_EXIT:-0}" ;;
    "auth login")  exit "${MOCK_GH_AUTH_LOGIN_EXIT:-0}" ;;
    "repo create") exit "${MOCK_GH_REPO_CREATE_EXIT:-0}" ;;
    "secret set")  exit "${MOCK_GH_SECRET_SET_EXIT:-0}" ;;
    "api user")    echo "${MOCK_GH_API_USER:-tama-create}" ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$bin_dir/gh"
}

# node モック
create_mock_node() {
    local bin_dir="$1"
    cat > "$bin_dir/node" << 'EOF'
#!/bin/bash
echo "node $*" >> "${MOCK_CALL_LOG:-/dev/null}"
echo "v20.0.0"
exit 0
EOF
    chmod +x "$bin_dir/node"
}

# 全モックを一括生成
create_all_mocks() {
    local bin_dir="$1"
    create_mock_git "$bin_dir"
    create_mock_sf "$bin_dir"
    create_mock_npm "$bin_dir"
    create_mock_code "$bin_dir"
    create_mock_gh "$bin_dir"
    create_mock_node "$bin_dir"
}

# ------------------------------------------------------------------------------
# テスト結果サマリー
# ------------------------------------------------------------------------------
print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED))
    echo ""
    echo "========================================"
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${CLR_PASS}結果: ${TESTS_PASSED}/${total} 件すべて成功${CLR_RST}"
        return 0
    else
        echo -e "${CLR_FAIL}結果: ${TESTS_PASSED}/${total} 件成功 / ${TESTS_FAILED} 件失敗${CLR_RST}"
        return 1
    fi
}
