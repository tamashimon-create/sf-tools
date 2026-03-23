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
#   5. 許可されていないユーザー     - check_authorized_user で失敗
#   6. 無効なフォルダ構成           - GitHub オーナー名バリデーション失敗
# ==============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"

# ==============================================================================
# ヘルパー：{github-owner}/{company}/init/ 構造を作成
# 戻り値: ベースディレクトリのパス（teardown に渡す）
# ==============================================================================
_setup_init_dir() {
    local github_owner="${1:-tamashimon}"
    local company="${2:-testproject}"
    local base
    base=$(mktemp -d "${TMPDIR:-/tmp}/test-init-XXXX")
    mkdir -p "$base/$github_owner/$company/init"
    echo "$base"
}

# ==============================================================================
# ヘルパー：sf-init.sh 用 gh モック（repo view カウンター付き）
#
# 通常フロー:
#   - 1回目の "repo view" → exit 1（リポジトリ未存在 → create をトリガー）
#   - 2回目以降の "repo view" → exit 0（作成後の確認チェック）
#
# MOCK_GH_REPO_CREATE_EXIT が非ゼロの場合:
#   - "repo view" は常に exit 1（作成失敗を再現）
# ==============================================================================
create_mock_gh_for_init() {
    local bin_dir="$1"
    cat > "$bin_dir/gh" << 'GHEOF'
#!/bin/bash
echo "gh $*" >> "${MOCK_CALL_LOG:-/dev/null}"
case "$1 $2" in
    "auth status") exit "${MOCK_GH_AUTH_STATUS_EXIT:-0}" ;;
    "auth login")  exit "${MOCK_GH_AUTH_LOGIN_EXIT:-0}" ;;
    "repo view")
        # create が失敗設定の場合は常に「未存在」を返す
        if [[ -n "${MOCK_GH_REPO_CREATE_EXIT:-}" && "${MOCK_GH_REPO_CREATE_EXIT}" != "0" ]]; then
            exit 1
        fi
        # 初回: 未存在（create をトリガー） / 2回目以降: 存在（作成確認 OK）
        _cnt_file="${MOCK_CALL_LOG%/*}/repo_view.cnt"
        _cnt=$(cat "$_cnt_file" 2>/dev/null || echo 0)
        _cnt=$((_cnt + 1))
        echo "$_cnt" > "$_cnt_file"
        [[ $_cnt -eq 1 ]] && exit 1 || exit 0 ;;
    "repo create") exit "${MOCK_GH_REPO_CREATE_EXIT:-0}" ;;
    "secret set")  exit "${MOCK_GH_SECRET_SET_EXIT:-0}" ;;
    "api user")    echo "${MOCK_GH_API_USER:-tama-create}" ;;
    *) exit 0 ;;
esac
GHEOF
    chmod +x "$bin_dir/gh"
}

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
# ヘルパー：3ブランチ構成用の stdin 入力シーケンス
#
# 入力順:
#   1. Y             (確認プロンプト - phase_load_project_info)
#   2. \n            (press_enter - register_sf_secret: prod)
#   3. \n            (press_enter - register_sf_secret: staging)
#   4. Y             (Sandbox? - staging)
#   5. \n            (press_enter - register_sf_secret: develop)
#   6. Y             (Sandbox? - develop)
#   7. \n            (press_enter - phase_setup_pat_token)
#   8. ghp_faketoken (PAT トークン)
#   9. \n            (press_enter - phase_setup_slack)
#  10. xoxb-faketoken (Slack Bot Token)
#  11. C01ABCDEFGH   (Slack チャンネル ID)
#  12. N             (init フォルダ削除をスキップ)
# ==============================================================================
_make_input_3branches() {
    printf 'Y\n\n\nY\n\nY\n\nghp_faketoken\n\nxoxb-faketoken\nC01ABCDEFGH\nN\n'
}

# ==============================================================================
# テスト 1: ハッピーパス（3ブランチ構成）
# ==============================================================================
test_happy_path_3branches() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] ハッピーパス（3ブランチ構成）${CLR_RST}"

    local mb mock_home init_base init_dir
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    init_base=$(_setup_init_dir "tamashimon" "testproject")
    init_dir="$init_base/tamashimon/testproject/init"

    create_all_mocks "$mb"
    create_mock_gh_for_init "$mb"   # repo view カウンター付きモックで上書き
    _stub_subscripts "$mock_home"

    # sf org display で sfdxAuthUrl を含む JSON を返す（register_sf_secret で使用）
    export MOCK_SF_ORG_JSON='{"result":{"alias":"prod","sfdxAuthUrl":"force://fakeurl@test.com","id":"00D000000000001AAA"}}'

    local exit_code
    _make_input_3branches \
        | ( cd "$init_dir" && HOME="$mock_home" PATH="$mb:$PATH" \
              bash "$mock_home/sf-tools/sf-init.sh" ) \
          > /tmp/sf-init-test-happy.log 2>&1
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

    teardown "$mb" "$mock_home" "$init_base"
    rm -f /tmp/sf-init-test-happy.log
    unset MOCK_SF_ORG_JSON
}

