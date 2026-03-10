#!/bin/bash

# ==============================================================================
# sf-tools メインエンジン (sf-start.sh)
# 役割: 環境構築(install) -> 同期(inithooks) -> 接続(login) -> 起動(vscode)
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. 共通の初期処理
# ------------------------------------------------------------------------------
# ターミナル出力用のカラー定義
# 実行環境がインタラクティブなターミナルの場合のみ色を有効化し、ログファイル等を汚さないようにする
if [ -t 2 ]; then
    # 本物のターミナル(Git Bash等)で実行されている場合は色をつける
    readonly CLR_INFO='\033[36m'
    readonly CLR_SUCCESS='\033[32m'
    readonly CLR_ERR='\033[31m'
    readonly CLR_CMD='\033[34m'
    readonly CLR_RESET='\033[0m'
else
    # TortoiseGitなどのGUIツールやパイプ処理時は色をつけない（文字化け防止）
    readonly CLR_INFO=''
    readonly CLR_SUCCESS=''
    readonly CLR_ERR=''
    readonly CLR_CMD=''
    readonly CLR_RESET=''
fi

echo "======================================================="
echo -e "${CLR_INFO}🚀 開発タスクのスタートアップを開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
# プロジェクトルート（force-から始まるディレクトリ）以外での誤実行による事故を防止します
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# 【安全性】スクリプト終了時に、プロセスID($$)が付与された一時ファイルを確実にクリーンアップする
# 正常終了時はもちろん、Ctrl+Cによる中断やエラー時にも作業ディレクトリを汚さないためのマナーです
trap 'rm -f ./login_out_$$.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 1. ツール環境の自動更新 (最優先)
# ------------------------------------------------------------------------------
echo -e "\n▶️ ツール環境の自動更新を開始します..."

# プロジェクト側に sf-install.sh がある場合は、まずそれを実行して共通ツールを最新にする
if [ -f "./sf-install.sh" ]; then
    echo -e "▶️  sf-tools 最新化"
    bash "./sf-install.sh" > /dev/null 2>&1
fi

# Gitフックの初期化も確実に行う
if [ -x "$HOME/sf-tools/sf-hook.sh" ]; then
    echo -e "▶️  Gitフック有効化"
    "$HOME/sf-tools/sf-hook.sh" > /dev/null 2>&1
fi
echo -e "▶️  環境最新化: ${CLR_SUCCESS}完了${CLR_RESET}"

# ------------------------------------------------------------------------------
# 2. フォルダ構成の準備
# ------------------------------------------------------------------------------
# 現在のGitブランチ名を取得し、リリース管理用のディレクトリを自動生成します
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
echo -e "\n▶️ Salesforce 接続状況を確認中..."

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
        echo -e "${CLR_SUCCESS}✅ 組織 (${CURRENT_ALIAS}) に接続済みです。${CLR_RESET}"
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
# VS CodeのSalesforce拡張機能が参照する設定ファイル(.sf/config.json, .sfdx/sfdx-config.json)を更新
mkdir -p .sfdx .sf
echo '{"target-org": "'"$ORG_ALIAS"'"}' > .sf/config.json
echo '{"defaultusername": "'"$ORG_ALIAS"'"}' > .sfdx/sfdx-config.json
sf config set target-org="$ORG_ALIAS" >/dev/null 2>&1
sleep 2

# ------------------------------------------------------------------------------
# 5. VS Code 起動
# ------------------------------------------------------------------------------
echo -e "\n▶️ VSCode を起動中..."
# 'code' コマンドが利用可能であれば、現在のプロジェクトフォルダをVS Codeで開く
if command -v code >/dev/null 2>&1; then
    code .
    echo -e "${CLR_SUCCESS}✅ 起動しました。${CLR_RESET}"
fi

echo "======================================================="
echo -e "${CLR_SUCCESS}🎉 準備が整いました。開発を開始してください。${CLR_RESET}"
echo "======================================================="
exit 0