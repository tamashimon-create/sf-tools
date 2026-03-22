#!/bin/bash
# ==============================================================================
# test_common.sh - lib/common.sh の共通関数テスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== common.sh ===${CLR_RST}"

# check_authorized_user をラップする小さなスクリプトを実行するヘルパー
# 引数: mock_home, mock_bin, gh_user
_run_check() {
    local mock_home="$1" mb="$2" gh_user="$3"
    MOCK_GH_API_USER="$gh_user" \
        HOME="$mock_home" PATH="$mb:$PATH" \
        bash -c "
            export SF_INIT_MODE=1
            readonly SCRIPT_NAME=test
            readonly LOG_FILE=\"$mock_home/test.log\"
            readonly LOG_MODE=NEW
            source \"$mock_home/sf-tools/lib/common.sh\"
            check_authorized_user
        " 2>&1
}

# マスターユーザー（tama-create）→ 許可
test_master_user_allowed() {
    local mb mh
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_mock_gh "$mb"

    local out ec
    out=$(_run_check "$mh" "$mb" "tama-create")
    ec=$?

    assert_exit_ok $ec "マスターユーザー（tama-create）は許可される"
    teardown "$mb" "$mh"
}

# allowed-users.txt に記載のユーザー → 許可
test_allowed_file_user_allowed() {
    local mb mh
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_mock_gh "$mb"
    # tamashimon は allowed-users.txt に記載済み

    local out ec
    out=$(_run_check "$mh" "$mb" "tamashimon")
    ec=$?

    assert_exit_ok $ec "allowed-users.txt のユーザー（tamashimon）は許可される"
    teardown "$mb" "$mh"
}

# 不明ユーザー → 拒否
test_unknown_user_denied() {
    local mb mh
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_mock_gh "$mb"

    local out ec
    out=$(_run_check "$mh" "$mb" "stranger123")
    ec=$?

    assert_exit_fail $ec "不明ユーザー（stranger123）は拒否される"
    teardown "$mb" "$mh"
}

# allowed-users.txt が存在しない場合 → マスター以外は拒否
test_no_allowed_file_denies_non_master() {
    local mb mh
    mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_mock_gh "$mb"
    rm -f "$mh/sf-tools/config/allowed-users.txt"

    local out ec
    out=$(_run_check "$mh" "$mb" "tamashimon")
    ec=$?

    assert_exit_fail $ec "allowed-users.txt なし → マスター以外は拒否される"
    teardown "$mb" "$mh"
}

test_master_user_allowed
test_allowed_file_user_allowed
test_unknown_user_denied
test_no_allowed_file_denies_non_master

print_summary
