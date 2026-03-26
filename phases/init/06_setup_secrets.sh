#!/bin/bash
# ==============================================================================
# 06_setup_secrets.sh - Phase 6: GitHub Secrets の設定
# ==============================================================================
# Salesforce 認証 URL・PAT_TOKEN・Slack 連携の Secret をまとめて設定する。
#
# 【処理順序】
#   6-1. 本番組織（SFDX_AUTH_URL_PROD）※必須
#   6-2. ステージング組織（SFDX_AUTH_URL_STG）※ BRANCH_COUNT >= 2 の場合
#   6-3. 開発組織（SFDX_AUTH_URL_DEV）※ BRANCH_COUNT >= 3 の場合
#   6-4. PAT_TOKEN（GitHub Personal Access Token）
#   6-5. SLACK_BOT_TOKEN / SLACK_CHANNEL_ID
#
# 【備考】
#   BRANCH_COUNT は Phase 5 で .sf-init.env に書き出される。
#   PAT_TOKEN_VALUE は .sf-init.env に書き出し、Phase 7 で使用する。
# ==============================================================================

# SF_TOOLS_DIR は sf-init.sh（司令塔）から export される
PHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SF_TOOLS_DIR="${SF_TOOLS_DIR:-$(dirname "$PHASE_DIR")}"

readonly SCRIPT_NAME="sf-init"
mkdir -p "$HOME/sf-tools/logs" 2>/dev/null || true
readonly LOG_FILE="$HOME/sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="APPEND"  # 司令塔が NEW で初期化済みのため追記
export SF_INIT_MODE=1

source "${SF_TOOLS_DIR}/lib/common.sh"
source "${SF_TOOLS_DIR}/lib/init-common.sh"

# 変数の復元（前フェーズで書き出した .sf-init.env を読み込む）
SF_INIT_ENV_FILE="${SF_INIT_ENV_FILE:-${PWD}/.sf-init.env}"
[[ -f "$SF_INIT_ENV_FILE" ]] && source "$SF_INIT_ENV_FILE"

[[ -z "$REPO_FULL_NAME" ]] && die "REPO_FULL_NAME が未設定です。Phase 2 が完了しているか確認してください。"
[[ -z "$PROJECT_NAME" ]]   && die "PROJECT_NAME が未設定です。Phase 2 が完了しているか確認してください。"
BRANCH_COUNT="${BRANCH_COUNT:-1}"

# ------------------------------------------------------------------------------
# 6-1. 本番組織の Salesforce 認証 URL を登録（必須）
# ------------------------------------------------------------------------------
log "HEADER" "Phase 6-1: GitHub Secrets（Salesforce 認証: 本番）を設定します。"
register_sf_secret "prod" "SFDX_AUTH_URL_PROD" "本番組織"
log "SUCCESS" "本番組織の Secret 登録完了。"

# ------------------------------------------------------------------------------
# 6-2. ステージング組織（2 階層以上）
# ------------------------------------------------------------------------------
if [[ $BRANCH_COUNT -ge 2 ]]; then
    log "HEADER" "Phase 6-2: GitHub Secrets（Salesforce 認証: ステージング）を設定します。"
    register_sf_secret "staging" "SFDX_AUTH_URL_STG" "ステージング組織"
    log "SUCCESS" "ステージング組織の Secret 登録完了。"
fi

# ------------------------------------------------------------------------------
# 6-3. 開発組織（3 階層）
# ------------------------------------------------------------------------------
if [[ $BRANCH_COUNT -ge 3 ]]; then
    log "HEADER" "Phase 6-3: GitHub Secrets（Salesforce 認証: 開発）を設定します。"
    register_sf_secret "develop" "SFDX_AUTH_URL_DEV" "開発組織"
    log "SUCCESS" "開発組織の Secret 登録完了。"
fi

