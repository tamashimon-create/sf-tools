#!/bin/bash

# ==============================================================================
# プログラム名: sf-hook.sh
# 概要: カレントディレクトリのGitプロジェクトに対して、Salesforce検証フックを有効化する
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

echo -e "-------------------------------------------------------"
if [ ! -d ".git" ]; then
    echo -e "${CLR_ERR}❌ ここはGitリポジトリのルートディレクトリではありません。${CLR_RESET}"
    echo -e "Salesforceプロジェクトのルート（.gitフォルダがある階層）に移動して実行してください。"
    exit 1
fi

readonly HOOK_DEST=".git/hooks/pre-push"

# ヒアドキュメントの区切り記号 'EOF' をクォートすることで、変数展開（セキュリティや意図しない展開防止のため）を防いでいます
cat << 'EOF' > "$HOOK_DEST"
#!/bin/bash
# 自動生成されたラッパースクリプト: sf-tools の pre-push フックを呼び出します
# HOOK_SCRIPT のパスは環境変数 SF_HOOK_SCRIPT で上書き可能、なければデフォルトパス
HOOK_SCRIPT="${SF_HOOK_SCRIPT:-$HOME/sf-tools/hooks/pre-push}"

if [ -f "$HOOK_SCRIPT" ]; then
    bash "$HOOK_SCRIPT" "$@"
    exit $?
else
    echo "⚠️ [PRE-PUSH] sf-tools のフックスクリプトが見つかりません: $HOOK_SCRIPT" >&2
    exit 0
fi
EOF

chmod +x "$HOOK_DEST"

echo -e "${CLR_SUCCESS}✅ sf-hook: pre-push フックを【有効化】しました！${CLR_RESET}"
echo -e "次回以降の git push 時に、自動的に Salesforce 組織への検証 (Dry-Run) が実行されます。"
echo -e "-------------------------------------------------------"
exit 0