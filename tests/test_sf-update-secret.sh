#!/bin/bash
# ==============================================================================
# test_sf-update-secret.sh - sf-update-secret.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-update-secret.sh ===${CLR_RST}"

# モック生成ヘルパー
_create_mocks_update_secret() {
    local mb="$1" td="$2" mode="$3"  # mode: success / sf_fail / gh_fail / cancel

    # git モック
    cat > "$mb/git" << EOF
#!/bin/bash
echo "git \$*" >> "\${MOCK_CALL_LOG:-/dev/null}"
args=("\$@")
cmd="\${args[0]}"
case "\$cmd" in
    remote) echo "https://github.com/testowner/force-test.git"; exit 0 ;;
    rev-parse) echo "$td"; exit 0 ;;
    *)      exit 0 ;;
esac
EOF
    chmod +x "$mb/git"

    # sf モック
    cat > "$mb/sf" << EOF
#!/bin/bash
echo "sf \$*" >> "\${MOCK_CALL_LOG:-/dev/null}"
if [[ "$mode" == "sf_fail" ]]; then
    exit 1
fi
cat << 'SFEOF'
{
  "status": 0,
  "result": {
    "username": "test@example.com",
    "sfdxAuthUrl": "force://PlatformCLI::test_token@example.my.salesforce.com"
  }
}
SFEOF
exit 0
EOF
    chmod +x "$mb/sf"

    # gh モック
    cat > "$mb/gh" << EOF
#!/bin/bash
echo "gh \$*" >> "\${MOCK_CALL_LOG:-/dev/null}"
[[ "$mode" == "gh_fail" ]] && exit 1 || exit 0
EOF
    chmod +x "$mb/gh"
}

# --- 正常系 ---
test_update_secret_success() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    _create_mocks_update_secret "$mb" "$td" "success"

    local out; out=$(cd "$td" && echo "y" | PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-update-secret.sh" 2>&1)
    local ec=$?
    assert_exit_ok $ec "正常系 → 終了コード 0"
    assert_file_contains "$mb/calls.log" "gh secret set SFDX_AUTH_URL_PROD" "PROD が更新される"
    assert_file_contains "$mb/calls.log" "gh secret set SFDX_AUTH_URL_STG"  "STG が更新される"
    assert_file_contains "$mb/calls.log" "gh secret set SFDX_AUTH_URL_DEV"  "DEV が更新される"
    teardown "$td" "$mb"
}

# --- sf org display 失敗（未接続）→ エラー中止 ---
test_update_secret_sf_fail() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    _create_mocks_update_secret "$mb" "$td" "sf_fail"

    local out; out=$(cd "$td" && echo "y" | PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-update-secret.sh" 2>&1)
    local ec=$?
    assert_exit_fail $ec "sf 未接続 → エラー中止"
    echo "$out" > "$mb/out.log"
    assert_file_contains "$mb/out.log" "sf-start.sh" "sf-start.sh の案内が出る"
    teardown "$td" "$mb"
}

# --- gh secret set 失敗 → エラー中止 ---
test_update_secret_gh_fail() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    _create_mocks_update_secret "$mb" "$td" "gh_fail"

    local out; out=$(cd "$td" && echo "y" | PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-update-secret.sh" 2>&1)
    local ec=$?
    assert_exit_fail $ec "gh 失敗 → エラー中止"
    teardown "$td" "$mb"
}

# --- 確認で n → 中断 ---
test_update_secret_cancel() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    _create_mocks_update_secret "$mb" "$td" "success"

    local out; out=$(cd "$td" && echo "n" | PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-update-secret.sh" 2>&1)
    local ec=$?
    assert_exit_fail $ec "確認 n → 中断（終了コード 非0）"
    teardown "$td" "$mb"
}

# --- force-* 以外のディレクトリ → エラー中止 ---
test_update_secret_not_force_dir() {
    local td mb
    td=$(setup_regular_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"
    _create_mocks_update_secret "$mb" "$td" "success"

    local out; out=$(cd "$td" && echo "y" | PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-update-secret.sh" 2>&1)
    local ec=$?
    assert_exit_fail $ec "force-* 以外 → エラー中止"
    teardown "$td" "$mb"
}

test_update_secret_success
test_update_secret_sf_fail
test_update_secret_gh_fail
test_update_secret_cancel
test_update_secret_not_force_dir

echo ""
