#!/bin/bash

# ==============================================================================
# sf-tools メインエンジン (sf-start.sh)
# 役割: 環境構築(install) -> 同期(inithooks) -> 接続(login) -> 起動(vscode)
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. 共通の初期処理
# ------------------------------------------------------------------------------
# カラー定義
if [ -t 1 ]; then
    readonly CLR_INFO='\033[36m'
    readonly CLR_SUCCESS='\033[32m'
    readonly CLR_ERR='\033[31m'
    readonly CLR_PROMPT='\033[33m'
    readonly CLR_RESET='\033[0m'
else
    readonly CLR_INFO=''; readonly CLR_SUCCESS=''; readonly CLR_ERR=''; readonly CLR_PROMPT=''; readonly CLR_RESET=''
fi

echo "======================================================="
echo -e "${CLR_INFO}🚀 開発タスクのスタートアップを開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# 一時ファイルのクリーンアップ
trap 'rm -f ./login_out_$$.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 1. ツール環境の自動更新 (最優先)
# ------------------------------------------------------------------------------
# プロジェクト側に sf-install.sh がある場合は、まずそれを実行して共通ツールを最新にする
if [ -f "./sf-install.sh" ]; then
    echo -e "▶️  [1/4] 環境の整合性をチェック中..."
    bash "./sf-install.sh" > /dev/null 2>&1
fi

# Gitフックの初期化も確実に行う
if [ -x "$HOME/sf-tools/sf-hook.sh" ]; then
"$HOME/sf-tools/sf-hook.sh" > /dev/null 2>&1
fi
echo -e "▶️  環境チェック: ${CLR_SUCCESS}完了${CLR_RESET}"

# ------------------------------------------------------------------------------
# 2. フォルダ構成の準備
# ------------------------------------------------------------------------------
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -n "$BRANCH_NAME" ]; then
    RELEASE_DIR="release/${BRANCH_NAME}"
    mkdir -p "$RELEASE_DIR"
    [ ! -f "${RELEASE_DIR}/deploy-target.txt" ] && cp "$HOME/sf-tools/templates/deploy-template.txt" "${RELEASE_DIR}/deploy-target.txt" 2>/dev/null
    [ ! -f "${RELEASE_DIR}/remove-target.txt" ] && cp "$HOME/sf-tools/templates/remove-template.txt" "${RELEASE_DIR}/remove-target.txt" 2>/dev/null
    echo -e "▶️  現在のブランチ: ${CLR_INFO}${BRANCH_NAME}${CLR_RESET}"
fi

# ------------------------------------------------------------------------------
# 3. Salesforce 接続確認（スマート判定 ＆ 強制リセット対応）
# ------------------------------------------------------------------------------
echo -e "\n▶️  [2/4] Salesforce 接続状況を確認中..."

SKIP_LOGIN=0

# FORCE_RELOGIN フラグが立っていない場合のみ、既存の接続をチェック
if [ "$FORCE_RELOGIN" != "1" ]; then
    DISPLAY_JSON=$(sf org display --json 2>/dev/null || echo "")
    CURRENT_ALIAS=$(echo "$DISPLAY_JSON" | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
    CURRENT_ID=$(echo "$DISPLAY_JSON" | grep '"id"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')

    if [ -n "$CURRENT_ALIAS" ] && [ "$CURRENT_ALIAS" != "null" ] && [[ "$CURRENT_ID" == 00D* ]]; then
        echo -e "${CLR_SUCCESS}✅ 組織 (${CURRENT_ALIAS}) に接続済みです。${CLR_RESET}"
        ORG_ALIAS="$CURRENT_ALIAS"
        SKIP_LOGIN=1
    fi
fi

if [ "$SKIP_LOGIN" -eq 0 ]; then
    echo -en "${CLR_PROMPT}✏️  接続する組織のエイリアスを入力してください [デフォルト: tama]: ${CLR_RESET}"
    read ORG_ALIAS
    ORG_ALIAS=${ORG_ALIAS:-tama}

    sf alias unset vscodeOrg >/dev/null 2>&1

    echo -e "ブラウザでログインして接続を許可してください..."
    TMP_LOGIN="./login_out_$$.tmp"
    sf org login web --set-default --alias "$ORG_ALIAS" 2>&1 | tee "$TMP_LOGIN"

    if grep -qi "successfully authorized" "$TMP_LOGIN"; then
        echo -e "${CLR_SUCCESS}✅ 接続完了！${CLR_RESET}"
    else
        echo -e "${CLR_ERR}❌ 接続失敗。${CLR_RESET}"
    fi
fi

# ------------------------------------------------------------------------------
# 4. VS Code 設定の同期
# ------------------------------------------------------------------------------
mkdir -p .sfdx .sf
echo '{"target-org": "'"$ORG_ALIAS"'"}' > .sf/config.json
echo '{"defaultusername": "'"$ORG_ALIAS"'"}' > .sfdx/sfdx-config.json
sf config set target-org="$ORG_ALIAS" >/dev/null 2>&1
sleep 2

# ------------------------------------------------------------------------------
# 5. VS Code 起動
# ------------------------------------------------------------------------------
echo -e "\n▶️  [3/4] VS Code を起動中..."
if command -v code >/dev/null 2>&1; then
    code .
    echo -e "${CLR_SUCCESS}✅ 起動しました。${CLR_RESET}"
fi

echo "======================================================="
echo -e "${CLR_SUCCESS}🎉 準備が整いました。開発を開始してください。${CLR_RESET}"
echo "======================================================="
exit 0