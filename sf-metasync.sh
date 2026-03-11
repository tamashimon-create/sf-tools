#!/bin/bash
# ==============================================================================
# sf-metasync.sh - SalesforceメタデータのGit自動同期スクリプト (最終確定版)
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
    echo "❌ [FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

# ------------------------------------------------------------------------------
# 3. 初期チェック
# ------------------------------------------------------------------------------
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "" "🔄 メタデータ同期（Sandbox -> Git）を開始します"

# 一時ファイルの掃除設定
trap 'rm -rf "$DELTA_DIR" ./cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. 固有設定
# ------------------------------------------------------------------------------
TARGET_ORG=$(get_target_org) || die "接続先組織を特定できませんでした。"
log "INFO" "INIT" "接続先組織: ${TARGET_ORG}"

BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

# ★ コミットメッセージを日本語に復元
readonly COMMIT_MSG="定期更新: Salesforce変更の自動反映 ($(date +'%Y-%m-%d'))"
readonly DELTA_DIR="./temp_delta_$$"
readonly METADATA_TYPES=(ApexClass ApexPage LightningComponentBundle CustomObject CustomField Layout FlexiPage Flow PermissionSet CustomLabels)

# ------------------------------------------------------------------------------
# 5. 各作業フェーズの定義
# ------------------------------------------------------------------------------

phase_git_update() {
    log "INFO" "GIT" "リモートの最新状態を取り込んでいます..."
    run "GIT" git stash
    run "GIT" git fetch origin
    if ! run "GIT" git pull origin "$BRANCH_NAME" --rebase; then
        run "GIT" git rebase --abort
        return $RET_NG
    fi
    return $RET_OK
}

phase_analyze_delta() {
    log "INFO" "DELTA" "前回の同期からの変更箇所(SGD)を解析中..."
    mkdir -p "$DELTA_DIR"
    run "DELTA" sf sgd source delta --from "origin/$BRANCH_NAME" --to HEAD --output-dir "$DELTA_DIR"
}

phase_retrieve_metadata() {
    if [[ -f "$DELTA_DIR/package/package.xml" ]]; then
        log "INFO" "RETRIEVE" "SGDで特定された差分ファイルをダウンロード中..."
        run "RETRIEVE" sf project retrieve start --manifest "$DELTA_DIR/package/package.xml" --target-org "$TARGET_ORG" --ignore-conflicts
    fi
    log "INFO" "RETRIEVE" "主要メタデータの整合性をチェック中..."
    run "RETRIEVE" sf project retrieve start --metadata "${METADATA_TYPES[@]}" --target-org "$TARGET_ORG" --ignore-conflicts
}

phase_git_sync() {
    log "INFO" "SYNC" "Gitリポジトリへ反映中..."
    run "SYNC" git add -A || return $RET_NG
    if git diff-index --quiet HEAD --; then return $RET_NO_CHANGE; fi
    run "SYNC" git commit -m "$COMMIT_MSG" || return $RET_NG
    run "SYNC" git push origin "$BRANCH_NAME"
}

# ------------------------------------------------------------------------------
# 6. メイン実行フロー
# ------------------------------------------------------------------------------
phase_git_update      || die "Git更新に失敗しました。"
log "SUCCESS" "GIT" "完了"

phase_analyze_delta   || die "差分解析(SGD)に失敗しました。"
log "SUCCESS" "DELTA" "完了"

phase_retrieve_metadata || die "メタデータの取得に失敗しました。"
log "SUCCESS" "RETRIEVE" "完了"

phase_git_sync
RES=$?

if [[ $RES -eq $RET_OK ]]; then
    log "SUCCESS" "SYNC" "完了: リポジトリを最新に更新しました。"
elif [[ $RES -eq $RET_NO_CHANGE ]]; then
    log "SUCCESS" "SYNC" "完了: Salesforce組織側に変更はありませんでした。"
else
    die "Gitへの同期中にエラーが発生しました。"
fi

log "HEADER" "" "🎉 すべての工程が正常に完了しました"
exit $RET_OK