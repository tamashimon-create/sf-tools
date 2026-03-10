#!/bin/bash

# ==============================================================================
# プログラム名: sf-hook.sh
# 概要: カレントディレクトリのGitプロジェクトに対して、Salesforce検証フックを有効化する
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
echo -e "${CLR_INFO}⚓ Git Hook (pre-push) の有効化を開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. フックファイルの生成
# ------------------------------------------------------------------------------
readonly HOOK_DEST=".git/hooks/pre-push"
# ラッパースクリプト内に埋め込む、このツールが生成したことを示す識別子
readonly HOOK_MARKER="# 自動生成されたラッパースクリプト: sf-tools の pre-push フックを呼び出します"

# --- 安全装置: 既存フックの上書きを防止 ---
# ファイルが存在し、かつそれがsf-tools製でない（マーカーがない）場合は、ユーザーのカスタムフックと判断して処理を中断
if [ -f "$HOOK_DEST" ] && ! grep -qF "$HOOK_MARKER" "$HOOK_DEST"; then
    echo -e "${CLR_ERR}❌ 警告: 独自の pre-push フックが既に存在します。${CLR_RESET}"
    echo "sf-tools のフックを有効にするには、既存のフックをバックアップしてから再度実行してください。"
    echo "ファイル: $HOOK_DEST"
    echo "-------------------------------------------------------"
    exit 1
fi

# --- ラッパースクリプトの書き込み ---
cat << EOF > "$HOOK_DEST"
#!/bin/bash
$HOOK_MARKER

HOOK_SCRIPT="\$HOME/sf-tools/hooks/pre-push"

if [ -f "$HOOK_SCRIPT" ]; then
    # 実体が存在すれば実行し、その終了コードをそのままGitに返す
    bash "\$HOOK_SCRIPT" "\$@"
    exit $?
else
    echo "⚠️ [PRE-PUSH] sf-tools のフックスクリプトが見つかりません: \$HOOK_SCRIPT" >&2
    echo "検証をスキップして Push を継続します。" >&2
    exit 0
fi
EOF

# 実行権限の付与
chmod +x "$HOOK_DEST"

echo -e "${CLR_SUCCESS}✅ sf-hook: pre-push フックを【有効化】しました！${CLR_RESET}"
echo "次回以降の git push 時に、自動的に Salesforce 組織への検証 (Dry-Run) が実行されます。"
echo "-------------------------------------------------------"
exit 0