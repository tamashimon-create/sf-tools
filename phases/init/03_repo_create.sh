#!/bin/bash
# ==============================================================================
# 03_repo_create.sh - Phase 3: リポジトリ作成
# ==============================================================================
# GitHub リポジトリを作成し、ローカルにクローンする。
# リポジトリ・クローン先が既に存在する場合はスキップ（冪等）。
#
# 【可視性ルール】
#   tama-create 配下はテスト用のため Public（Ruleset 利用可）
#   その他の組織・ユーザーは Private
#
# 【WF 配布】
#   クローン後に sf-tools/templates/.github/workflows/ の内容を上書きコピーする。
#   force-template から来た WF を sf-tools 管理の正本で置き換える。
# ==============================================================================

# SF_TOOLS_DIR は sf-init.sh（司令塔）から export される
PHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SF_TOOLS_DIR="${SF_TOOLS_DIR:-$(dirname "$PHASE_DIR")}"

readonly SCRIPT_NAME="sf-init"
mkdir -p "$HOME/sf-tools/logs" 2>/dev/null || true
readonly LOG_FILE="$HOME/sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="APPEND"  # 司令塔が NEW で初期化済みのため追記
export SF_INIT_MODE=1

source "${SF_TOOLS_DIR}/lib/common.sh"
source "${SF_TOOLS_DIR}/phases/init/init-common.sh"

# 変数の復元（前フェーズで書き出した .sf-init.env を読み込む）
SF_INIT_ENV_FILE="${SF_INIT_ENV_FILE:-${PWD}/.sf-init.env}"
[[ -f "$SF_INIT_ENV_FILE" ]] && source "$SF_INIT_ENV_FILE"

[[ -z "$REPO_FULL_NAME" ]] && die "REPO_FULL_NAME が未設定です。Phase 2 が完了しているか確認してください。"
[[ -z "$REPO_DIR" ]]       && die "REPO_DIR が未設定です。Phase 2 が完了しているか確認してください。"

# ------------------------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------------------------
log "HEADER" "Phase 3: リポジトリ作成"

# --- リポジトリ作成（冪等: すでに存在する場合はスキップ） ---
if run gh repo view "$REPO_FULL_NAME" --json name 2>/dev/null; then
    log "WARNING" "リポジトリはすでに存在します。作成をスキップします: ${REPO_FULL_NAME}"
else
    log "INFO" "GitHub リポジトリを作成中..."
    # tama-create 配下はテスト用リポジトリのため Public で作成（Ruleset 利用可）
    # その他の組織・ユーザーは Private で作成
    visibility_opt="--private"
    [[ "$GITHUB_OWNER" == "tama-create" ]] && visibility_opt="--public"
    run gh repo create "$REPO_FULL_NAME" \
        --template tama-create/force-template \
        "$visibility_opt"
    # gh repo create --template はテンプレートコピーで非ゼロを返す場合がある。
    # 実際にリポジトリが存在するか確認して判定する。
    if ! run gh repo view "$REPO_FULL_NAME" --json name 2>/dev/null; then
        die "リポジトリの作成に失敗しました。
考えられる原因:
  - GitHub ユーザー名・組織名が誤っている（入力値: ${GITHUB_OWNER}）
  - GitHub CLI の認証トークンの権限が不足している → gh auth status で確認
詳細は ~/sf-tools/logs/sf-init.log を確認してください。"
    fi
    log "SUCCESS" "リポジトリを作成しました: ${REPO_FULL_NAME}"
fi

# --- クローン（冪等: すでに存在する場合はスキップ） ---
if [[ -d "$REPO_DIR/.git" ]]; then
    log "WARNING" "クローン先ディレクトリが既に存在します。クローンをスキップします: ${REPO_DIR}"
elif [[ -d "$REPO_DIR" ]]; then
    die "クローン先ディレクトリが既に存在しますが Git リポジトリではありません: ${REPO_DIR}
手動で削除してから再実行してください。"
else
    log "INFO" "リポジトリをクローン中..."
    clone_base="$(dirname "$REPO_DIR")"
    run mkdir -p "$clone_base" || die "クローン先ディレクトリを作成できません: $clone_base"
    run git clone "https://github.com/${REPO_FULL_NAME}.git" "$REPO_DIR" \
        || die "クローンに失敗しました。"
    log "SUCCESS" "リポジトリをクローンしました: ${REPO_DIR}"
fi

# --- WF コピー（sf-tools/templates/ が正本・force-template 由来を上書き） ---
wf_src="${SF_TOOLS_DIR}/templates/.github/workflows"
wf_dst="${REPO_DIR}/.github/workflows"
log "INFO" "WF ファイルをコピー中: ${wf_src} → ${wf_dst}"
run mkdir -p "$wf_dst" || die "WF ディレクトリを作成できません: $wf_dst"
for wf_file in "$wf_src"/*.yml; do
    run cp "$wf_file" "$wf_dst/" || die "WF ファイルのコピーに失敗しました: $wf_file"
done
log "SUCCESS" "WF ファイルをコピーしました（${wf_src}）"

log "SUCCESS" "Phase 3 完了: リポジトリ作成 OK。"
exit $RET_OK
