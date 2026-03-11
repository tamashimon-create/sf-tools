#!/bin/bash

# ==============================================================================
# sf-tools メインエンジン (sf-start.sh)
# 役割: 環境構築(install) -> 同期(inithooks) -> 接続(login) -> 起動(vscode)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"         # 実行のたびにログをリセット
readonly SILENT_EXEC=1          # コマンドの標準出力はログファイルのみに記録

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
# プロジェクトディレクトリ（force-で始まる）にいるか確認
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "" "開発タスクのスタートアップを開始します..."

DELTA_DIR="./temp_delta_$$"
trap 'rm -rf "$DELTA_DIR" ./cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. ツール環境の自動更新 (最優先)
# ------------------------------------------------------------------------------
log "INFO" "INIT" "ツール環境の自動更新を開始します..."

# プロジェクト側に sf-install.sh がある場合は、まずそれを実行して共通ツールを最新にする
if [ -f "./sf-install.sh" ]; then
    log "INFO" "INIT" "sf-tools を最新化します"
    bash "./sf-install.sh" > /dev/null 2>&1
fi

# Gitフックの初期化も確実に行う
if [ -x "$HOME/sf-tools/sf-hook.sh" ]; then
    log "INFO" "INIT" "Gitフック有効化します"

    "$HOME/sf-tools/sf-hook.sh" > /dev/null 2>&1
fi
log "SUCCESS" "INIT" "ツール環境の自動更新を完了しました"

# ------------------------------------------------------------------------------
# 5. フォルダ構成の準備
# ------------------------------------------------------------------------------
log "INFO" "ENV" "リリース管理用のディレクトリを自動生成します..."

# 現在のGitブランチ名を取得し、リリース管理用のディレクトリを自動生成します
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -n "$BRANCH_NAME" ]; then
    RELEASE_DIR="release/${BRANCH_NAME}"
    mkdir -p "$RELEASE_DIR"
    [ ! -f "${RELEASE_DIR}/deploy-target.txt" ] && cp "$HOME/sf-tools/templates/deploy-template.txt" "${RELEASE_DIR}/deploy-target.txt" 2>/dev/null
    [ ! -f "${RELEASE_DIR}/remove-target.txt" ] && cp "$HOME/sf-tools/templates/remove-template.txt" "${RELEASE_DIR}/remove-target.txt" 2>/dev/null
    log "INFO" "INIT" "現在のブランチ:${BRANCH_NAME}"
fi
log "SUCCESS" "ENV" "リリース管理用のディレクトリを作成しました"

# ------------------------------------------------------------------------------
# 6. Salesforce 接続確認（スマート判定 ＆ 強制リセット対応）
# ------------------------------------------------------------------------------
log "INFO" "LOGIN" "Salesforce 接続確認中..."
SKIP_LOGIN=0

# パターンA: 既存の接続情報を確認（sf-startswitch.sh からの呼び出しでない場合）
# FORCE_RELOGIN フラグが立っていない場合、sf org display で現在の接続状況をチェックします
if [ "$FORCE_RELOGIN" != "1" ]; then
    DISPLAY_JSON=$(sf org display --json 2>/dev/null || echo "")
    # JSONからエイリアス名と組織IDを抽出し、余計な改行コードを除去
    CURRENT_ALIAS=$(echo "$DISPLAY_JSON" | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
    CURRENT_ID=$(echo "$DISPLAY_JSON" | grep '"id"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')

    # 有効なエイリアスと本番/Sandbox組織ID(00Dから始まる)が取得できた場合、ログイン済みと判断
    if [ -n "$CURRENT_ALIAS" ] && [ "$CURRENT_ALIAS" != "null" ] && [[ "$CURRENT_ID" == 00D* ]]; then
        log "INFO" "LOGIN" "組織 (${CURRENT_ALIAS}) に接続済みです。"
        ORG_ALIAS="$CURRENT_ALIAS"
        SKIP_LOGIN=1
    fi
fi

# パターンB: 新規ログイン、または強制再ログイン
# 接続が確認できない場合、または sf-startswitch.sh から強制フラグが渡された場合に実行
if [ "$SKIP_LOGIN" -eq 0 ]; then
    # ユーザーに接続先エイリアスの入力を促す（デフォルト値: tama）
    echo -en "${CLR_PROMPT}✏️  接続する組織のエイリアスを入力してください [デフォルト: tama]: ${CLR_RESET}"
    read ORG_ALIAS
    ORG_ALIAS=${ORG_ALIAS:-tama}

    # VS Codeが参照する古いエイリアス設定をクリア
    sf alias unset vscodeOrg >/dev/null 2>&1

    # Webブラウザ経由でのログインフローを開始し、デフォルト組織として設定
    log "INFO" "LOGIN" "ブラウザでログインして接続を許可してください..."
    sf org login web --set-default --alias "$ORG_ALIAS" 2>&1 | tee "$DELTA_DIR"

    if grep -qi "successfully authorized" "$DELTA_DIR"; then
        log "INFO" "LOGIN" "接続完了！"

    else
        log "INFO" "LOGIN" "接続失敗。"
    fi
fi
log "INFO" "SUCCESS" "Salesforce に接続しました"

# ------------------------------------------------------------------------------
# 4. VS Code 設定の同期＆起動
# ------------------------------------------------------------------------------
log "INFO" "VSCode" "VSCode 起動中..."

# VS CodeのSalesforce拡張機能が参照する設定ファイル(.sf/config.json, .sfdx/sfdx-config.json)を更新
mkdir -p .sfdx .sf
echo '{"target-org": "'"$ORG_ALIAS"'"}' > .sf/config.json
echo '{"defaultusername": "'"$ORG_ALIAS"'"}' > .sfdx/sfdx-config.json
sf config set target-org="$ORG_ALIAS" >/dev/null 2>&1
sleep 2

# ------------------------------------------------------------------------------
# 5. VS Code 起動
# ------------------------------------------------------------------------------
log "INFO" "VSCode" "VSCode を起動中..."
# 'code' コマンドが利用可能であれば、現在のプロジェクトフォルダをVS Codeで開く
if command -v code >/dev/null 2>&1; then
    code .
    log "INFO" "VSCode" "VSCode を起動しました。"
fi
exit 0