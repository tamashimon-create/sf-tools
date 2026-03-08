#!/bin/bash

# ==============================================================================
# プログラム名: sf-startswitch.sh
# 概要: 現在の接続設定を初期化し、別の組織への切り替え（強制再認証）を行う
# ==============================================================================

if [ -t 1 ]; then
    readonly CLR_INFO='\033[36m'
    readonly CLR_SUCCESS='\033[32m'
    readonly CLR_RESET='\033[0m'
else
    readonly CLR_INFO=''
    readonly CLR_SUCCESS=''
    readonly CLR_RESET=''
fi

echo "======================================================="
echo -e "${CLR_INFO}♻️  接続組織の切り替え（Switch）を開始します...${CLR_RESET}"
echo "======================================================="

# 1. ローカルの接続キャッシュ（.sf / .sfdx）をクリア
# これにより、sf-start.sh 内の「接続済み自動スキップ」を無効化します
echo "▶️  現在のローカル接続設定をクリアしています..."
rm -f .sf/config.json .sfdx/sfdx-config.json 2>/dev/null

echo -e "${CLR_INFO}💡 VS Codeの表示を更新するため、完了後にウィンドウをリロードしてください。${CLR_RESET}"
echo -e "\n${CLR_SUCCESS}✅ 初期化完了。新しい組織へのログインを開始します。${CLR_RESET}"
echo "-------------------------------------------------------"

# 2. 強制ログインフラグ(FORCE_RELOGIN)を立ててメインスクリプトを呼び出す
if [ -f "./sf-start.sh" ]; then
    FORCE_RELOGIN=1 bash "./sf-start.sh"
else
    echo "❌ sf-start.sh が見つかりません。同じディレクトリに配置してください。"
    exit 1
fi

exit 0