#!/bin/bash
# ==============================================================================
# 05_setup_branches.sh - Phase 5: ブランチ構成
# ==============================================================================
# sf-branch.sh（インタラクティブなメニュー）を実行してブランチ階層を選択・作成する。
# 完了後、branches.txt からブランチ数を取得して .sf-init.env に追記する。
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

[[ -z "$REPO_DIR" ]] && die "REPO_DIR が未設定です。Phase 2 が完了しているか確認してください。"

# ------------------------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------------------------
log "HEADER" "Phase 5: ブランチ構成"

log "INFO" "ブランチ構成を選択してください。"

cd "$REPO_DIR" || die "ディレクトリに移動できません: $REPO_DIR"

# sf-branch.sh はインタラクティブなメニューを持つため run ではなく直接実行する
# （run ラッパー経由では stdin/stdout の制御が崩れる）
log "CMD" "[${SCRIPT_NAME}] bash ${SF_TOOLS_DIR}/bin/sf-branch.sh"
bash "${SF_TOOLS_DIR}/bin/sf-branch.sh" \
    || die "sf-branch.sh の実行に失敗しました。"

# branches.txt からブランチ階層数を取得
BRANCH_COUNT=1
branches_file="$REPO_DIR/sf-tools/config/branches.txt"
if [[ -f "$branches_file" ]]; then
    BRANCH_COUNT=$(grep -v '^[[:space:]]*#' "$branches_file" \
        | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
fi

# .sf-init.env に BRANCH_COUNT を追記
printf 'BRANCH_COUNT="%s"\n' "$BRANCH_COUNT" >> "$SF_INIT_ENV_FILE"

log "SUCCESS" "Phase 5 完了: ブランチ構成 OK（${BRANCH_COUNT} 階層）。"
exit $RET_OK
