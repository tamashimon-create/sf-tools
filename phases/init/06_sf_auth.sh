#!/bin/bash
# ==============================================================================
# 06_sf_auth.sh - Phase 6: Salesforce 認証 URL の設定
# ==============================================================================
# Salesforce 組織への接続認証 URL を GitHub Secrets に登録する。
# ブランチ構成に応じて登録する組織数が変わる。
#
#   6-1. 本番組織（SFDX_AUTH_URL_PROD）※必須
#   6-2. ステージング組織（SFDX_AUTH_URL_STG）※ BRANCH_COUNT >= 2 の場合
#   6-3. 開発組織（SFDX_AUTH_URL_DEV）※ BRANCH_COUNT >= 3 の場合
#
# 【備考】
#   JWT 認証への移行時はこのフェーズのみ差し替えればよい設計。
#   BRANCH_COUNT は Phase 5 で .sf-init.env に書き出される。
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
BRANCH_COUNT="${BRANCH_COUNT:-1}"

# ------------------------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------------------------
# 6-1. 本番組織の Salesforce 認証 URL を登録（必須）
log "HEADER" "Phase 6: Salesforce 認証 URL の設定"
log "HEADER" "Phase 6-1: GitHub Secrets（Salesforce 認証: 本番）を設定します。"
register_sf_secret "prod" "SFDX_AUTH_URL_PROD" "本番組織"
log "SUCCESS" "本番組織の Secret 登録完了。"

# 6-2. ステージング組織（2 階層以上）
if [[ $BRANCH_COUNT -ge 2 ]]; then
    log "HEADER" "Phase 6-2: GitHub Secrets（Salesforce 認証: ステージング）を設定します。"
    register_sf_secret "staging" "SFDX_AUTH_URL_STG" "ステージング組織"
    log "SUCCESS" "ステージング組織の Secret 登録完了。"
fi

# 6-3. 開発組織（3 階層）
if [[ $BRANCH_COUNT -ge 3 ]]; then
    log "HEADER" "Phase 6-3: GitHub Secrets（Salesforce 認証: 開発）を設定します。"
    register_sf_secret "develop" "SFDX_AUTH_URL_DEV" "開発組織"
    log "SUCCESS" "開発組織の Secret 登録完了。"
fi

log "SUCCESS" "Phase 6 完了: Salesforce 認証 URL の設定 OK。"
exit $RET_OK