# ==============================================================================
# テスト 2: 必要なツールが不足している場合（gh コマンドなし）
# ==============================================================================
test_missing_tool_gh() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] 必要なツール不足（gh コマンドなし）${CLR_RST}"

    local mb mock_home init_base init_dir
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    init_base=$(_setup_init_dir "tamashimon" "testproject")
    init_dir="$init_base/tamashimon/testproject/init"

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
        | ( cd "$init_dir" && HOME="$mock_home" PATH="$mb" \
              bash "$mock_home/sf-tools/sf-init.sh" ) > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code" "gh なしで失敗終了する"

    teardown "$mb" "$mock_home" "$init_base"
}

# ==============================================================================
# テスト 3: リポジトリ作成に失敗する場合
# ==============================================================================
test_repo_create_failure() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] リポジトリ作成失敗（gh repo create が exit 1）${CLR_RST}"

    local mb mock_home init_base init_dir
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    init_base=$(_setup_init_dir "tamashimon" "testproject")
    init_dir="$init_base/tamashimon/testproject/init"

    create_all_mocks "$mb"
    create_mock_gh_for_init "$mb"
    _stub_subscripts "$mock_home"

    export MOCK_GH_REPO_CREATE_EXIT=1

    local exit_code
    # confirm のみ入力（リポジトリ作成で失敗するため以降は不要）
    printf 'Y\n' \
        | ( cd "$init_dir" && HOME="$mock_home" PATH="$mb:$PATH" \
              bash "$mock_home/sf-tools/sf-init.sh" ) > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code"                                              "リポジトリ作成失敗で非ゼロ終了する"
    assert_file_contains "$MOCK_CALL_LOG" "gh repo create"                    "gh repo create が試みられる"

    unset MOCK_GH_REPO_CREATE_EXIT
    teardown "$mb" "$mock_home" "$init_base"
}

# ==============================================================================
# テスト 4: Salesforce ログインに失敗する場合
# ==============================================================================
test_sf_login_failure() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] Salesforce ログイン失敗（sf org login が exit 1）${CLR_RST}"

    local mb mock_home init_base init_dir
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    init_base=$(_setup_init_dir "tamashimon" "testproject")
    init_dir="$init_base/tamashimon/testproject/init"

    create_all_mocks "$mb"
    create_mock_gh_for_init "$mb"
    _stub_subscripts "$mock_home"

    export MOCK_SF_LOGIN_EXIT=1

    # confirm + prod の press_enter まで入力（sf org login で失敗するため以降は不要）
    local exit_code
    printf 'Y\n\n' \
        | ( cd "$init_dir" && HOME="$mock_home" PATH="$mb:$PATH" \
              bash "$mock_home/sf-tools/sf-init.sh" ) > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code"                                              "SF ログイン失敗で非ゼロ終了する"
    assert_file_contains "$MOCK_CALL_LOG" "sf org login"                      "sf org login が試みられる"

    unset MOCK_SF_LOGIN_EXIT
    teardown "$mb" "$mock_home" "$init_base"
}

# ==============================================================================
# テスト 5: 許可されていないユーザーは実行できない
# ==============================================================================
test_unauthorized_user() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] 許可されていないユーザー → 実行拒否${CLR_RST}"

    local mb mock_home init_base init_dir
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)
    init_base=$(_setup_init_dir "tamashimon" "testproject")
    init_dir="$init_base/tamashimon/testproject/init"

    create_all_mocks "$mb"
    create_mock_gh_for_init "$mb"
    export MOCK_GH_API_USER="stranger123"

    local exit_code
    printf 'x\n' \
        | ( cd "$init_dir" && HOME="$mock_home" PATH="$mb:$PATH" \
              bash "$mock_home/sf-tools/sf-init.sh" ) > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code" "許可されていないユーザーは失敗終了する"

    unset MOCK_GH_API_USER
    teardown "$mb" "$mock_home" "$init_base"
}

# ==============================================================================
# テスト 6: 無効なフォルダ構成（GitHub オーナー名バリデーション失敗）
# ==============================================================================
test_invalid_owner_folder() {
    echo ""
    echo -e "${CLR_HEAD}[TEST] 無効なフォルダ構成 → GitHub オーナー名エラー${CLR_RST}"

    local mb mock_home init_base init_dir
    mb=$(setup_mock_bin)
    export MOCK_CALL_LOG="$mb/calls.log"
    mock_home=$(setup_mock_home)

    # GitHub ユーザー名に使用できない文字（スペース）を含むフォルダ名
    init_base=$(mktemp -d "${TMPDIR:-/tmp}/test-init-XXXX")
    mkdir -p "$init_base/invalid owner/testproject/init"
    init_dir="$init_base/invalid owner/testproject/init"

    create_all_mocks "$mb"
    create_mock_gh_for_init "$mb"

    local exit_code
    printf 'x\n' \
        | ( cd "$init_dir" && HOME="$mock_home" PATH="$mb:$PATH" \
              bash "$mock_home/sf-tools/sf-init.sh" ) > /dev/null 2>&1
    exit_code=$?

    assert_exit_fail "$exit_code" "無効なオーナー名で失敗終了する"

    teardown "$mb" "$mock_home" "$init_base"
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
test_invalid_owner_folder

print_summary
