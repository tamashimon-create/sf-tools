#!/bin/bash
# ==============================================================================
# 02_project_info.sh - Phase 2: プロジェクト情報の確認
# ==============================================================================
# フォルダ構成から GITHUB_OWNER とプロジェクト名を自動導出し、ユーザーに確認する。
# 確認後、.sf-init.env に変数を書き出して後続フェーズと共有する。
#
# 【導出ルール】
#   カレント: ~/home/{github-owner}/{company}/init/（sf-init.sh が自動作成・移動）
#   PROJECT_NAME  = {company}（init の 1 つ上）
#   GITHUB_OWNER  = {github-owner}（init の 2 つ上）
#   REPO_NAME     = force-{company}
#   REPO_FULL_NAME= {github-owner}/force-{company}
#   REPO_DIR      = {PWD}/force-{company}
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
source "${SF_TOOLS_DIR}/phases/init/init-common.sh"

# 変数の復元（前フェーズで書き出した .sf-init.env を読み込む）
SF_INIT_ENV_FILE="${SF_INIT_ENV_FILE:-${PWD}/.sf-init.env}"
[[ -f "$SF_INIT_ENV_FILE" ]] && source "$SF_INIT_ENV_FILE"

# ------------------------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------------------------
log "HEADER" "Phase 2: プロジェクト情報の確認"

log "INFO" "プロジェクト情報を確認中..."

# init の 1つ上 = {company}、2つ上 = {github-owner}
PROJECT_NAME=$(basename "$(dirname "$PWD")")
GITHUB_OWNER=$(basename "$(dirname "$(dirname "$PWD")")")
REPO_NAME="force-${PROJECT_NAME}"
REPO_FULL_NAME="${GITHUB_OWNER}/${REPO_NAME}"
REPO_DIR="${PWD}/${REPO_NAME}"

# GitHub オーナー名バリデーション（英数字・ハイフンのみ・先頭末尾はハイフン不可）
if [[ -z "$GITHUB_OWNER" ]] || \
   [[ ! "$GITHUB_OWNER" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$ ]]; then
    die "GitHub オーナー名が無効です: \"${GITHUB_OWNER}\"
  2つ上のフォルダ名を GitHub ユーザー名として使用します。
  正しいフォルダ構成で実行してください:
    ~/home/{github-owner}/{company}/"
fi

log "INFO" "  GitHub オーナー（フォルダ自動取得）: ${GITHUB_OWNER}"
log "INFO" "  リポジトリ名（自動導出）: ${REPO_NAME}"

# 確認表示
echo ""
echo "  --------------------------------------------------"
echo "  リポジトリ : ${REPO_FULL_NAME}"
echo "  クローン先 : ${REPO_DIR}"
echo "  --------------------------------------------------"
echo ""
ask_yn "▶ よろしいですか？" || die "セットアップを中断しました。"

# .sf-init.env に変数を書き出す（後続フェーズで source して使用）
{
    printf 'GITHUB_OWNER="%s"\n'    "$GITHUB_OWNER"
    printf 'PROJECT_NAME="%s"\n'   "$PROJECT_NAME"
    printf 'REPO_NAME="%s"\n'      "$REPO_NAME"
    printf 'REPO_FULL_NAME="%s"\n' "$REPO_FULL_NAME"
    printf 'REPO_DIR="%s"\n'       "$REPO_DIR"
} > "$SF_INIT_ENV_FILE"

log "SUCCESS" "Phase 2 完了: プロジェクト情報の確認 OK。"
exit $RET_OK
