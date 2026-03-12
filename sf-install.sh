#!/bin/bash

# ==============================================================================
# sf-install.sh - sf-tools の最新化・プロジェクトラッパー生成スクリプト
# ==============================================================================
# sf-start.sh から自動呼び出しされるため、通常は直接実行する必要はありません。
#
# 【動作】
#   1. ~/sf-tools を git pull で最新化
#   2. プロジェクト側のラッパースクリプト (sf-start.sh / sf-restart.sh) を生成
#
# 【前提】
#   ~/sf-tools は初回インストール済みであること。
#   初回インストール: git clone <sf-tools の URL> ~/sf-tools
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"
readonly SILENT_EXEC=0

# ------------------------------------------------------------------------------
# 2. 共通ライブラリの読み込み
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

# ------------------------------------------------------------------------------
# 3. 初期チェック
# ------------------------------------------------------------------------------
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "sf-tools のセットアップを開始します..."

trap 'rm -f ./cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. 定数定義
# ------------------------------------------------------------------------------
readonly TARGET_DIR="$HOME/sf-tools"

# ------------------------------------------------------------------------------
# 5. フェーズ定義
# ------------------------------------------------------------------------------

# 【UPDATE】sf-tools を最新化
phase_update() {
    log "INFO" "sf-tools を最新化します (${TARGET_DIR})..."
    local branch
    branch=$(git -C "$TARGET_DIR" symbolic-ref --short HEAD 2>/dev/null || echo "main")
    run git -C "$TARGET_DIR" pull origin "$branch" || return $RET_NG
    return $RET_OK
}

# 【WRAPPER】プロジェクト側のラッパースクリプトを生成
phase_generate_wrappers() {
    log "INFO" "プロジェクト側のラッパースクリプトを生成します..."

    for script in sf-start.sh sf-restart.sh; do
        cat << EOF > "./${script}"
#!/bin/bash
exec bash "\$HOME/sf-tools/${script}" "\$@"
EOF
        run chmod +x "./${script}" || return $RET_NG
        log "INFO" "${script} を生成しました。"
    done

    return $RET_OK
}

# ------------------------------------------------------------------------------
# 6. メインフロー
# ------------------------------------------------------------------------------
phase_update           || die "sf-tools の最新化に失敗しました。"
log "SUCCESS" "sf-tools を最新化しました。"

phase_generate_wrappers || die "ラッパースクリプトの生成に失敗しました。"
log "SUCCESS" "ラッパースクリプトを生成しました。"

exit $RET_OK
