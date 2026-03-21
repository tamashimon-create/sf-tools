#!/bin/bash
# ==============================================================================
# sf-init.sh - 新規 Salesforce プロジェクトの初期セットアップ
# ==============================================================================
# 新しい force-xxx プロジェクトを GitHub に作成し、sf-tools と連携させるまでの
# 一連のセットアップを自動化する。
#
# 【処理フロー】
#   Phase 1: 環境チェック（ツール確認・GitHub CLI 認証確認）
#   Phase 2: プロジェクト情報の入力（owner・プロジェクト名・クローン先）
#   Phase 3: リポジトリ作成（gh repo create + git clone）
#   Phase 4: Salesforce 初期接続（sf org login web）
#   Phase 5: ファイル生成（sf-install.sh / sf-hook.sh）
#   Phase 6: ブランチ構成（sf-branch.sh）
#   Phase 7: GitHub Secrets の設定（Salesforce 認証 URL / PAT_TOKEN / Slack）
#   Phase 8: 初回コミット＆プッシュ
#   Phase 9: Ruleset の設定（repo-settings.sh）
#
# 【手動操作が必要なステップ】
#   - Salesforce 組織へのブラウザログイン
#   - GitHub Fine-grained PAT トークンの作成
#   - Slack App の作成・Bot Token の取得
#
# 【使い方】
#   ~/sf-tools/sf-init.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
# sf-init.sh はプロジェクト外から実行するため、ログは sf-tools 配下に記録する
mkdir -p "$HOME/sf-tools/logs" 2>/dev/null || true
readonly LOG_FILE="$HOME/sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"

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
# 3. 変数定義
# ------------------------------------------------------------------------------
GITHUB_OWNER=""       # GitHub ユーザー名または組織名
PROJECT_NAME=""       # force- 以降のプロジェクト名（例: admin）
REPO_NAME=""          # リポジトリ名（例: force-admin）
REPO_FULL_NAME=""     # OWNER/REPO 形式（例: tamashimon/force-admin）
REPO_DIR=""           # クローン先の絶対パス
BRANCH_COUNT=1        # ブランチ階層数（sf-branch.sh 実行後に取得）

# ------------------------------------------------------------------------------
# 4. ヘルパー関数
# ------------------------------------------------------------------------------

# ブラウザを開く（OS 判定）
open_browser() {
    local url="$1"
    if command -v start &>/dev/null; then
        start "" "$url" 2>/dev/null || true
    elif command -v open &>/dev/null; then
        open "$url" 2>/dev/null || true
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url" 2>/dev/null || true
    fi
}

# Enter キー待ち
press_enter() {
    local msg="${1:-続行するには Enter キーを押してください...}"
    echo ""
    read -rp "  ▶ $msg"
}

# Salesforce 認証 URL を取得して GitHub Secret に登録する
# 引数: alias、secret name、org type label
register_sf_secret() {
    local org_alias="$1"
    local secret_name="$2"
    local label="$3"

    log "INFO" "${label}（${org_alias}）に接続します。ブラウザが開くのでログインしてください。"
    press_enter

    local login_opts="--alias $org_alias"
    if [[ "$org_alias" != "prod" ]]; then
        login_opts="$login_opts --instance-url https://test.salesforce.com"
    fi

    # shellcheck disable=SC2086
    run sf org login web $login_opts \
        || die "${label}へのログインに失敗しました。"

    log "INFO" "認証 URL を取得中..."
    local sf_json auth_url
    sf_json=$(run sf org display --verbose --json --target-org "$org_alias" 2>/dev/null)
    auth_url=$(echo "$sf_json" \
        | grep '"sfdxAuthUrl"' \
        | sed 's/.*"sfdxAuthUrl": *"\([^"]*\)".*/\1/')

    [[ -z "$auth_url" ]] && die "${label}の認証 URL を取得できませんでした。\n  sf org display の出力を確認してください。"

    echo "$auth_url" | run gh secret set "$secret_name" -R "$REPO_FULL_NAME" \
        || die "${secret_name} の登録に失敗しました。"

    log "SUCCESS" "${secret_name} を登録しました。"
}

