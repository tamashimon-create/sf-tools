#!/bin/bash

# ==============================================================================
# sf-metasync.sh - Salesforce メタデータ Git 自動同期スクリプト
# ==============================================================================
# Salesforce 組織の最新メタデータを取得し、Git リポジトリへ自動反映します。
#   1. Git の最新状態をプル (Rebase)
#   2. SGD (Salesforce Git Diff) による差分抽出
#   3. 組織からのメタデータ取得 (Retrieve)
#   4. 変更がある場合のみ Git Commit & Push
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"
readonly SILENT_EXEC=0

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
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "メタデータ同期（Salesforce -> Git）を開始します"

# ------------------------------------------------------------------------------
# 4. 固有設定
# ------------------------------------------------------------------------------
TARGET_ORG=$(get_target_org) || die "接続先組織を特定できませんでした。"
log "INFO" "接続先組織: ${TARGET_ORG}"

BRANCH_NAME=$(run git symbolic-ref --short HEAD 2>/dev/null || echo "main")
DELTA_DIR="./temp_delta_$$"

# DELTA_DIR 定義後に trap を設定（未定義のまま rm -rf が実行されないようにする）
trap 'rm -rf "$DELTA_DIR" ./cmd_out_*.tmp 2>/dev/null' EXIT

readonly COMMIT_MSG="定期更新: Salesforce変更の自動反映 ($(date +'%Y-%m-%d'))"
readonly METADATA_TYPES=(ApexClass ApexPage LightningComponentBundle CustomObject CustomField Layout FlexiPage Flow PermissionSet CustomLabels)

# ------------------------------------------------------------------------------
# 5. フェーズ定義
# ------------------------------------------------------------------------------

# 【GIT】リモートの変更を取り込む
phase_git_update() {
    log "INFO" "リモートの最新状態を取り込んでいます..."

    # ローカルに未コミットの変更があれば一時退避し、処理後に復元する
    local stashed=0
    if ! run git diff-index --quiet HEAD --; then
        run git stash || return $RET_NG
        stashed=1
    fi

    run git fetch origin || log "WARNING" "git fetch に失敗しました。ローカルキャッシュで続行します。"

    if ! run git pull origin "$BRANCH_NAME" --rebase; then
        run git rebase --abort
        [[ $stashed -eq 1 ]] && run git stash pop
        return $RET_NG
    fi

    [[ $stashed -eq 1 ]] && run git stash pop
    return $RET_OK
}

# 【DELTA】SGD による差分解析
phase_analyze_delta() {
    log "INFO" "前回の同期からの変更箇所 (SGD) を解析中..."
    run mkdir -p "$DELTA_DIR"
    run sf sgd source delta --from "origin/$BRANCH_NAME" --to HEAD --output-dir "$DELTA_DIR" || return $RET_NG
    return $RET_OK
}

# 【RETRIEVE】組織からメタデータを取得
phase_retrieve_metadata() {
    # SGD で生成された package.xml があればそれを使用して差分取得
    if [[ -f "$DELTA_DIR/package/package.xml" ]]; then
        log "INFO" "SGD で特定された差分ファイルをダウンロード中..."
        run sf project retrieve start \
            --manifest "$DELTA_DIR/package/package.xml" \
            --target-org "$TARGET_ORG" \
            --ignore-conflicts \
            --json
    fi

    # 主要メタデータの整合性確保のために再取得（型ごとに --metadata を分けて指定）
    log "INFO" "主要メタデータの整合性をチェック中..."
    local retrieve_cmd=("sf" "project" "retrieve" "start" "--target-org" "$TARGET_ORG" "--ignore-conflicts" "--json")
    for type in "${METADATA_TYPES[@]}"; do
        retrieve_cmd+=("--metadata" "$type")
    done
    run "${retrieve_cmd[@]}"
}

# 【SYNC】変更を Git へ反映
phase_git_sync() {
    log "INFO" "Git リポジトリへ反映中..."
    run git add -A || return $RET_NG

    # ステージに変更がなければ早期終了
    if run git diff-index --quiet HEAD --; then
        return $RET_NO_CHANGE
    fi

    run git commit -m "$COMMIT_MSG" || return $RET_NG
    run git push origin "$BRANCH_NAME" || return $RET_NG
}

# ------------------------------------------------------------------------------
# 6. メインフロー
# ------------------------------------------------------------------------------
phase_git_update        || die "Git 更新に失敗しました。"
log "SUCCESS" "Git 更新完了"

phase_analyze_delta     || die "差分解析 (SGD) に失敗しました。"
log "SUCCESS" "差分解析完了"

phase_retrieve_metadata || die "メタデータの取得に失敗しました。"
log "SUCCESS" "メタデータ取得完了"

phase_git_sync
RES=$?

if [[ $RES -eq $RET_OK ]]; then
    log "SUCCESS" "完了: リポジトリを最新に更新しました。"
elif [[ $RES -eq $RET_NO_CHANGE ]]; then
    log "SUCCESS" "完了: Salesforce 組織側に変更はありませんでした。"
else
    die "Git への同期中にエラーが発生しました。"
fi

exit $RET_OK
