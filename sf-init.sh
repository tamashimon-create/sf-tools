#!/bin/bash
# ==============================================================================
# sf-init.sh - 新規 Salesforce プロジェクトの初期セットアップ
# ==============================================================================
# 新しい force-xxx プロジェクトを GitHub に作成し、sf-tools と連携させるまでの
# 一連のセットアップを自動化する。
#
# 【前提フォルダ構成】
#   ~/home/
#   └── {github-owner}/   ← GitHub ユーザー名（フォルダ名から自動取得）
#       └── {company}/    ← プロジェクト名として使用（例: yamada → force-yamada）
#           └── init/     ← このフォルダをカレントにして実行すること
#
# 【処理フロー】
#   Phase 1: 環境チェック（ツール確認・GitHub CLI 認証確認）
#   Phase 2: プロジェクト情報の確認（フォルダ構成からOWNERとプロジェクト名を自動導出）
#   Phase 3: リポジトリ作成（gh repo create + git clone）
#   Phase 4: ファイル生成（sf-install.sh / sf-hook.sh）
#   Phase 5: ブランチ構成（sf-branch.sh）
#   Phase 6: GitHub Secrets の設定（Salesforce 認証 URL / PAT_TOKEN / Slack）
#   Phase 7: 初回コミット＆プッシュ
#   Phase 8: Ruleset の設定（repo-settings.sh）
#
# 【手動操作が必要なステップ】
#   - Salesforce 組織へのブラウザログイン
#   - GitHub Classic PAT トークンの作成（repo + workflow スコープ）
#   - Slack App の作成・Bot Token の取得
#
# 【使い方】
#   mkdir -p ~/home/{github-owner}/{company}/init
#   cd ~/home/{github-owner}/{company}/init
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
# sf-init.sh はプロジェクト外から実行するため、force-* チェックをバイパスする
export SF_INIT_MODE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

trap '' INT  # Ctrl+C を無効化（子プロセスにも継承される）

# ------------------------------------------------------------------------------
# 3. 変数定義
# ------------------------------------------------------------------------------
GITHUB_OWNER=""       # GitHub ユーザー名または組織名
PROJECT_NAME=""       # force- 以降のプロジェクト名（例: yamada）
REPO_NAME=""          # リポジトリ名（例: force-yamada）
REPO_FULL_NAME=""     # OWNER/REPO 形式（例: yamada-corp/force-yamada）
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

# Enter キー待ち（q で中断）
press_enter() {
    local msg="${1:-続行するには Enter キーを押してください（q で中断）...}"
    echo ""
    local _input
    read -rp "  ▶ $msg" _input
    [[ "$_input" == "q" || "$_input" == "Q" ]] && die "セットアップを中断しました。"
}

# 入力を受け取る（q で中断）
# 使い方: read_or_quit 変数名 "プロンプト"
read_or_quit() {
    local -n _rq_var=$1
    local prompt="$2"
    read -rp "$prompt" _rq_var
    [[ "$_rq_var" == "q" || "$_rq_var" == "Q" ]] && die "セットアップを中断しました。"
}

# Salesforce 認証 URL を取得して GitHub Secret に登録する
# 引数: alias、secret name、org type label、[is_sandbox_override: Y/n（省略時は対話で確認）]
register_sf_secret() {
    local org_alias="$1"
    local secret_name="$2"
    local label="$3"
    local is_sandbox_override="${4:-}"   # 省略時は対話で確認

    log "INFO" "${label}（${org_alias}）に接続します。ブラウザが開くのでログインしてください。"
    press_enter

    local login_opts="--alias $org_alias"
    # prod 以外は Sandbox か Developer Edition かを確認してログイン URL を切り替える
    if [[ "$org_alias" != "prod" ]]; then
        local is_sandbox_input
        if [[ -n "$is_sandbox_override" ]]; then
            is_sandbox_input="$is_sandbox_override"
        else
            ask_yn "Sandbox ですか？" && is_sandbox_input="Y" || is_sandbox_input="N"
        fi
        if [[ ! "$is_sandbox_input" =~ ^[Nn] ]]; then
            login_opts="$login_opts --instance-url https://test.salesforce.com"
        fi
    fi

    # sf org login web は MINGW64 等の環境で exit code が信頼できないため直接実行する。
    # 成否は続く sf org display の auth_url 取得で判定する（exit code は無視）。
    log "CMD" "[${SCRIPT_NAME}] sf org login web ${login_opts}"
    # shellcheck disable=SC2086
    sf org login web $login_opts || true

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
    # init フォルダからのみ実行を許可
    local current_dir
    current_dir=$(basename "$PWD")
    if [[ "$current_dir" != "init" ]]; then
        die "このスクリプトは init フォルダから実行してください。
実行方法:
  mkdir -p ~/home/{github-owner}/{company}/init
  cd ~/home/{github-owner}/{company}/init
  ~/sf-tools/sf-init.sh"
    fi

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
    if ! run gh auth status; then
        log "WARNING" "GitHub CLI が未認証です。ログインします..."
        run gh auth login || die "GitHub 認証に失敗しました。"
    fi

    check_authorized_user

    log "SUCCESS" "環境チェック完了。"
    return $RET_OK
}

