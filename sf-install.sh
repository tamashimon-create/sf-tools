#!/bin/bash

# ==============================================================================
# sf-install.sh - sf-tools の最新化・プロジェクト初期セットアップスクリプト
# ==============================================================================
# sf-start.sh から自動呼び出しされるため、通常は直接実行する必要はありません。
# ※ 時間のかかるツールアップデートは sf-upgrade.sh に委譲し、バックグラウンドで最後に実行。
#    それ以外の処理（ラッパー生成・マージドライバー登録など）は毎回・同期で実行。
#
# 【処理の流れ】
#   1. ~/sf-tools を git pull で最新化
#   2. プロジェクト側のラッパースクリプト (sf-start.sh / sf-restart.sh) を生成（未存在時のみ）
#   3. Git マージドライバー (ours) をリポジトリに登録
#   4. プロジェクトの npm パッケージをインストール（package.json がある場合のみ）
#   5. 開発ツールのアップデート（sf-upgrade.sh をバックグラウンドで起動）※24 時間に 1 回のみ
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

# _get_mtime - ファイルの更新タイムスタンプ（Unix秒）を取得する（macOS / Linux / Git Bash 対応）
_get_mtime() {
    local file="$1"
    if [[ "$(uname -s)" == Darwin* ]]; then
        stat -f "%m" "$file" 2>/dev/null || echo 0
    else
        stat -c "%Y" "$file" 2>/dev/null || echo 0
    fi
}

# _is_tool_update_needed - 前回のツールアップデートから一定時間が経過しているか判定
# 戻り値: 0=実行が必要 / 1=スキップ可
_is_tool_update_needed() {
    [[ ! -f "$UPDATE_STAMP_FILE" ]] && return 0
    local last_update elapsed
    last_update=$(_get_mtime "$UPDATE_STAMP_FILE")
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
    log "INFO" "プロジェクト側のラッパースクリプトを確認します..."

    for script in sf-start.sh sf-restart.sh; do
        if [[ -f "./${script}" ]]; then
            log "INFO" "${script} は既に存在します。スキップします。"
            continue
        fi
        cat << EOF > "./${script}"
#!/bin/bash
exec bash "\$HOME/sf-tools/${script}" "\$@"
EOF
        run chmod +x "./${script}" || return $RET_NG
        log "INFO" "${script} を生成しました。"
    done

    return $RET_OK
}

# 【MERGE DRIVER】Git マージドライバーの登録
phase_setup_merge_driver() {
    log "INFO" "Git マージドライバー (ours) を登録します..."
    run git config merge.ours.driver true \
        || log "WARNING" "Git マージドライバーの登録に失敗しました（続行します）"
    return $RET_OK
}

# 【NPM】プロジェクトの npm パッケージをインストール
# ※ 依存関係の変更を即時反映するため sf-upgrade.sh には移さず、毎回ここで実行する
phase_npm_install() {
    # package-lock.json が node_modules より新しい場合のみ実行
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

# 【UPGRADE】開発ツールのアップデート（バックグラウンド実行）
phase_upgrade_tools_bg() {
    if _is_tool_update_needed; then
        log "INFO" "開発ツールのアップデートをバックグラウンドで開始します（sf-upgrade.sh）..."
        bash "$SCRIPT_DIR/sf-upgrade.sh" &
        touch "$UPDATE_STAMP_FILE"
        log "INFO" "次回の自動アップデートは $((UPDATE_INTERVAL_SEC / 3600)) 時間後です。"
    else
        local last_update elapsed_h
        last_update=$(_get_mtime "$UPDATE_STAMP_FILE")
        elapsed_h=$(( ( $(date +%s) - last_update ) / 3600 ))
        log "INFO" "開発ツールは ${elapsed_h} 時間前にアップデート済みのためスキップします（間隔: $((UPDATE_INTERVAL_SEC / 3600))h）。"
    fi

    return $RET_OK
}

# ------------------------------------------------------------------------------
# 6. メインフロー
# ------------------------------------------------------------------------------
phase_update           || die "sf-tools の最新化に失敗しました。"
log "SUCCESS" "sf-tools を最新化しました。"

phase_generate_wrappers || die "ラッパースクリプトの確認に失敗しました。"
log "SUCCESS" "ラッパースクリプトの確認が完了しました。"

phase_setup_merge_driver
log "SUCCESS" "Git マージドライバーを登録しました。"

phase_npm_install
log "SUCCESS" "npm パッケージの確認が完了しました。"

phase_upgrade_tools_bg

exit $RET_OK
