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

# ==============================================================================
# check_admin_user テスト
# ==============================================================================
# check_admin_user は ./sf-tools/config/admin-users.txt（プロジェクトローカル）を参照するため、
# テストは force-* ディレクトリ内（td）から実行する。
# setup_force_dir が admin-users.txt（tamashimon を含む）を自動生成する。

# check_admin_user をラップするヘルパー（GITHUB_ACTIONS は未設定）
# 引数: td=force-*ディレクトリ  mb=モックbinディレクトリ  gh_user=GitHubユーザー名
_run_check_admin() {
    local td="$1" mb="$2" gh_user="$3"
    MOCK_GH_API_USER="$gh_user" \
        PATH="$mb:$PATH" \
        bash -c "
            unset GITHUB_ACTIONS
            export SF_INIT_MODE=1
            readonly SCRIPT_NAME=test
            readonly LOG_FILE=\"$td/sf-tools/logs/test.log\"
            readonly LOG_MODE=NEW
            cd \"$td\"
            source \"$SF_TOOLS_DIR/lib/common.sh\"
            check_admin_user
        " 2>&1
}

# マスターユーザー（tama-create）→ 許可
test_admin_master_user_allowed() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_admin_user: マスターユーザー → 許可${CLR_RST}"
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_gh "$mb"

    local ec
    _run_check_admin "$td" "$mb" "tama-create" > /dev/null 2>&1
    ec=$?

    assert_exit_ok $ec "マスターユーザー（tama-create）は管理者として許可される"
    teardown "$td" "$mb"
}

# admin-users.txt 記載ユーザー（tamashimon）→ 許可
test_admin_file_user_allowed() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_admin_user: admin-users.txt 記載ユーザー → 許可${CLR_RST}"
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_gh "$mb"
    # setup_force_dir が ./sf-tools/config/admin-users.txt（tamashimon を含む）を自動生成する

    local ec
    _run_check_admin "$td" "$mb" "tamashimon" > /dev/null 2>&1
    ec=$?

    assert_exit_ok $ec "admin-users.txt のユーザー（tamashimon）は管理者として許可される"
    teardown "$td" "$mb"
}

# 非管理者ユーザー → 拒否
test_admin_non_admin_denied() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_admin_user: 非管理者ユーザー → 拒否${CLR_RST}"
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_gh "$mb"

    local ec
    _run_check_admin "$td" "$mb" "stranger123" > /dev/null 2>&1
    ec=$?

    assert_exit_fail $ec "非管理者ユーザー（stranger123）は拒否される"
    teardown "$td" "$mb"
}

# admin-users.txt が存在しない場合 → マスター以外は拒否
test_admin_no_file_denies_non_master() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_admin_user: admin-users.txt なし → 拒否${CLR_RST}"
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_gh "$mb"
    rm -f "$td/sf-tools/config/admin-users.txt"

    local ec
    _run_check_admin "$td" "$mb" "tamashimon" > /dev/null 2>&1
    ec=$?

    assert_exit_fail $ec "admin-users.txt なし → マスター以外は拒否される"
    teardown "$td" "$mb"
}

# GITHUB_ACTIONS=true → スキップ（常に許可）
test_admin_github_actions_skip() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] check_admin_user: GITHUB_ACTIONS=true → スキップ${CLR_RST}"
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    create_mock_gh "$mb"

    local ec
    MOCK_GH_API_USER="stranger123" \
        GITHUB_ACTIONS="true" \
        PATH="$mb:$PATH" \
        bash -c "
            export SF_INIT_MODE=1
            readonly SCRIPT_NAME=test
            readonly LOG_FILE=\"$td/sf-tools/logs/test.log\"
            readonly LOG_MODE=NEW
            cd \"$td\"
            source \"$SF_TOOLS_DIR/lib/common.sh\"
            check_admin_user
        " > /dev/null 2>&1
    ec=$?

    assert_exit_ok $ec "GITHUB_ACTIONS=true → 非管理者でもスキップされ許可される"
    teardown "$td" "$mb"
}

test_admin_master_user_allowed
test_admin_file_user_allowed
test_admin_non_admin_denied
test_admin_github_actions_skip

print_summary
