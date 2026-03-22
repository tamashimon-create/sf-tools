#!/bin/bash
# ==============================================================================
# test_sf-init.sh - sf-init.sh の単体テスト（モックベース）
# ==============================================================================
#
# 【テストケース】
#   1. ハッピーパス（3ブランチ構成）- フルフロー正常終了
#   2. 必要なツール不足（gh なし）  - 環境チェックで失敗
#   3. リポジトリ作成失敗           - gh repo create が exit 1 を返す
#   4. Salesforce ログイン失敗      - sf org login が exit 1 を返す
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# ==============================================================================
# ヘルパー：モックホームにサブスクリプトのスタブを設置
# ==============================================================================
_stub_subscripts() {
    local mock_home="$1"

    # sf-install.sh スタブ（何もしない）
    printf '#!/bin/bash\nexit 0\n' > "$mock_home/sf-tools/sf-install.sh"
    chmod +x "$mock_home/sf-tools/sf-install.sh"

    # sf-hook.sh スタブ（何もしない）
    printf '#!/bin/bash\nexit 0\n' > "$mock_home/sf-tools/sf-hook.sh"
    chmod +x "$mock_home/sf-tools/sf-hook.sh"

    # sf-branch.sh スタブ（pwd 配下に 3ブランチ構成の branches.txt を生成）
    # sf-init.sh は実行前に cd "$REPO_DIR" しているため pwd = $REPO_DIR になる
    cat > "$mock_home/sf-tools/sf-branch.sh" << 'STUB'
#!/bin/bash
mkdir -p "sf-tools/config"
printf 'main\nstaging\ndevelop\n' > "sf-tools/config/branches.txt"
exit 0
STUB
    chmod +x "$mock_home/sf-tools/sf-branch.sh"

    # repo-settings.sh スタブ（何もしない）
    printf '#!/bin/bash\nexit 0\n' > "$mock_home/sf-tools/repo-settings.sh"
    chmod +x "$mock_home/sf-tools/repo-settings.sh"
}

# ==============================================================================
# ヘルパー：3ブランチ構成用の stdin 入力シーケンスを生成
#
# 入力順:
#   1. GITHUB_OWNER          (phase_ask_project_info)
#   2. PROJECT_NAME          (phase_ask_project_info)
#   3. clone_base            (phase_ask_project_info)
#   4. Y                     (確認プロンプト)
#   5. dev_alias             (phase_initial_sf_login)
#   6. Y                     (Sandbox かどうか)
#   7. (空行)                (register_sf_secret: prod - press_enter)
#   8. (空行)                (register_sf_secret: staging - press_enter)
#   9. (空行)                (register_sf_secret: develop - press_enter)
#  10. (空行)                (phase_setup_pat_token - press_enter)
#  11. ghp_faketoken         (PAT トークン入力 - read -rsp)
#  12. (空行)                (phase_setup_slack - press_enter)
#  13. xoxb-faketoken        (Slack Bot Token 入力 - read -rsp)
#  14. C01ABCDEFGH           (Slack チャンネル ID)
# ==============================================================================
_make_input_3branches() {
    local owner="$1" project="$2" clone_base="$3"
    printf '%s\n%s\n%s\nY\ndevelop\nY\n\n\n\n\nghp_faketoken\n\nxoxb-faketoken\nC01ABCDEFGH\n' \
        "$owner" "$project" "$clone_base"
}

# ==============================================================================
# テスト 1: ハッピーパス（3ブランチ構成）
# ==============================================================================
test_happy_path_3branches() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] ハッピーパス（3ブランチ構成）${CLR_RST}"

    local mb mock_home clone_base
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    clone_base=$(mktemp -d "${TMPDIR:-/tmp}/clone-test-XXXX")

    create_all_mocks "$mb"
    _stub_subscripts "$mock_home"

    # sf org display で sfdxAuthUrl を含む JSON を返す（register_sf_secret で使用）
    export MOCK_SF_ORG_JSON='{"result":{"alias":"prod","sfdxAuthUrl":"force://fakeurl@test.com","id":"00D000000000001AAA"}}'

    local input exit_code
    input=$(_make_input_3branches "tamashimon" "testproject" "$clone_base")

    printf '%s' "$input" \
        | HOME="$mock_home" PATH="$mb:$PATH" \
          bash "$mock_home/sf-tools/sf-init.sh" > /tmp/sf-init-test-happy.log 2>&1
    exit_code=$?

    assert_exit_ok   "$exit_code"                                              "正常終了する"
    assert_file_contains "$MOCK_CALL_LOG" "gh auth status"                    "gh auth status が呼ばれる"
    assert_file_contains "$MOCK_CALL_LOG" "gh repo create"                    "gh repo create が呼ばれる"
    assert_file_contains "$MOCK_CALL_LOG" "git clone"                         "git clone が呼ばれる"
    assert_file_contains "$MOCK_CALL_LOG" "sf org login"                      "sf org login が呼ばれる"
    assert_file_contains "$MOCK_CALL_LOG" "gh secret set SFDX_AUTH_URL_PROD"  "SFDX_AUTH_URL_PROD が登録される"
    assert_file_contains "$MOCK_CALL_LOG" "gh secret set SFDX_AUTH_URL_STG"   "SFDX_AUTH_URL_STG が登録される"
    assert_file_contains "$MOCK_CALL_LOG" "gh secret set SFDX_AUTH_URL_DEV"   "SFDX_AUTH_URL_DEV が登録される"
    assert_file_contains "$MOCK_CALL_LOG" "gh secret set PAT_TOKEN"           "PAT_TOKEN が登録される"
    assert_file_contains "$MOCK_CALL_LOG" "gh secret set SLACK_BOT_TOKEN"     "SLACK_BOT_TOKEN が登録される"
    assert_file_contains "$MOCK_CALL_LOG" "gh secret set SLACK_CHANNEL_ID"    "SLACK_CHANNEL_ID が登録される"
    assert_file_contains "$MOCK_CALL_LOG" "git add"                           "git add が呼ばれる"
    assert_file_contains "$MOCK_CALL_LOG" "git commit"                        "git commit が呼ばれる"
    assert_file_contains "$MOCK_CALL_LOG" "git push"                          "git push が呼ばれる"

    teardown "$mb" "$mock_home" "$clone_base"
    rm -f /tmp/sf-init-test-happy.log
    unset MOCK_SF_ORG_JSON
}

