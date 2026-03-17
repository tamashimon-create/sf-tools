#!/bin/bash

# ==============================================================================
# sf-start.sh - 開発環境スタートアップスクリプト
# ==============================================================================
# ワンコマンドで開発環境を整えます。
#   1. Salesforce 組織への接続確認・ログイン
#   2. VS Code 設定の同期と起動
#   ↓ VS Code 起動後にバックグラウンドで実行
#   3. sf-tools 自動更新 & Git フック有効化
#   4. リリース管理ディレクトリの準備
#   5. 現在のブランチ名を sf-tools/release/branch_name.txt に保存
#
# 【オプション】
#   -v, --verbose       : コマンドの応答（出力）をコンソールにも表示します
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"


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
log "HEADER" "開発タスクのスタートアップを開始します (${SCRIPT_NAME}.sh)"

trap 'rm -f ./sf-tools/cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. Salesforce 接続確認・ログイン
# ------------------------------------------------------------------------------
log "INFO" "Salesforce 接続確認中..."
SKIP_LOGIN=0

# パターンA: 接続済みの場合はログインをスキップ
#   FORCE_RELOGIN=1（sf-restart.sh 経由）の場合はこのブロックを飛ばして強制ログイン
#   .sf/config.json が存在しない場合はプロジェクト初回起動とみなし、強制的にエイリアス入力へ
if [ "$FORCE_RELOGIN" != "1" ] && [ -f ".sf/config.json" ]; then
    DISPLAY_JSON=$(run sf org display --json || echo "")
    CURRENT_ALIAS=$(echo "$DISPLAY_JSON" | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
    CURRENT_ID=$(echo "$DISPLAY_JSON"    | grep '"id"'    | head -n 1 | cut -d '"' -f 4 | tr -d '\r')

    # エイリアスと本番/Sandbox 組織ID（00D始まり）が取得できた場合は接続済みと判断
    if [ -n "$CURRENT_ALIAS" ] && [ "$CURRENT_ALIAS" != "null" ] && [[ "$CURRENT_ID" == 00D* ]]; then
        log "INFO" "組織 (${CURRENT_ALIAS}) に接続済みです。"
        ORG_ALIAS="$CURRENT_ALIAS"
        SKIP_LOGIN=1
    fi
fi

# パターンB: 未接続 または 強制再ログイン
if [ "$SKIP_LOGIN" -eq 0 ]; then
    echo -en "${CLR_PROMPT}接続する組織のエイリアスを入力してください [デフォルト: tama]: ${CLR_RESET}"
    read -r ORG_ALIAS
    ORG_ALIAS=${ORG_ALIAS:-tama}

    # VS Code が参照する古いエイリアス設定をクリア
    run sf alias unset vscodeOrg --json

    log "INFO" "ブラウザでログインして接続を許可してください..."
    run sf org login web --set-default --alias "$ORG_ALIAS" || die "Salesforce へのログインに失敗しました。"
    log "SUCCESS" "接続完了！"
fi

log "SUCCESS" "Salesforce に接続しました"

# ------------------------------------------------------------------------------
# 5. VS Code 設定の同期と起動
# ------------------------------------------------------------------------------
log "INFO" "VS Code を起動中..."

# VS Code の Salesforce 拡張が参照する設定ファイル (.sf/config.json, .sfdx/sfdx-config.json) を更新
run mkdir -p .sfdx .sf || die "設定ディレクトリの作成に失敗しました。"
printf '{"target-org": "%s"}\n'      "$ORG_ALIAS" | run tee .sf/config.json        || die "設定ファイル (.sf/config.json) の書き込みに失敗しました。"
printf '{"defaultusername": "%s"}\n' "$ORG_ALIAS" | run tee .sfdx/sfdx-config.json || die "設定ファイル (.sfdx/sfdx-config.json) の書き込みに失敗しました。"
run sf config set target-org="$ORG_ALIAS" --json || log "WARNING" "sf config set に失敗しました（続行します）"
sleep 2  # VS Code 起動前に設定ファイルの書き込み完了を待機

if command -v code >/dev/null 2>&1; then
    run code .
    log "SUCCESS" "VS Code を起動しました。"
else
    log "WARNING" "'code' コマンドが見つかりません。VS Code を手動で起動してください。"
fi

# ------------------------------------------------------------------------------
# 6. バックグラウンド処理（VS Code 起動後に実行）
# ------------------------------------------------------------------------------
(
    # sf-tools 最新化
    if [ -f "$HOME/sf-tools/sf-install.sh" ]; then
        log "INFO" "sf-tools を最新化します（バックグラウンド）"
        bash "$HOME/sf-tools/sf-install.sh" "$@" \
            || log "WARNING" "sf-tools の最新化に失敗しました（続行します）"
    fi

    # Git フック有効化（sf-unhook.sh で一時的に無効化可能）
    if [ -x "$HOME/sf-tools/sf-hook.sh" ]; then
        log "INFO" "Git フックを有効化します（バックグラウンド）"
        bash "$HOME/sf-tools/sf-hook.sh" "$@" \
            || log "WARNING" "Git フックの有効化に失敗しました（続行します）"
    fi

    # リリース管理ディレクトリの準備 & ブランチ名保存
    log "INFO" "リリース管理用のディレクトリを準備します..."
    BRANCH_NAME=$(run git symbolic-ref --short HEAD)
    if [ -n "$BRANCH_NAME" ]; then
        RELEASE_DIR="sf-tools/release/${BRANCH_NAME}"
        run mkdir -p "$RELEASE_DIR"
        [ ! -f "${RELEASE_DIR}/deploy-target.txt" ] \
            && run cp "$HOME/sf-tools/templates/deploy-template.txt" "${RELEASE_DIR}/deploy-target.txt"
        [ ! -f "${RELEASE_DIR}/remove-target.txt" ] \
            && run cp "$HOME/sf-tools/templates/remove-template.txt"  "${RELEASE_DIR}/remove-target.txt"
        run mkdir -p "sf-tools/release"
        printf '%s\n' "$BRANCH_NAME" | run tee "sf-tools/release/branch_name.txt" > /dev/null
        log "INFO" "ブランチ: ${BRANCH_NAME} / branch_name.txt を保存しました"
    fi

    log "SUCCESS" "バックグラウンド処理が完了しました"
) &

exit $RET_OK
