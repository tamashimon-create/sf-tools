#!/bin/bash

# ==============================================================================
# プログラム名: sf-hook.sh
# 概要: カレントディレクトリのGitプロジェクトに対して、Salesforce検証フックを有効化する
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

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

echo "======================================================="
echo -e "${CLR_INFO}⚓ Git Hook (pre-push) の有効化を開始します...${CLR_RESET}"
echo "======================================================="

# ------------------------------------------------------------------------------
# 1. フックファイルの生成
# ------------------------------------------------------------------------------
HOOK_DEST=".git/hooks/pre-push"

# ヒアドキュメントを使用して .git/hooks/pre-push を作成
cat << 'EOF' > "$HOOK_DEST"
#!/bin/bash
# 自動生成されたラッパースクリプト: sf-tools の pre-push フックを呼び出します

HOOK_SCRIPT="$HOME/sf-tools/hooks/pre-push"

if [ -f "$HOOK_SCRIPT" ]; then
    bash "$HOOK_SCRIPT" "$@"
    exit $?
else
    echo "⚠️ [PRE-PUSH] sf-tools のフックスクリプトが見つかりません: $HOOK_SCRIPT" >&2
    exit 0
fi
EOF

# 実行権限の付与
chmod +x "$HOOK_DEST"

echo -e "${CLR_SUCCESS}✅ sf-hook: pre-push フックを【有効化】しました！${CLR_RESET}"
echo "次回以降の git push 時に、自動的に Salesforce 組織への検証 (Dry-Run) が実行されます。"
echo "-------------------------------------------------------"
exit 0