# ------------------------------------------------------------------------------
# 5. フェーズ定義
# ------------------------------------------------------------------------------

# 【CHECK】必要なツールと GitHub CLI 認証の確認
phase_check_environment() {
    log "INFO" "必要なツールを確認中..."

    local missing=0
    for cmd in git gh node npm sf code; do
        if command -v "$cmd" &>/dev/null; then
            local ver
            ver=$("$cmd" --version 2>&1 | head -1)
            log "INFO" "  ✅ $cmd: $ver"
        else
            log "ERROR" "  ❌ $cmd が見つかりません"
            missing=1
        fi
    done

    [[ $missing -eq 1 ]] && die "必要なツールが不足しています。インストール後に再実行してください。"

    log "INFO" "GitHub CLI の認証状態を確認中..."
    if ! gh auth status &>/dev/null; then
        log "WARNING" "GitHub CLI が未認証です。ログインします..."
        run gh auth login || die "GitHub 認証に失敗しました。"
    fi
    log "SUCCESS" "環境チェック完了。"
    return $RET_OK
}

# 【INPUT】プロジェクト情報の入力
phase_ask_project_info() {
    log "INFO" "プロジェクト情報を入力してください。"
    echo ""

    while [[ -z "$GITHUB_OWNER" ]]; do
        read -rp "  GitHub ユーザー名または組織名: " GITHUB_OWNER
    done

    while [[ -z "$PROJECT_NAME" ]]; do
        read -rp "  プロジェクト名（force- の後の部分、例: admin）: " PROJECT_NAME
    done

    local clone_base
    read -rp "  クローン先ディレクトリ（デフォルト: $(pwd)）: " clone_base
    clone_base="${clone_base:-$(pwd)}"

    REPO_NAME="force-${PROJECT_NAME}"
    REPO_FULL_NAME="${GITHUB_OWNER}/${REPO_NAME}"
    REPO_DIR="${clone_base}/${REPO_NAME}"

    echo ""
    log "INFO" "  リポジトリ: ${REPO_FULL_NAME}"
    log "INFO" "  クローン先: ${REPO_DIR}"

    read -rp "  ▶ よろしいですか？ [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn] ]] && die "セットアップを中断しました。"

    return $RET_OK
}

# 【CREATE】GitHub リポジトリの作成とクローン
phase_create_repository() {
    log "INFO" "GitHub リポジトリを作成中..."

    run gh repo create "$REPO_FULL_NAME" \
        --template tama-create/force-template \
        --private \
        || die "リポジトリの作成に失敗しました。"

    log "INFO" "リポジトリをクローン中..."
    local clone_base
    clone_base="$(dirname "$REPO_DIR")"
    mkdir -p "$clone_base" || die "クローン先ディレクトリを作成できません: $clone_base"

    run git clone "https://github.com/${REPO_FULL_NAME}.git" "$REPO_DIR" \
        || die "クローンに失敗しました。"

    log "SUCCESS" "リポジトリを作成・クローンしました: ${REPO_DIR}"
    return $RET_OK
}

# 【SF LOGIN】Salesforce 初期接続（開発組織）
phase_initial_sf_login() {
    log "INFO" "Salesforce 開発組織に接続します。"
    echo ""
    echo "  ブラウザが開くので、普段使用している開発用 Sandbox にログインしてください。"
    echo "  ※ ログイン後、sf-tools の初期設定が続きます。"
    echo ""

    local dev_alias
    read -rp "  開発組織のエイリアス名（例: develop）: " dev_alias
    dev_alias="${dev_alias:-develop}"

    local instance_url_opt=""
    local is_sandbox
    read -rp "  Sandbox ですか？ [Y/n]: " is_sandbox
    if [[ ! "$is_sandbox" =~ ^[Nn] ]]; then
        instance_url_opt="--instance-url https://test.salesforce.com"
    fi

    # shellcheck disable=SC2086
    cd "$REPO_DIR" && run sf org login web --alias "$dev_alias" $instance_url_opt \
        || die "Salesforce へのログインに失敗しました。"

    log "SUCCESS" "Salesforce 開発組織への接続完了（エイリアス: ${dev_alias}）。"
    return $RET_OK
}

