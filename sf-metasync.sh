#!/bin/bash
# ==============================================================================
# sf-metasync.sh - SalesforceメタデータのGit自動同期スクリプト (完全版)
# ------------------------------------------------------------------------------
# [処理概要]
#   1. Gitの最新状態をプル (Rebase)
#   2. SGD (Salesforce git diff) による差分抽出
#   3. 組織からのメタデータ取得 (Retrieve)
#   4. 変更がある場合のみ Git Commit & Push
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"         # 実行のたびにログをリセット
readonly SILENT_EXEC=1          # コマンドの標準出力はログファイルのみに記録

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
# 3. 初期チェック
# ------------------------------------------------------------------------------
# プロジェクトディレクトリ（force-で始まる）にいるか確認
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "" "メタデータ同期（Sandbox -> Git）を開始します"

# 一時ファイルおよび一時ディレクトリの自動削除設定
DELTA_DIR="./temp_delta_$$"
trap 'rm -rf "$DELTA_DIR" ./cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. 固有設定
# ------------------------------------------------------------------------------
# ターゲット組織の特定
TARGET_ORG=$(get_target_org) || die "接続先組織を特定できませんでした。"
log "INFO" "INIT" "接続先組織: ${TARGET_ORG}"

# 現在のブランチ名を取得
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

# コミットメッセージと対象メタデータ型の定義
readonly COMMIT_MSG="定期更新: Salesforce変更の自動反映 ($(date +'%Y-%m-%d'))"
readonly METADATA_TYPES=(ApexClass ApexPage LightningComponentBundle CustomObject CustomField Layout FlexiPage Flow PermissionSet CustomLabels)

# ------------------------------------------------------------------------------
# 5. 各作業フェーズの定義
# ------------------------------------------------------------------------------

# 【GITフェーズ】リモートの変更を取り込む
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

# 【DELTAフェーズ】差分解析
phase_analyze_delta() {
    log "INFO" "DELTA" "前回の同期からの変更箇所(SGD)を解析中..."
    mkdir -p "$DELTA_DIR"
    # sf sgd を使用して差分を抽出
    run "DELTA" sf sgd source delta --from "origin/$BRANCH_NAME" --to HEAD --output-dir "$DELTA_DIR"
}

# 【RETRIEVEフェーズ】メタデータ取得
phase_retrieve_metadata() {
    # SGDで生成された package.xml があればそれを使用
    if [[ -f "$DELTA_DIR/package/package.xml" ]]; then
        log "INFO" "RETRIEVE" "SGDで特定された差分ファイルをダウンロード中..."
        run "RETRIEVE" sf project retrieve start --manifest "$DELTA_DIR/package/package.xml" --target-org "$TARGET_ORG" --ignore-conflicts
    fi
    # 主要メタデータの整合性確保のために再取得
    log "INFO" "RETRIEVE" "主要メタデータの整合性をチェック中..."
    run "RETRIEVE" sf project retrieve start --metadata "${METADATA_TYPES[@]}" --target-org "$TARGET_ORG" --ignore-conflicts
}

# 【SYNCフェーズ】Gitへの反映
phase_git_sync() {
    log "INFO" "SYNC" "Gitリポジトリへ反映中..."
    run "SYNC" git add -A || return $RET_NG
    
    # 変更があるか確認。なければ早期終了
    if git diff-index --quiet HEAD --; then 
        return $RET_NO_CHANGE
    fi
    
    run "SYNC" git commit -m "$COMMIT_MSG" || return $RET_NG
    run "SYNC" git push origin "$BRANCH_NAME"
}

# ------------------------------------------------------------------------------
# 6. メイン実行フロー (Dispatcher)
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

exit $RET_OK