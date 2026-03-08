#!/bin/bash

# ==============================================================================
# プログラム名: sf-unhook.sh
# 概要: カレントディレクトリのGitプロジェクトから、Salesforce検証フックを削除（無効化）する
# ==============================================================================

if [ -t 1 ]; then
    readonly CLR_INFO='\033[36m'
    readonly CLR_SUCCESS='\033[32m'
    readonly CLR_ERR='\033[31m'
    readonly CLR_RESET='\033[0m'
else
    readonly CLR_INFO=''
    readonly CLR_SUCCESS=''
    readonly CLR_ERR=''
    readonly CLR_RESET=''
fi

echo -e "${CLR_INFO}--------------------------------------------------------------${CLR_RESET}"
if [ ! -d ".git" ]; then
    echo -e "${CLR_ERR}❌ ここはGitリポジトリのルートディレクトリではありません。${CLR_RESET}"
    exit 1
fi

PRE_PUSH_HOOK=".git/hooks/pre-push"

if [ -f "$PRE_PUSH_HOOK" ]; then
    if rm -f "$PRE_PUSH_HOOK"; then
        echo -e "${CLR_SUCCESS}✅ sf-unhook: pre-push フックを【無効化】しました。${CLR_RESET}"
        echo "次回以降の git push 時には、Salesforce 組織への検証は行われません。（削除されたフック: pre-push フック）"
    else
        echo -e "${CLR_ERR}❌ pre-push フックの削除に失敗しました。権限やファイルの状態を確認してください。（例: 'chmod +w $PRE_PUSH_HOOK' で書き込み権限を付与）${CLR_RESET}"
        exit 2
    fi
else
    echo -e "${CLR_INFO}▶️ フックはすでに無効化されています（ファイルが存在しません）。${CLR_RESET}"
fi

echo -e "${CLR_INFO}-------------------------------------------------------${CLR_RESET}"
exit 0