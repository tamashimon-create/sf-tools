#!/bin/bash

# ==============================================================================
# sf-metasync.sh - Salesforce メタデータ Git 自動同期スクリプト
# ==============================================================================
# 本番組織の最新メタデータを取得し、main ブランチへ自動反映します。
# ※ main ブランチ・本番組織への接続時のみ実行可能（Sandbox / 他ブランチは即エラー）
# ※ Salesforce 組織の変更を正とする。ローカルの未コミット変更がある場合は中止。
#   1. 実行条件チェック（main ブランチ・本番組織・ローカル変更なしであることを確認）
#   2. Git の最新状態をプル (Rebase)
#   3. SGD (Salesforce Git Diff) による差分抽出
#   4. 組織からのメタデータ取得 (Retrieve)
#   5. 変更がある場合のみ Git Commit & Push
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

log "HEADER" "メタデータ同期（Salesforce -> Git）を開始します (${SCRIPT_NAME}.sh)"

# ------------------------------------------------------------------------------
# 4. 固有設定
# ------------------------------------------------------------------------------
TARGET_ORG=$(get_target_org) || die "接続先組織を特定できませんでした。"
log "INFO" "接続先組織: ${TARGET_ORG}"

BRANCH_NAME=$(run git symbolic-ref --short HEAD 2>/dev/null || echo "main")

# main ブランチ以外での実行を禁止
[[ "$BRANCH_NAME" != "main" ]] \
    && die "このスクリプトは main ブランチでのみ実行できます（現在: ${BRANCH_NAME}）。"

# Sandbox への接続中は実行を禁止（本番組織のみ許可）
ORG_DISPLAY_JSON=$(run sf org display --json 2>/dev/null || echo "")
if echo "$ORG_DISPLAY_JSON" | grep -qi '"isSandbox".*true'; then
    die "Sandbox 組織への接続中は実行できません。本番組織に接続してから再実行してください。"
fi

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

    # main ブランチのローカル変更は Salesforce 組織の内容より優先されないため中止する
    # （stash して復元すると、ローカル変更が retrieve 後にコミットされてしまうため）
    if ! run git diff-index --quiet HEAD --; then
        die "main ブランチにローカルの未コミット変更があります。Salesforce 組織の内容を正として同期するため、ローカル変更は反映しません。変更を破棄（git checkout .）してから再実行してください。"
    fi

    run git fetch origin || log "WARNING" "git fetch に失敗しました。ローカルキャッシュで続行します。"

    if ! run git pull origin "$BRANCH_NAME" --rebase; then
        run git rebase --abort
        return $RET_NG
    fi

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

# 【PROPAGATE】main の変更を下流ブランチへ伝播 (main → staging → development)
phase_propagate_downstream() {
    local prev_branch="main"
    for branch in staging development; do
        # リモートにブランチが存在するか確認（出力は不要なため直接呼び出し）
        if ! git ls-remote --exit-code --heads origin "$branch" > /dev/null 2>&1; then
            log "WARNING" "${branch} ブランチがリモートに存在しないためスキップします"
            continue
        fi

        log "INFO" "${prev_branch} → ${branch} へマージします..."

        if ! run git checkout "$branch"; then
            log "WARNING" "${branch} のチェックアウトに失敗しました（スキップ）"
            continue
        fi

        if ! run git pull origin "$branch" --rebase; then
            log "WARNING" "${branch} の pull に失敗しました（スキップ）"
            run git rebase --abort 2>/dev/null
            run git checkout main
            continue
        fi

        if ! run git merge "$prev_branch" --no-edit; then
            log "WARNING" "${branch} へのマージに失敗しました（スキップ）"
            run git merge --abort 2>/dev/null
            run git checkout main
            continue
        fi

        if ! run git push origin "$branch"; then
            log "WARNING" "${branch} の push に失敗しました（スキップ）"
            run git checkout main
            continue
        fi

        log "SUCCESS" "${branch} への伝播が完了しました"
        prev_branch="$branch"  # 成功時のみ更新（失敗時は前のブランチからマージを継続）
    done

    # 作業ブランチを main に戻す
    run git checkout main || die "main ブランチへの復帰に失敗しました。"
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
    phase_propagate_downstream || die "下流ブランチへの伝播に失敗しました。"
    log "SUCCESS" "下流ブランチへの伝播完了 (main → staging → development)"
elif [[ $RES -eq $RET_NO_CHANGE ]]; then
    log "SUCCESS" "完了: Salesforce 組織側に変更はありませんでした。"
else
    die "Git への同期中にエラーが発生しました。"
fi

exit $RET_OK
