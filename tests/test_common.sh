#!/bin/bash
# ==============================================================================
# test_common.sh - lib/common.sh の共通関数テスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== common.sh ===${CLR_RST}"

# check_authorized_user / check_admin_user は廃止済み。
# 権限チェックは警告ボックス + ask_yn に置き換えられたため、テストなし。

# ------------------------------------------------------------------------------
# check_gh_owner のテスト
# ------------------------------------------------------------------------------
_make_mock_gh_bin() {
    local mb user
    mb=$(setup_mock_bin)
    user="${1:-testowner}"
    cat > "$mb/gh" << EOF
#!/bin/bash
echo "gh \$*" >> "\${MOCK_CALL_LOG:-/dev/null}"
case "\$1 \$2" in
    "api user") echo "${user}" ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$mb/gh"
    echo "$mb"
}

# check_gh_owner を呼び出す小さなラッパースクリプトを生成する
_make_check_gh_owner_script() {
    local script
    script=$(mktemp /tmp/test-check-gh-owner-XXXX.sh)
    cat > "$script" << EOF
#!/bin/bash
readonly SCRIPT_NAME=test
readonly LOG_FILE=/dev/null
readonly LOG_MODE=NEW
export SF_INIT_MODE=1
source '${SF_TOOLS_DIR}/lib/common.sh'
check_gh_owner "\$1"
EOF
    chmod +x "$script"
    echo "$script"
}

# 一致 → 正常終了
test_check_gh_owner_match() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_gh_owner: ユーザーが一致 → 正常終了${CLR_RST}"

    local mb script
    mb=$(_make_mock_gh_bin "testowner")
    script=$(_make_check_gh_owner_script)

    PATH="$mb:$PATH" bash "$script" "testowner" > /dev/null 2>&1
    assert_exit_ok $? "ユーザー一致 → 終了コード 0"

    rm -f "$script"; teardown "$mb"
}

# 不一致 → die
test_check_gh_owner_mismatch() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_gh_owner: ユーザーが不一致 → die${CLR_RST}"

    local mb script
    mb=$(_make_mock_gh_bin "other-user")
    script=$(_make_check_gh_owner_script)

    PATH="$mb:$PATH" bash "$script" "testowner" > /dev/null 2>&1
    assert_exit_fail $? "ユーザー不一致 → die"

    rm -f "$script"; teardown "$mb"
}

# gh が空を返す → スキップして正常終了
test_check_gh_owner_skip_on_empty() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_gh_owner: gh が空を返す → スキップ${CLR_RST}"

    local mb script
    mb=$(setup_mock_bin)
    cat > "$mb/gh" << 'GHEOF'
#!/bin/bash
exit 0
GHEOF
    chmod +x "$mb/gh"
    script=$(_make_check_gh_owner_script)

    PATH="$mb:$PATH" bash "$script" "testowner" > /dev/null 2>&1
    assert_exit_ok $? "gh 空返却 → スキップして終了コード 0"

    rm -f "$script"; teardown "$mb"
}

test_check_gh_owner_match
test_check_gh_owner_mismatch
test_check_gh_owner_skip_on_empty

print_summary
