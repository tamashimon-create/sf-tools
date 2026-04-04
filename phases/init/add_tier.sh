#!/bin/bash
# ==============================================================================
# add_tier.sh - ブランチ tier の追加（staging / develop）
# ==============================================================================
# 既存プロジェクトに staging または develop 階層を追加する。
# sf-init.sh --add-tier から呼び出される。
#
# 【処理フロー】
#   1. .sf-init.env を読み込んでプロジェクト情報を取得
#   2. 追加 tier のバリデーション（すでに存在する場合はエラー）
#   3. sf-branch.sh で branches.txt を更新・GitHub にブランチを作成
#   4. JWT 認証情報（SF_CONSUMER_KEY_xxx / SF_USERNAME_xxx / SF_INSTANCE_URL_xxx）を登録
#   5. branches.txt をコミット・プッシュ
#
# 【登録する Secrets / Variables】
#   staging 追加時: SF_CONSUMER_KEY_STG（Secret）/ SF_USERNAME_STG / SF_INSTANCE_URL_STG（Variable）
#   develop 追加時: SF_CONSUMER_KEY_DEV（Secret）/ SF_USERNAME_DEV / SF_INSTANCE_URL_DEV（Variable）
# ==============================================================================

# SF_TOOLS_DIR は sf-init.sh（司令塔）から export される
PHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SF_TOOLS_DIR="${SF_TOOLS_DIR:-$(dirname "$PHASE_DIR")}"

readonly SCRIPT_NAME="sf-init"
mkdir -p "$HOME/sf-tools/logs" 2>/dev/null || true
readonly LOG_FILE="$HOME/sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"
export SF_INIT_MODE=1

source "${SF_TOOLS_DIR}/lib/common.sh"
source "${SF_TOOLS_DIR}/phases/init/init-common.sh"

# ------------------------------------------------------------------------------
# 引数取得
# ------------------------------------------------------------------------------
ADD_TIER="${ADD_TIER:-}"  # sf-init.sh から export される
[[ -z "$ADD_TIER" ]] && die "ADD_TIER が未設定です。"

# ------------------------------------------------------------------------------
# 1. force-* ディレクトリであること確認
# ------------------------------------------------------------------------------
log "HEADER" "tier 追加: ${ADD_TIER}"

check_force_dir || die "force-* ディレクトリ内で実行してください。"

# ------------------------------------------------------------------------------
# 2. .sf-init.env を読み込む
# ------------------------------------------------------------------------------
BRANCHES_FILE="${PWD}/sf-tools/config/branches.txt"
SF_INIT_ENV_FILE="${PWD}/sf-tools/config/.sf-init.env"

# .sf-init.env が見つからない場合は git remote から REPO_FULL_NAME を導出する
if [[ -f "$SF_INIT_ENV_FILE" ]]; then
    source "$SF_INIT_ENV_FILE"
else
    # VAR=$(cmd) 形式のため run 不使用
    remote_url=$(git remote get-url origin 2>/dev/null) || die ".sf-init.env が見つからず、git remote も取得できません。"
    REPO_FULL_NAME=$(echo "$remote_url" | sed 's|.*github\.com[:/]\(.*\)\.git|\1|; s|.*github\.com[:/]\(.*\)|\1|')
    REPO_NAME=$(basename "$REPO_FULL_NAME")
fi

[[ -z "$REPO_FULL_NAME" ]] && die "REPO_FULL_NAME が取得できません。"
[[ -z "$REPO_NAME"      ]] && die "REPO_NAME が取得できません。"

# ------------------------------------------------------------------------------
# 3. 追加 tier のバリデーション
# ------------------------------------------------------------------------------
case "$ADD_TIER" in
    staging)
        SUFFIX="STG"
        LABEL="ステージング組織"
        ORG_ALIAS="staging"
        ;;
    develop)
        SUFFIX="DEV"
        LABEL="開発組織"
        ORG_ALIAS="develop"
        ;;
    *)
        die "--add-tier には staging または develop を指定してください。"
        ;;
esac

