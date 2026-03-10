#!/bin/bash

# ==============================================================================
# プログラム名: sf-unhook.sh
# 概要: カレントディレクトリのGitプロジェクトから、Salesforce検証フックを削除（無効化）する
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. 共通の初期処理
# ------------------------------------------------------------------------------
# カラー定義
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
echo -e "${CLR_INFO}⚓ Git Hook (pre-push) の無効化を開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. フックファイルの削除
# ------------------------------------------------------------------------------
HOOK_DEST=".git/hooks/pre-push"

if [ -f "$HOOK_DEST" ]; then
    rm -f "$HOOK_DEST"
    echo -e "${CLR_SUCCESS}✅ sf-unhook: pre-push フックを【無効化】しました。${CLR_RESET}"
    echo "次回以降の git push 時には、Salesforce 組織への検証は行われません。"
else
    echo -e "${CLR_INFO}▶️  フックはすでに無効化されています（ファイルが存在しません）。${CLR_RESET}"
fi

echo "-------------------------------------------------------"
exit 0