# ==============================================================================
# テスト 2: 必要なツールが不足している場合（gh コマンドなし）
# ==============================================================================
test_missing_tool_gh() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] 必要なツール不足（gh コマンドなし）${CLR_RST}"

    local mb mock_home
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)

    # gh モックを作成しない → PATH="$mb" 限定なら command -v gh が失敗する
    create_mock_git  "$mb"
    create_mock_sf   "$mb"
    create_mock_npm  "$mb"
    create_mock_code "$mb"
    create_mock_node "$mb"
    # create_mock_gh は意図的に省略

    local exit_code
    # PATH を $mb のみに限定して gh が見つからない状態を再現する
    printf 'x\n' \
        | HOME="$mock_home" PATH="$mb" \
          bash "$mock_home/sf-tools/sf-init.sh" > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code" "gh なしで失敗終了する"

    teardown "$mb" "$mock_home"
}

# ==============================================================================
# テスト 3: リポジトリ作成に失敗する場合
# ==============================================================================
test_repo_create_failure() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] リポジトリ作成失敗（gh repo create が exit 1）${CLR_RST}"

    local mb mock_home clone_base
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    clone_base=$(mktemp -d "${TMPDIR:-/tmp}/clone-test-XXXX")

    create_all_mocks "$mb"
    _stub_subscripts "$mock_home"

    export MOCK_GH_REPO_CREATE_EXIT=1

    local input exit_code
    input=$(printf 'tamashimon\ntestproject\n%s\nY\n' "$clone_base")

    printf '%s' "$input" \
        | HOME="$mock_home" PATH="$mb:$PATH" \
          bash "$mock_home/sf-tools/sf-init.sh" > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code"                                              "リポジトリ作成失敗で非ゼロ終了する"
    assert_file_contains "$MOCK_CALL_LOG" "gh repo create"                    "gh repo create が試みられる"

    unset MOCK_GH_REPO_CREATE_EXIT
    teardown "$mb" "$mock_home" "$clone_base"
}

# ==============================================================================
# テスト 4: Salesforce ログインに失敗する場合
# ==============================================================================
test_sf_login_failure() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] Salesforce ログイン失敗（sf org login が exit 1）${CLR_RST}"

    local mb mock_home clone_base
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    clone_base=$(mktemp -d "${TMPDIR:-/tmp}/clone-test-XXXX")

    create_all_mocks "$mb"
    _stub_subscripts "$mock_home"

    export MOCK_SF_LOGIN_EXIT=1

    # phase_initial_sf_login まで到達させる入力
    local input exit_code
    input=$(printf 'tamashimon\ntestproject\n%s\nY\ndevelop\nY\n' "$clone_base")

    printf '%s' "$input" \
        | HOME="$mock_home" PATH="$mb:$PATH" \
          bash "$mock_home/sf-tools/sf-init.sh" > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code"                                              "SF ログイン失敗で非ゼロ終了する"
    assert_file_contains "$MOCK_CALL_LOG" "sf org login"                      "sf org login が試みられる"

    unset MOCK_SF_LOGIN_EXIT
    teardown "$mb" "$mock_home" "$clone_base"
}

# ==============================================================================
# テスト: 許可されていないユーザーは実行できない
# ==============================================================================
test_unauthorized_user() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] 許可されていないユーザー → 実行拒否${CLR_RST}"

    local mb mock_home
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)

    create_all_mocks "$mb"
    export MOCK_GH_API_USER="stranger123"

    local exit_code
    printf 'x\n' \
        | HOME="$mock_home" PATH="$mb:$PATH" \
          bash "$mock_home/sf-tools/sf-init.sh" > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code" "許可されていないユーザーは失敗終了する"

    unset MOCK_GH_API_USER
    teardown "$mb" "$mock_home"
}

# ==============================================================================
# テスト実行
# ==============================================================================
echo ""
echo -e "${CLR_HEAD}========================================"
echo "  sf-init.sh テスト"
echo -e "========================================${CLR_RST}"

test_happy_path_3branches
test_missing_tool_gh
test_repo_create_failure
test_sf_login_failure
test_unauthorized_user

print_summary