# 【INFO】プロジェクト情報の確認（フォルダ構成から OWNER とプロジェクト名を自動導出）
phase_load_project_info() {
    log "INFO" "プロジェクト情報を確認中..."

    # init の 1つ上 = {company}、2つ上 = {github-owner}
    PROJECT_NAME=$(basename "$(dirname "$PWD")")
    GITHUB_OWNER=$(basename "$(dirname "$(dirname "$PWD")")")
    REPO_NAME="force-${PROJECT_NAME}"
    REPO_FULL_NAME="${GITHUB_OWNER}/${REPO_NAME}"
    REPO_DIR="$(pwd)/${REPO_NAME}"

    # GitHub オーナー名バリデーション（英数字・ハイフンのみ・先頭末尾はハイフン不可）
    if [[ -z "$GITHUB_OWNER" ]] || \
       [[ ! "$GITHUB_OWNER" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$ ]]; then
        die "GitHub オーナー名が無効です: \"${GITHUB_OWNER}\"
  2つ上のフォルダ名を GitHub ユーザー名として使用します。
  正しいフォルダ構成で実行してください:
    ~/home/{github-owner}/{company}/init/"
    fi

    log "INFO" "  GitHub オーナー（フォルダ自動取得）: ${GITHUB_OWNER}"
    log "INFO" "  リポジトリ名（自動導出）: ${REPO_NAME}"

    # --- 確認表示 ---
    echo ""
    echo "  --------------------------------------------------"
    echo "  リポジトリ : ${REPO_FULL_NAME}"
    echo "  クローン先 : ${REPO_DIR}"
    echo "  --------------------------------------------------"
    echo ""
    ask_yn "▶ よろしいですか？" || die "セットアップを中断しました。"

    return $RET_OK
}

# 【CREATE】GitHub リポジトリの作成とクローン
phase_create_repository() {
    # --- リポジトリ作成（冪等: すでに存在する場合はスキップ） ---
    if run gh repo view "$REPO_FULL_NAME" --json name 2>/dev/null; then
        log "WARNING" "リポジトリはすでに存在します。作成をスキップします: ${REPO_FULL_NAME}"
    else
        log "INFO" "GitHub リポジトリを作成中..."
        # tama-create 配下はテスト用リポジトリのため Public で作成（Ruleset 利用可）
        # その他の組織・ユーザーは Private で作成
        local visibility_opt="--private"
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
        local clone_base
        clone_base="$(dirname "$REPO_DIR")"
        mkdir -p "$clone_base" || die "クローン先ディレクトリを作成できません: $clone_base"
        run git clone "https://github.com/${REPO_FULL_NAME}.git" "$REPO_DIR" \
            || die "クローンに失敗しました。"
        log "SUCCESS" "リポジトリをクローンしました: ${REPO_DIR}"
    fi

    return $RET_OK
}


# 【INSTALL】sf-install.sh でファイル生成・フック設定
phase_generate_files() {
    log "INFO" "sf-tools の初期設定ファイルを生成中..."

    cd "$REPO_DIR" || die "ディレクトリに移動できません: $REPO_DIR"

    run bash "$SCRIPT_DIR/sf-install.sh" \
        || die "sf-install.sh の実行に失敗しました。"

    log "SUCCESS" "設定ファイルの生成完了。"
    return $RET_OK
}