# 【INSTALL】sf-install.sh でファイル生成・フック設定
phase_generate_files() {
    log "INFO" "sf-tools の初期設定ファイルを生成中..."

    cd "$REPO_DIR" || die "ディレクトリに移動できません: $REPO_DIR"

    run bash "$SCRIPT_DIR/sf-install.sh" \
        || die "sf-install.sh の実行に失敗しました。"

    run bash "$SCRIPT_DIR/sf-hook.sh" \
        || die "sf-hook.sh の実行に失敗しました。"

    log "SUCCESS" "設定ファイルの生成完了。"
    return $RET_OK
}

# 【BRANCH】sf-branch.sh でブランチ構成を選択・作成
phase_setup_branches() {
    log "INFO" "ブランチ構成を選択してください。"

    cd "$REPO_DIR" || die "ディレクトリに移動できません: $REPO_DIR"

    run bash "$SCRIPT_DIR/sf-branch.sh" \
        || die "sf-branch.sh の実行に失敗しました。"

    # branches.txt からブランチ階層数を取得
    local branches_file="$REPO_DIR/sf-tools/config/branches.txt"
    if [[ -f "$branches_file" ]]; then
        BRANCH_COUNT=$(grep -v '^[[:space:]]*#' "$branches_file" \
            | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
    fi

    log "SUCCESS" "ブランチ構成の設定完了（${BRANCH_COUNT} 階層）。"
    return $RET_OK
}

# 【SECRETS-SF】Salesforce 認証 URL の取得と登録
phase_setup_sf_secrets() {
    log "HEADER" "GitHub Secrets（Salesforce 認証）を設定します。"

    # 本番組織（必須）
    register_sf_secret "prod" "SFDX_AUTH_URL_PROD" "本番組織"

    # ステージング組織（2階層以上）
    if [[ $BRANCH_COUNT -ge 2 ]]; then
        register_sf_secret "staging" "SFDX_AUTH_URL_STG" "ステージング組織"
    fi

    # 開発組織（3階層）
    if [[ $BRANCH_COUNT -ge 3 ]]; then
        register_sf_secret "develop" "SFDX_AUTH_URL_DEV" "開発組織"
    fi

    log "SUCCESS" "Salesforce Secrets の登録完了。"
    return $RET_OK
}

# 【SECRETS-PAT】GitHub PAT_TOKEN の作成支援と登録
phase_setup_pat_token() {
    log "HEADER" "GitHub Secrets（PAT_TOKEN）を設定します。"
    echo ""
    echo "  ワークフローがブランチ保護をバイパスして push するために必要です。"
    echo ""
    echo "  ブラウザで Fine-grained tokens のページを開きます。"
    echo "  以下の設定でトークンを生成してください:"
    echo ""
    echo "    Token name      : sf-metasync（任意）"
    echo "    Repository      : Only select repositories → ${REPO_FULL_NAME}"
    echo "    Permissions     : Contents → Read and write"
    echo ""
    open_browser "https://github.com/settings/tokens?type=beta"
    press_enter "トークンを生成したら Enter を押してください..."

    local pat_token=""
    while [[ -z "$pat_token" ]]; do
        read -rsp "  生成されたトークンを貼り付けてください（入力は非表示）: " pat_token
        echo ""
    done

    echo "$pat_token" | run gh secret set PAT_TOKEN -R "$REPO_FULL_NAME" \
        || die "PAT_TOKEN の登録に失敗しました。"

    log "SUCCESS" "PAT_TOKEN を登録しました。"
    return $RET_OK
}

# 【SECRETS-SLACK】Slack Bot Token と Channel ID の取得支援と登録
phase_setup_slack() {
    log "HEADER" "GitHub Secrets（Slack 連携）を設定します。"
    echo ""
    echo "  ブラウザで Slack API ページを開きます。"
    echo "  以下の手順で Bot Token を取得してください:"
    echo ""
    echo "    1. 「Create New App」→「From scratch」"
    echo "    2. App 名とワークスペースを設定"
    echo "    3. 左メニュー「OAuth & Permissions」→ Scopes → chat:write を追加"
    echo "    4. 「Install to Workspace」→ 許可する"
    echo "    5. 表示される「Bot User OAuth Token」（xoxb-...）をコピー"
    echo ""
    open_browser "https://api.slack.com/apps"
    press_enter "Bot Token を取得したら Enter を押してください..."

    local slack_token=""
    while [[ -z "$slack_token" ]]; do
        read -rsp "  Bot User OAuth Token を貼り付けてください（入力は非表示）: " slack_token
        echo ""
    done

    echo "$slack_token" | run gh secret set SLACK_BOT_TOKEN -R "$REPO_FULL_NAME" \
        || die "SLACK_BOT_TOKEN の登録に失敗しました。"
    log "SUCCESS" "SLACK_BOT_TOKEN を登録しました。"

    echo ""
    echo "  通知先 Slack チャンネルの ID を入力します。"
    echo "  確認方法: チャンネルを開く → チャンネル名をクリック → 最下部に「チャンネル ID」"
    echo "            C から始まる文字列（例: C01ABCDEFGH）"
    echo ""

    local channel_id=""
    while [[ -z "$channel_id" ]]; do
        read -rp "  チャンネル ID: " channel_id
    done

    echo "$channel_id" | run gh secret set SLACK_CHANNEL_ID -R "$REPO_FULL_NAME" \
        || die "SLACK_CHANNEL_ID の登録に失敗しました。"
    log "SUCCESS" "SLACK_CHANNEL_ID を登録しました。"

    return $RET_OK
}

# 【COMMIT】初回コミット＆プッシュ
phase_initial_commit() {
    log "INFO" "初回コミット＆プッシュを実行中..."

    cd "$REPO_DIR" || die "ディレクトリに移動できません: $REPO_DIR"

    # コミット対象ファイルの確認
    log "INFO" "変更ファイル:"
    git status --short

    run git add -A \
        || die "git add に失敗しました。"
    run git commit -m "chore: sf-tools 初期セットアップ" \
        || die "git commit に失敗しました。"
    run git push origin main \
        || die "git push に失敗しました。"

    log "SUCCESS" "初回コミット＆プッシュ完了。"
    return $RET_OK
}

# 【RULESET】Ruleset の設定
phase_setup_rulesets() {
    log "INFO" "Ruleset を設定中..."

    run bash "$SCRIPT_DIR/repo-settings.sh" "$REPO_FULL_NAME" \
        || die "Ruleset の設定に失敗しました。"

    log "SUCCESS" "Ruleset の設定完了。"
    return $RET_OK
}

# ------------------------------------------------------------------------------
# 6. メイン実行フロー
# ------------------------------------------------------------------------------
log "HEADER" "新規 Salesforce プロジェクトの初期セットアップを開始します (${SCRIPT_NAME}.sh)"

phase_check_environment  || die "環境チェックに失敗しました。"
log "SUCCESS" "環境チェック完了。"

phase_ask_project_info   || die "プロジェクト情報の入力に失敗しました。"

phase_create_repository  || die "リポジトリの作成に失敗しました。"

phase_initial_sf_login   || die "Salesforce への接続に失敗しました。"

phase_generate_files     || die "ファイル生成に失敗しました。"

phase_setup_branches     || die "ブランチ構成のセットアップに失敗しました。"

phase_setup_sf_secrets   || die "Salesforce Secrets の設定に失敗しました。"

phase_setup_pat_token    || die "PAT_TOKEN の設定に失敗しました。"

phase_setup_slack        || die "Slack 連携の設定に失敗しました。"

phase_initial_commit     || die "初回コミットに失敗しました。"

phase_setup_rulesets     || die "Ruleset の設定に失敗しました。"

echo "-------------------------------------------------------"
log "INFO" "次のステップ: cd \"${REPO_DIR}\" で作業ディレクトリへ移動してください。"
log "INFO" "以降の開発は sf-start.sh で VS Code を起動して開始してください。"
log "HEADER" "セットアップが完了しました"

exit $RET_OK
