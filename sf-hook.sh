#!/bin/bash
# ==============================================================================
# sf-hook.sh - pre-push フックのインストールスクリプト
# ==============================================================================
# git push 時に Salesforce 組織への検証(dry-run)を自動実行する pre-push フックを
# カレントプロジェクトの .git/hooks/ にインストールします。
#
# 生成されるフックは ~/sf-tools/hooks/pre-push の呼び出しラッパーです。
# sf-tools 本体を更新するだけで、全プロジェクトのフック動作に即時反映されます。
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"
readonly SILENT_EXEC=1

# ------------------------------------------------------------------------------
# 2. 共通ライブラリの読み込み
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

# ------------------------------------------------------------------------------
# 3. 定数定義
# ------------------------------------------------------------------------------
# インストール先: カレントプロジェクトの Git フックディレクトリ
readonly HOOK_DEST=".git/hooks/pre-push"

# SF_HOOK_MARKER は lib/common.sh で定義済み

# ------------------------------------------------------------------------------
# 4. フェーズ定義
# ------------------------------------------------------------------------------

# 【CHECK】実行環境の検証
phase_check_environment() {
    log "INFO" "実行環境を確認中..."

    # force-* ディレクトリ内でのみ実行を許可
    check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。"

    # Git リポジトリのルートであることを確認
    if [[ ! -d ".git" ]]; then
        die "Gitリポジトリのルートで実行してください（.git ディレクトリが見つかりません）。"
    fi

    return $RET_OK
}

# 【INSTALL】ラッパースクリプトの生成と権限付与
phase_install_hook() {
    log "INFO" "Git Hook を生成（強制上書き）中..."

    run mkdir -p "$(dirname "$HOOK_DEST")" || return $RET_NG

    # ラッパースクリプトを生成する。
    # \$HOME はここでは展開せず、ラッパー実行時 (git push 時) に展開させる。
    cat << EOF > "$HOOK_DEST"
#!/bin/bash
$SF_HOOK_MARKER

HOOK_SCRIPT="\$HOME/sf-tools/hooks/pre-push"

if [ -f "\$HOOK_SCRIPT" ]; then
    bash "\$HOOK_SCRIPT" "\$@"
    exit \$?
else
    echo "[WARNING] [PRE-PUSH] sf-tools のフックスクリプトが見つかりません: \$HOOK_SCRIPT" >&2
    echo "検証をスキップして Push を継続します。" >&2
    exit 0
fi
EOF

    if [[ $? -ne 0 ]]; then
        log "ERROR" "フックスクリプトの書き込みに失敗しました: $HOOK_DEST"
        return $RET_NG
    fi

    run chmod +x "$HOOK_DEST" || return $RET_NG
    return $RET_OK
}

# ------------------------------------------------------------------------------
# 5. メイン実行フロー
# ------------------------------------------------------------------------------
log "HEADER" "Git Hook (pre-push) の有効化を開始します"

phase_check_environment || die "初期チェックに失敗しました。"
log "SUCCESS" "環境確認完了。"

phase_install_hook || die "フックのインストールに失敗しました。"
log "SUCCESS" "pre-push フックを強制適用しました。"

echo "-------------------------------------------------------"
log "INFO" "次回以降の git push 時に自動的に検証が実行されます。"
log "HEADER" "セットアップが完了しました"

exit $RET_OK