# 【BRANCH】sf-branch.sh でブランチ構成を選択・作成
phase_setup_branches() {
    log "INFO" "ブランチ構成を選択してください。"

    cd "$REPO_DIR" || die "ディレクトリに移動できません: $REPO_DIR"

    # sf-branch.sh はインタラクティブなメニューを持つため run ではなく直接実行する
    log "CMD" "[${SCRIPT_NAME}] bash ${SCRIPT_DIR}/sf-branch.sh"
    bash "$SCRIPT_DIR/sf-branch.sh" \
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

# 【SECRETS-SF-PROD】本番組織の Salesforce 認証 URL を登録（ブランチ階層に関わらず必須）
phase_setup_prod_secret() {
    log "HEADER" "GitHub Secrets（Salesforce 認証: 本番）を設定します。"
    register_sf_secret "prod" "SFDX_AUTH_URL_PROD" "本番組織"
    log "SUCCESS" "本番組織の Secret 登録完了。"
    return $RET_OK
}

# 【SECRETS-SF-SANDBOX】ステージング・開発組織の Salesforce 認証 URL を登録（階層に応じて）
phase_setup_sandbox_secrets() {
    # ステージング組織（2階層以上）
    if [[ $BRANCH_COUNT -ge 2 ]]; then
        log "HEADER" "GitHub Secrets（Salesforce 認証: ステージング）を設定します。"
        register_sf_secret "staging" "SFDX_AUTH_URL_STG" "ステージング組織"
        log "SUCCESS" "ステージング組織の Secret 登録完了。"
    fi

    # 開発組織（3階層）
    if [[ $BRANCH_COUNT -ge 3 ]]; then
        log "HEADER" "GitHub Secrets（Salesforce 認証: 開発）を設定します。"
        register_sf_secret "develop" "SFDX_AUTH_URL_DEV" "開発組織"
        log "SUCCESS" "開発組織の Secret 登録完了。"
    fi

    return $RET_OK
}

# 【SECRETS-PAT】GitHub PAT_TOKEN の作成支援と登録
phase_setup_pat_token() {
    log "HEADER" "GitHub Secrets（PAT_TOKEN）を設定します。"
    echo ""
    echo "  ワークフローがブランチ保護をバイパスして push するために必要です。"
    echo ""
    echo "  ブラウザで Personal access tokens (classic) のページを開きます。"
    echo "  【手順】"
    echo "    1. 「Generate new token」→「Generate new token (classic)」をクリック"
    echo "    2. 以下の設定でトークンを作成してください:"
    echo ""
    echo "       Note       : sf-metasync-${PROJECT_NAME}"
    echo "       Expiration : No expiration"
    echo "       Scopes     : ✅ repo（全選択）  ✅ workflow"
    echo ""
    echo "    3. 「Generate token」をクリックしてトークンをコピー"
    echo ""
    open_browser "https://github.com/settings/tokens"
    press_enter "トークンをコピーしたら Enter を押してください..."

    local pat_token=""
    while [[ -z "$pat_token" ]]; do
        read_or_quit pat_token "  生成されたトークンを貼り付けてください（q で中断）: "
        echo ""
    done

    echo "$pat_token" | run gh secret set PAT_TOKEN -R "$REPO_FULL_NAME" \
        || die "PAT_TOKEN の登録に失敗しました。"

    PAT_TOKEN_VALUE="$pat_token"   # 初回 push（workflow スコープ必要）で使用
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
    echo "    1. 「Create New App」→「From scratch」をクリック"
    echo "    2. 以下を設定して「Create App」をクリック:"
    echo "       App Name  : sf-notify-${PROJECT_NAME}"
    echo "       Workspace : 通知先のワークスペースを選択"
    echo "    3. 左メニュー「OAuth & Permissions」をクリック"
    echo "    4. 「ボットトークンのスコープ」→「OAuth スコープを追加する」をクリック"
    echo "       chat:write と入力して追加"
    echo "    5. 左メニュー「Install App」→「Install to <ワークスペース名>」をクリック"
    echo "    6. 「許可する」をクリック"
    echo "    7. 左メニュー「OAuth & Permissions」に戻り「Bot User OAuth Token」（xoxb-...）をコピー"
    echo ""
    open_browser "https://api.slack.com/apps"
    press_enter "Bot Token を取得したら Enter を押してください..."

    local slack_token=""
    while [[ -z "$slack_token" ]]; do
        read_or_quit slack_token "  Bot User OAuth Token を貼り付けてください（q で中断）: "
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
        read_or_quit channel_id "  チャンネル ID（q で中断）: "
    done

    echo "$channel_id" | run gh secret set SLACK_CHANNEL_ID -R "$REPO_FULL_NAME" \
        || die "SLACK_CHANNEL_ID の登録に失敗しました。"
    log "SUCCESS" "SLACK_CHANNEL_ID を登録しました。"

    return $RET_OK
}

# 【COMMIT】初回コミット＆プッシュ（変更がない場合はスキップ）
phase_initial_commit() {
    log "INFO" "初回コミット＆プッシュを実行中..."

    cd "$REPO_DIR" || die "ディレクトリに移動できません: $REPO_DIR"

    run git add -A \
        || die "git add に失敗しました。"

    # ステージングに差分がなければコミット不要
    if git diff --cached --quiet 2>/dev/null; then
        log "INFO" "コミットする変更がありません。スキップします。"
        return $RET_OK
    fi

    log "INFO" "変更ファイル:"
    run git status --short

    run git commit -m "chore: sf-tools 初期セットアップ" \
        || die "git commit に失敗しました。"

    # PAT トークン（workflow スコープ付き）で push
    # gh の OAuth 認証は workflow スコープを持たないため PAT を使用する
    local origin_url
    origin_url=$(git remote get-url origin)
    local pat_url="https://${PAT_TOKEN_VALUE}@github.com/${REPO_FULL_NAME}.git"
    git remote set-url origin "$pat_url"
    run git push --no-verify origin main \
        || { git remote set-url origin "$origin_url"; die "git push に失敗しました。"; }
    git remote set-url origin "$origin_url"

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
log "INFO" "セットアップ中は Ctrl+C が無効です。中断するにはターミナルを閉じてください。"

phase_check_environment      || die "環境チェックに失敗しました。"
log "SUCCESS" "環境チェック完了。"

phase_load_project_info      || die "プロジェクト情報の確認に失敗しました。"

phase_create_repository      || die "リポジトリの作成に失敗しました。"

export SF_INIT_RUNNING=1
phase_generate_files         || die "ファイル生成に失敗しました。"

phase_setup_prod_secret      || die "本番組織 Secret の設定に失敗しました。"

phase_setup_branches         || die "ブランチ構成のセットアップに失敗しました。"

phase_setup_sandbox_secrets  || die "Sandbox Secret の設定に失敗しました。"

phase_setup_pat_token        || die "PAT_TOKEN の設定に失敗しました。"

phase_setup_slack        || die "Slack 連携の設定に失敗しました。"

phase_initial_commit     || die "初回コミットに失敗しました。"

# 初回コミット後に pre-push フックをインストール（main への直接 push をブロックするため先に入れない）
run bash "$SCRIPT_DIR/sf-hook.sh" \
    || die "sf-hook.sh の実行に失敗しました。"

phase_setup_rulesets     || log "WARNING" "Ruleset の設定に失敗しました（無料プランでは利用不可の場合があります。スキップして続行します）。"

echo "-------------------------------------------------------"
# init フォルダごと削除（開発時は別途クローンし直すため）
INIT_DIR="$(dirname "$REPO_DIR")"   # init フォルダのパス
cd "$(dirname "$INIT_DIR")" || true
if [[ -d "$INIT_DIR" ]]; then
    printf "  ▶ init フォルダ（%s）を削除してよいですか？ [Y/N/q]: " "$INIT_DIR"
    answer=""
    read -r answer
    [[ "$answer" == "q" || "$answer" == "Q" ]] && { log "INFO" "削除をスキップしました。手動で削除してください: ${INIT_DIR}"; exit $RET_OK; }
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -rf "$INIT_DIR"
        log "SUCCESS" "init フォルダを削除しました。"
    else
        log "INFO" "削除をスキップしました。手動で削除してください: ${INIT_DIR}"
    fi
fi

log "HEADER" "セットアップが完了しました"

exit $RET_OK
