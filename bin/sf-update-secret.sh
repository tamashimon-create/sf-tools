#!/bin/bash
# ==============================================================================
# sf-update-secret.sh - GitHub Secrets の SFDX_AUTH_URL_* を再登録する
# ==============================================================================
# ローカルの tama エイリアスから sfdxAuthUrl を取得し、
# GitHub Secrets（PROD / STG / DEV）を一括更新する。
#
# 動作:
#   1. force-* ディレクトリかチェック
#   2. git remote から対象リポジトリを自動取得
#   3. sf org display で sfdxAuthUrl を取得（未接続ならエラー中止）
#   4. 更新内容を表示して確認（y/n）
#   5. SFDX_AUTH_URL_PROD / STG / DEV を gh secret set で更新
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. common.sh 用の事前設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"

# ------------------------------------------------------------------------------
# 2. 共通ライブラリの読み込み
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

# ------------------------------------------------------------------------------
# 3. 必須コマンドのチェック
# ------------------------------------------------------------------------------
command -v sf >/dev/null 2>&1 || die "コマンドが見つかりません: sf"
command -v gh >/dev/null 2>&1 || die "コマンドが見つかりません: gh"
command -v git >/dev/null 2>&1 || die "コマンドが見つかりません: git"

# ------------------------------------------------------------------------------
# 4. force-* ディレクトリかチェック
# ------------------------------------------------------------------------------
check_force_dir

# ------------------------------------------------------------------------------
# 5. git remote からリポジトリ名を取得
# ------------------------------------------------------------------------------
REMOTE_URL=$(git remote get-url origin 2>/dev/null) \
    || die "git remote の取得に失敗しました。Git リポジトリか確認してください。"

REPO_FULL_NAME=$(echo "$REMOTE_URL" \
    | sed 's|.*github\.com[:/]\(.*\)\.git|\1|' \
    | sed 's|.*github\.com[:/]\(.*\)$|\1|')

[[ -z "$REPO_FULL_NAME" ]] && die "リポジトリ名を取得できませんでした。Remote URL: ${REMOTE_URL}"

# ------------------------------------------------------------------------------
# 6. sfdxAuthUrl を取得
# ------------------------------------------------------------------------------
log "HEADER" "GitHub Secrets の SFDX_AUTH_URL_* を更新します (${SCRIPT_NAME}.sh)"
log "INFO" "リポジトリ: ${REPO_FULL_NAME}"
log "INFO" "tama エイリアスから認証 URL を取得中..."

# run 不使用: 出力に sfdxAuthUrl を含むためログへの記録を避ける
SF_JSON=$(sf org display --verbose --json --target-org tama 2>/dev/null || true)
AUTH_URL=$(echo "$SF_JSON" \
    | grep '"sfdxAuthUrl"' \
    | sed 's/.*"sfdxAuthUrl": *"\([^"]*\)".*/\1/')

if [[ -z "$AUTH_URL" ]]; then
    die "認証 URL を取得できませんでした。\n  先に sf-start.sh を実行して tama 組織に接続してください。"
fi

# 組織情報を表示
ORG_USER=$(echo "$SF_JSON" \
    | grep '"username"' \
    | head -1 \
    | sed 's/.*"username": *"\([^"]*\)".*/\1/')
log "INFO" "接続中の組織: ${ORG_USER}"

# ------------------------------------------------------------------------------
# 7. 確認
# ------------------------------------------------------------------------------
log "INFO" "以下の Secrets を更新します:"
log "INFO" "  - SFDX_AUTH_URL_PROD"
log "INFO" "  - SFDX_AUTH_URL_STG"
log "INFO" "  - SFDX_AUTH_URL_DEV"

ask_yn "▶ よろしいですか？" || die "更新を中断しました。"

# ------------------------------------------------------------------------------
# 8. GitHub Secrets を更新
# ------------------------------------------------------------------------------
for SECRET_NAME in SFDX_AUTH_URL_PROD SFDX_AUTH_URL_STG SFDX_AUTH_URL_DEV; do
    echo "$AUTH_URL" | run gh secret set "$SECRET_NAME" -R "$REPO_FULL_NAME" \
        || die "${SECRET_NAME} の更新に失敗しました。"
    log "SUCCESS" "${SECRET_NAME} を更新しました。"
done

log "SUCCESS" "すべての SFDX_AUTH_URL_* の更新が完了しました。"
