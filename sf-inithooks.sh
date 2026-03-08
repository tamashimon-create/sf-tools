#!/bin/bash

# ==============================================================================
# プログラム名: init-hooks.sh
# 概要: カレントディレクトリのGitプロジェクトに、sf-toolsのGitフックを適用する
# 設置場所: ~/sf-tools/init-hooks.sh
# ==============================================================================

# ターミナル出力用のカラー装飾定義（環境に応じて自動切替）
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

echo "-------------------------------------------------------"
echo -e "${CLR_INFO}▶️  Gitフックのセットアップを開始します...${CLR_RESET}"

# カレントディレクトリがGitリポジトリかチェック
if [ ! -d ".git" ]; then
    echo -e "${CLR_ERR}❌ ここはGitリポジトリのルートディレクトリではありません。${CLR_RESET}"
    echo "Salesforceプロジェクトのルート（.gitフォルダがある階層）に移動してから実行してください。"
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