# branches.txt に既に存在するか確認
if [[ -f "$BRANCHES_FILE" ]]; then
    if grep -qx "$ADD_TIER" "$BRANCHES_FILE" 2>/dev/null; then
        die "${ADD_TIER} はすでに branches.txt に登録されています。"
    fi
fi

# develop を追加する場合は staging が先に存在するか確認
if [[ "$ADD_TIER" == "develop" ]]; then
    if ! grep -qx "staging" "$BRANCHES_FILE" 2>/dev/null; then
        die "develop を追加するには先に staging が必要です。先に --add-tier staging を実行してください。"
    fi
fi

log "INFO" "  対象リポジトリ: ${REPO_FULL_NAME}"
log "INFO" "  追加 tier     : ${ADD_TIER}（${LABEL}）"

# ------------------------------------------------------------------------------
# 4. ブランチを追加（sf-branch.sh を利用）
# ------------------------------------------------------------------------------
log "HEADER" "Step 1: ${ADD_TIER} ブランチを追加します。"

# sf-branch.sh を呼び出す（対話メニューをスキップするため直接 branches.txt を更新してブランチ作成）
# branches.txt に ADD_TIER を追記
TMP_BRANCH_FILE="${BRANCHES_FILE}.tmp"
{
    if [[ -f "$BRANCHES_FILE" ]]; then
        # 既存コメント行を保持
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            echo "$line"
        done < "$BRANCHES_FILE"
    fi
    echo "$ADD_TIER"
} > "$TMP_BRANCH_FILE"
run mv "$TMP_BRANCH_FILE" "$BRANCHES_FILE"
log "SUCCESS" "branches.txt に ${ADD_TIER} を追記しました。"

# リモートにブランチを作成（main から派生）
if git ls-remote --exit-code --heads origin "$ADD_TIER" > /dev/null 2>&1; then
    # 条件チェックのため run 不使用
    log "INFO" "${ADD_TIER} ブランチはリモートに既に存在します（スキップ）。"
else
    run git checkout main            || die "main ブランチへの切り替えに失敗しました。"
    run git checkout -b "$ADD_TIER"  || die "${ADD_TIER} ブランチの作成に失敗しました。"
    run git push --no-verify -u origin "$ADD_TIER" \
        || die "${ADD_TIER} ブランチのプッシュに失敗しました。"
    run git checkout main            || die "main ブランチへの切り替えに失敗しました。"
    log "SUCCESS" "${ADD_TIER} ブランチを作成しました。"
fi

# ------------------------------------------------------------------------------
# 5. JWT 認証情報を登録
# ------------------------------------------------------------------------------
log "HEADER" "Step 2: ${LABEL} の JWT 認証情報を設定します。"

JWT_DIR="$HOME/.sf-jwt/${REPO_NAME}"
[[ ! -f "${JWT_DIR}/server.key" ]] && die "秘密鍵が見つかりません: ${JWT_DIR}/server.key\n  sf-init Phase 10 を先に実行してください。"

register_jwt_secret "$ORG_ALIAS" "$SUFFIX" "$LABEL" "${JWT_DIR}/server.key"

# ------------------------------------------------------------------------------
# 6. branches.txt をコミット・プッシュ
# ------------------------------------------------------------------------------
log "HEADER" "Step 3: branches.txt をコミット・プッシュします。"

run git add sf-tools/config/branches.txt \
    || die "git add に失敗しました。"
run git commit --no-verify -m "chore: ${ADD_TIER} tier を追加" \
    || die "git commit に失敗しました。"
run git push --no-verify origin main \
    || die "git push に失敗しました。"

log "SUCCESS" "tier 追加完了: ${ADD_TIER}（${LABEL}）"
log "INFO"    "次のステップ:"
log "INFO"    "  ・Salesforce Sandbox の Connected App で ${ADD_TIER} 用プロファイルを追加してください。"
log "INFO"    "  ・GitHub Actions（wf-release / wf-validate）が ${ADD_TIER} ブランチに対して動作することを確認してください。"

exit $RET_OK
