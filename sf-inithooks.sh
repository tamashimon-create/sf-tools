#!/bin/bash

# ==============================================================================
# プログラム名: init-hooks.sh
# 概要: カレントディレクトリのGitプロジェクトに、sf-toolsのGitフックを適用する
# 設置場所: ~/sf-tools/init-hooks.sh
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
echo -e "${CLR_INFO}⚓ Gitフックの初期化(Init Hooks)を開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# ラッパースクリプトの生成先
HOOK_DEST=".git/hooks/pre-push"

# ==========================================
# ラッパースクリプトの書き込み
# ==========================================
cat << 'EOF' > "$HOOK_DEST"
#!/bin/bash
# 自動生成されたラッパースクリプト: sf-tools の pre-push フックを呼び出します

HOOK_SCRIPT="$HOME/sf-tools/hooks/pre-push"

if [ -f "$HOOK_SCRIPT" ]; then
    # 実体が存在すれば実行し、その終了コードをそのままGitに返す
    bash "$HOOK_SCRIPT" "$@"
    exit $?
else
    echo "⚠️ [PRE-PUSH] sf-tools のフックスクリプトが見つかりません: $HOOK_SCRIPT" >&2
    echo "検証をスキップして Push を継続します。" >&2
    exit 0
fi
EOF

# 実行権限の付与
chmod +x "$HOOK_DEST"

echo -e "${CLR_SUCCESS}✅ pre-push フックのインストールが完了しました！${CLR_RESET}"
echo "-------------------------------------------------------"
exit 0