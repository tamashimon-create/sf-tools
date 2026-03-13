#!/bin/bash

# ==============================================================================
# sf-install.sh - sf-tools の最新化・プロジェクトラッパー生成スクリプト
# ==============================================================================
# sf-start.sh から自動呼び出しされるため、通常は直接実行する必要はありません。
#
# 【動作】
#   1. ~/sf-tools を git pull で最新化
#   2. プロジェクト側のラッパースクリプト (sf-start.sh / sf-restart.sh) を生成
#   3. Git / Node.js / Salesforce CLI をアップデート
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

log "HEADER" "sf-tools のセットアップを開始します (${SCRIPT_NAME}.sh)"

trap 'rm -f ./cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. 定数定義
# ------------------------------------------------------------------------------
readonly TARGET_DIR="$HOME/sf-tools"
readonly UPDATE_STAMP_FILE="$HOME/.sf-tools-last-update"
readonly UPDATE_INTERVAL_SEC=86400  # 24時間（秒）

# _is_tool_update_needed - 前回のツールアップデートから一定時間が経過しているか判定
# 戻り値: 0=実行が必要 / 1=スキップ可
_is_tool_update_needed() {
    [[ ! -f "$UPDATE_STAMP_FILE" ]] && return 0
    local last_update elapsed
    last_update=$(stat -c "%Y" "$UPDATE_STAMP_FILE" 2>/dev/null || echo 0)
    elapsed=$(( $(date +%s) - last_update ))
    [[ $elapsed -ge $UPDATE_INTERVAL_SEC ]]
}

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

# 【TOOLS】開発ツールのアップデート
phase_update_tools() {
    # ── ① ツールアップデート（前回から 24 時間経過時のみ実行） ──
    if _is_tool_update_needed; then
        log "INFO" "開発ツールのアップデートを開始します..."

        # Git
        log "INFO" "Git をアップデートします..."
        if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
            run git update-git-for-windows --yes \
                || log "WARNING" "Git のアップデートに失敗しました（続行します）"
        else
            log "INFO" "Git のアップデートはパッケージマネージャーで行ってください（スキップ）"
        fi

        # Node.js (npm 経由でアップデート)
        log "INFO" "Node.js / npm をアップデートします..."
        if command -v npm >/dev/null 2>&1; then
            run npm install -g npm@latest \
                || log "WARNING" "npm のアップデートに失敗しました（続行します）"
        else
            log "WARNING" "npm が見つかりません。Node.js のインストールを確認してください。"
        fi

        # Salesforce CLI
        log "INFO" "Salesforce CLI をアップデートします..."
        if command -v sf >/dev/null 2>&1; then
            run sf update \
                || log "WARNING" "Salesforce CLI のアップデートに失敗しました（続行します）"
        else
            log "WARNING" "sf コマンドが見つかりません。Salesforce CLI のインストールを確認してください。"
        fi

        # Git マージドライバー (ours) の登録
        log "INFO" "Git マージドライバー (ours) を登録します..."
        run git config merge.ours.driver true \
            || log "WARNING" "Git マージドライバーの登録に失敗しました（続行します）"

        touch "$UPDATE_STAMP_FILE"
        log "INFO" "次回の自動アップデートは $((UPDATE_INTERVAL_SEC / 3600)) 時間後です。"
    else
        local last_update elapsed_h
        last_update=$(stat -c "%Y" "$UPDATE_STAMP_FILE" 2>/dev/null || echo 0)
        elapsed_h=$(( ( $(date +%s) - last_update ) / 3600 ))
        log "INFO" "開発ツールは ${elapsed_h} 時間前にアップデート済みのためスキップします（間隔: $((UPDATE_INTERVAL_SEC / 3600))h）。"
    fi

    # ── ② npm install（package-lock.json が node_modules より新しい場合のみ実行） ──
    if [[ -f "./package.json" ]]; then
        if [[ ! -d "./node_modules" ]] || [[ "./package-lock.json" -nt "./node_modules" ]]; then
            log "INFO" "npm パッケージをインストール／更新します（Prettier 等）..."
            run npm install \
                || log "WARNING" "npm install に失敗しました（続行します）"
        else
            log "INFO" "npm パッケージは最新です。npm install をスキップします。"
        fi
    else
        log "INFO" "package.json が見つかりません。npm install をスキップします。"
    fi

    return $RET_OK
}

# ------------------------------------------------------------------------------
# 6. メインフロー
# ------------------------------------------------------------------------------
phase_update           || die "sf-tools の最新化に失敗しました。"
log "SUCCESS" "sf-tools を最新化しました。"

phase_generate_wrappers || die "ラッパースクリプトの生成に失敗しました。"
log "SUCCESS" "ラッパースクリプトを生成しました。"

phase_update_tools
log "SUCCESS" "開発ツールのアップデートが完了しました。"

exit $RET_OK