# ------------------------------------------------------------------------------
# 6-4. PAT_TOKEN の作成支援と登録
# ------------------------------------------------------------------------------
log "HEADER" "Phase 6-4: GitHub Secrets（PAT_TOKEN）を設定します。"
echo ""
echo "  ワークフローがブランチ保護をバイパスして push するために必要です。"
echo ""
echo "  ブラウザで Personal access tokens (classic) のページを開きます。"
echo "  【手順】"
echo "    1. 「Generate new token」→「Generate new token (classic)」をクリック"
echo "    2. 以下の設定でトークンを作成してください:"
echo ""
echo "       Note       : sf-metasync-${PROJECT_NAME}"
echo "       Expiration : No expiration"
echo "       Scopes     : ✅ repo（全選択）  ✅ workflow"
echo ""
echo "    3. 「Generate token」をクリックしてトークンをコピー"
echo ""
open_browser "https://github.com/settings/tokens"
press_enter "トークンをコピーしたら Enter を押してください..."

PAT_TOKEN_VALUE=""
while [[ -z "$PAT_TOKEN_VALUE" ]]; do
    read_or_quit PAT_TOKEN_VALUE "  生成されたトークンを貼り付けてください（q で中断）: "
    echo ""
done

echo "$PAT_TOKEN_VALUE" | run gh secret set PAT_TOKEN -R "$REPO_FULL_NAME" \
    || die "PAT_TOKEN の登録に失敗しました。"

# PAT_TOKEN_VALUE を .sf-init.env に書き出す（Phase 7 の push で使用）
printf 'PAT_TOKEN_VALUE="%s"\n' "$PAT_TOKEN_VALUE" >> "$SF_INIT_ENV_FILE"

log "SUCCESS" "PAT_TOKEN を登録しました。"

# ------------------------------------------------------------------------------
# 6-5. Slack Bot Token と Channel ID の登録
# ------------------------------------------------------------------------------
log "HEADER" "Phase 6-5: GitHub Secrets（Slack 連携）を設定します。"
echo ""
echo "  ブラウザで Slack API ページを開きます。"
echo "  以下の手順で Bot Token を取得してください:"
echo ""
echo "    1. 「Create New App」→「From scratch」をクリック"
echo "    2. 以下を設定して「Create App」をクリック:"
echo "       App Name  : sf-notify-${PROJECT_NAME}"
echo "       Workspace : 通知先のワークスペースを選択"
echo "    3. 左メニュー「OAuth & Permissions」をクリック"
echo "    4. 「ボットトークンのスコープ」→「OAuth スコープを追加する」をクリック"
echo "       chat:write と入力して追加"
echo "    5. 左メニュー「Install App」→「Install to <ワークスペース名>」をクリック"
echo "    6. 「許可する」をクリック"
echo "    7. 左メニュー「OAuth & Permissions」に戻り「Bot User OAuth Token」（xoxb-...）をコピー"
echo ""
open_browser "https://api.slack.com/apps"
press_enter "Bot Token を取得したら Enter を押してください..."

slack_token=""
while [[ -z "$slack_token" ]]; do
    read_or_quit slack_token "  Bot User OAuth Token を貼り付けてください（q で中断）: "
    echo ""
done

echo "$slack_token" | run gh secret set SLACK_BOT_TOKEN -R "$REPO_FULL_NAME" \
    || die "SLACK_BOT_TOKEN の登録に失敗しました。"
log "SUCCESS" "SLACK_BOT_TOKEN を登録しました。"

echo ""
echo "  通知先 Slack チャンネルの ID を入力します。"
echo "  確認方法: チャンネルを開く → チャンネル名をクリック → 最下部に「チャンネル ID」"
echo "            C から始まる文字列（例: C01ABCDEFGH）"
echo ""

channel_id=""
while [[ -z "$channel_id" ]]; do
    read_or_quit channel_id "  チャンネル ID（q で中断）: "
done

echo "$channel_id" | run gh secret set SLACK_CHANNEL_ID -R "$REPO_FULL_NAME" \
    || die "SLACK_CHANNEL_ID の登録に失敗しました。"
log "SUCCESS" "SLACK_CHANNEL_ID を登録しました。"

echo ""
log "WARNING" "【重要】Slack チャンネルへの Bot 招待が必要です"
echo "  通知先チャンネルで以下のコマンドを実行してください:"
echo ""
echo "    /invite @sf-notify-${PROJECT_NAME}"
echo ""
echo "  Bot がチャンネルに参加していないと通知が届きません。"
echo ""
press_enter "Bot の招待が完了したら Enter を押してください..."

log "SUCCESS" "Phase 6 完了: GitHub Secrets の設定 OK。"
exit $RET_OK
