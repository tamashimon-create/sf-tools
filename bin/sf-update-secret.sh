#!/bin/bash
# ==============================================================================
# sf-update-secret.sh - GitHub Secrets の JWT 認証情報を更新する
# ==============================================================================
# JWT 認証に使用する GitHub Secrets を対話形式で更新する。
#
# 動作:
#   1. force-* ディレクトリかチェック
#   2. git remote から対象リポジトリを自動取得
#   3. 更新する項目を選択（秘密鍵 / コンシューマーキー / ユーザー名 / すべて）
#   4. 入力値で JWT 接続テストを実施（テスト成功後のみ Secret を更新）
#   5. gh secret set で GitHub Secrets を更新
#
# 【更新対象の GitHub Secrets】
#   SF_PRIVATE_KEY                      （全組織共通）
#   SF_CONSUMER_KEY_PROD / _STG / _DEV  （組織別）
#   SF_USERNAME_PROD     / _STG / _DEV  （組織別）
#   SF_INSTANCE_URL_PROD / _STG / _DEV  （組織別・変更は稀）
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. common.sh 用の事前設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"

# ------------------------------------------------------------------------------
# 2. 共通ライブラリの読み込み
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    awk '/^# ==/{f++; next} f==2{sub(/^# ?/,""); print} f==3{exit}' "${BASH_SOURCE[0]}"
    exit 0
fi
source "$COMMON_LIB"

# ------------------------------------------------------------------------------
# 3. 必須コマンドのチェック
# ------------------------------------------------------------------------------
command -v sf      >/dev/null 2>&1 || die "コマンドが見つかりません: sf"
command -v gh      >/dev/null 2>&1 || die "コマンドが見つかりません: gh"
command -v git     >/dev/null 2>&1 || die "コマンドが見つかりません: git"
command -v openssl >/dev/null 2>&1 || die "コマンドが見つかりません: openssl"

# ------------------------------------------------------------------------------
# 4. force-* ディレクトリかチェック
# ------------------------------------------------------------------------------
check_force_dir

# ------------------------------------------------------------------------------
# 5. git remote からリポジトリ名を取得
# ------------------------------------------------------------------------------
REMOTE_URL=$(git remote get-url origin 2>/dev/null) \
    || die "git remote の取得に失敗しました。Git リポジトリか確認してください。"

REPO_FULL_NAME=$(echo "$REMOTE_URL" \
    | sed 's|.*github\.com[:/]\(.*\)\.git|\1|' \
    | sed 's|.*github\.com[:/]\(.*\)$|\1|')
REPO_NAME=$(basename "$REPO_FULL_NAME")

[[ -z "$REPO_FULL_NAME" ]] && die "リポジトリ名を取得できませんでした。Remote URL: ${REMOTE_URL}"

JWT_DIR="$HOME/.sf-jwt/${REPO_NAME}"

log "HEADER" "GitHub Secrets（JWT 認証情報）を更新します (${SCRIPT_NAME}.sh)"
log "INFO" "リポジトリ: ${REPO_FULL_NAME}"

# ------------------------------------------------------------------------------
# 共通: JWT 接続テスト関数
# 引数: $1=org_alias $2=suffix $3=label $4=consumer_key $5=username
#       $6=instance_url $7=key_file
# ------------------------------------------------------------------------------
_test_jwt_login() {
    local org_alias="$1" suffix="$2" label="$3"
    local consumer_key="$4" username="$5" instance_url="$6" key_file="$7"

    log "INFO" "JWT 接続テスト中: ${label}..."
    # run 不使用: sf org login jwt は exit code が不安定な場合があるため直接確認
    sf org login jwt \
        --client-id    "$consumer_key" \
        --jwt-key-file "$key_file" \
        --username     "$username" \
        --instance-url "$instance_url" \
        --alias        "$org_alias" 2>/dev/null \
        || die "JWT 接続テストに失敗しました（${label}）。\n  Connected App の設定・コンシューマーキー・ユーザー名を確認してください。"
    log "SUCCESS" "JWT 接続テスト成功: ${label}"
}

# ------------------------------------------------------------------------------
# 共通: 組織選択プロンプト → suffix と label を返す（nameref）
# ------------------------------------------------------------------------------
_select_org() {
    local -n _suffix_ref=$1  # Bash 4.3+ nameref
    local -n _label_ref=$2
    local -n _alias_ref=$3

    log "INFO" "対象組織を選択してください:"
    log "INFO" "  1) 本番組織（PROD）"
    log "INFO" "  2) ステージング組織（STG）"
    log "INFO" "  3) 開発組織（DEV）"

    local key
    read_key key "" "[123]"
    case "$key" in
        1) _suffix_ref="PROD"; _label_ref="本番組織";         _alias_ref="prod"    ;;
        2) _suffix_ref="STG";  _label_ref="ステージング組織"; _alias_ref="staging" ;;
        3) _suffix_ref="DEV";  _label_ref="開発組織";         _alias_ref="develop" ;;
    esac
}

# ------------------------------------------------------------------------------
# 更新処理: 秘密鍵（SF_PRIVATE_KEY）
# ------------------------------------------------------------------------------
_update_private_key() {
    log "HEADER" "秘密鍵（SF_PRIVATE_KEY）を更新します"

    local key_file
    read_or_quit key_file "  秘密鍵ファイルのパスを入力してください（例: ~/.sf-jwt/${REPO_NAME}/server.key）："
    # ~ を展開
    key_file="${key_file/#\~/$HOME}"
    [[ -f "$key_file" ]] || die "ファイルが存在しません: ${key_file}"

    ask_yn "  SF_PRIVATE_KEY を更新してよいですか？" || { log "INFO" "スキップしました。"; return; }

    # run 不使用: 秘密鍵の内容をログに記録しないため
    gh secret set "SF_PRIVATE_KEY" < "$key_file" -R "$REPO_FULL_NAME" \
        || die "SF_PRIVATE_KEY の更新に失敗しました。"
    log "SUCCESS" "SF_PRIVATE_KEY を更新しました。"
}

# ------------------------------------------------------------------------------
# 更新処理: コンシューマーキー（SF_CONSUMER_KEY_xxx）
# ------------------------------------------------------------------------------
_update_consumer_key() {
    log "HEADER" "コンシューマーキー（SF_CONSUMER_KEY_xxx）を更新します"

    local suffix label org_alias
    _select_org suffix label org_alias

    # 秘密鍵ファイルの確認（接続テスト用）
    local key_file="${JWT_DIR}/server.key"
    if [[ ! -f "$key_file" ]]; then
        read_or_quit key_file "  秘密鍵ファイルのパスを入力してください："
        key_file="${key_file/#\~/$HOME}"
        [[ -f "$key_file" ]] || die "ファイルが存在しません: ${key_file}"
    fi

    local consumer_key
    read_or_quit consumer_key "  ${label}のコンシューマーキーを入力してください："

    # 現在の username / instance_url を GitHub から取得（テスト用）
    local username instance_url
    # VAR=$(cmd) 形式のため run 不使用
    username=$(gh secret list -R "$REPO_FULL_NAME" 2>/dev/null \
        | grep "SF_USERNAME_${suffix}" | head -1 | awk '{print $1}' || true)
    # GitHub Secrets の値は取得不可のため入力を要求
    read_or_quit username     "  ${label}の接続ユーザー名を入力してください（接続テスト用）："
    read_or_quit instance_url "  接続 URL を入力してください（https://login.salesforce.com または https://test.salesforce.com）："

    _test_jwt_login "$org_alias" "$suffix" "$label" "$consumer_key" "$username" "$instance_url" "$key_file"

    run gh secret set "SF_CONSUMER_KEY_${suffix}" --body "$consumer_key" -R "$REPO_FULL_NAME" \
        || die "SF_CONSUMER_KEY_${suffix} の更新に失敗しました。"
    log "SUCCESS" "SF_CONSUMER_KEY_${suffix} を更新しました。"
}

# ------------------------------------------------------------------------------
# 更新処理: ユーザー名（SF_USERNAME_xxx）
# ------------------------------------------------------------------------------
_update_username() {
    log "HEADER" "ユーザー名（SF_USERNAME_xxx）を更新します"

    local suffix label org_alias
    _select_org suffix label org_alias

    local key_file="${JWT_DIR}/server.key"
    if [[ ! -f "$key_file" ]]; then
        read_or_quit key_file "  秘密鍵ファイルのパスを入力してください："
        key_file="${key_file/#\~/$HOME}"
        [[ -f "$key_file" ]] || die "ファイルが存在しません: ${key_file}"
    fi

    local consumer_key username instance_url
    read_or_quit consumer_key  "  ${label}のコンシューマーキーを入力してください（接続テスト用）："
    read_or_quit username      "  ${label}の新しい接続ユーザー名を入力してください："
    read_or_quit instance_url  "  接続 URL を入力してください（https://login.salesforce.com または https://test.salesforce.com）："

    _test_jwt_login "$org_alias" "$suffix" "$label" "$consumer_key" "$username" "$instance_url" "$key_file"

    run gh secret set "SF_USERNAME_${suffix}" --body "$username" -R "$REPO_FULL_NAME" \
        || die "SF_USERNAME_${suffix} の更新に失敗しました。"
    log "SUCCESS" "SF_USERNAME_${suffix} を更新しました。"
}

# ------------------------------------------------------------------------------
# 更新処理: すべて更新
# ------------------------------------------------------------------------------
_update_all() {
    log "HEADER" "すべての JWT Secrets を更新します"

    # 秘密鍵
    local key_file="${JWT_DIR}/server.key"
    if [[ ! -f "$key_file" ]]; then
        read_or_quit key_file "  秘密鍵ファイルのパスを入力してください："
        key_file="${key_file/#\~/$HOME}"
        [[ -f "$key_file" ]] || die "ファイルが存在しません: ${key_file}"
    fi
    log "INFO" "  秘密鍵: ${key_file}"

    ask_yn "  SF_PRIVATE_KEY を更新しますか？" && {
        # run 不使用: 秘密鍵の内容をログに記録しないため
        gh secret set "SF_PRIVATE_KEY" < "$key_file" -R "$REPO_FULL_NAME" \
            || die "SF_PRIVATE_KEY の更新に失敗しました。"
        log "SUCCESS" "  SF_PRIVATE_KEY を更新しました。"
    }

    # 組織ごとに更新
    local suffixes=("PROD") aliases=("prod") labels=("本番組織")
    local branch_count_file="./sf-tools/config/branches.txt"
    if [[ -f "$branch_count_file" ]]; then
        local bc; bc=$(wc -l < "$branch_count_file" | tr -d ' ')
        [[ $bc -ge 2 ]] && { suffixes+=("STG");  aliases+=("staging"); labels+=("ステージング組織"); }
        [[ $bc -ge 3 ]] && { suffixes+=("DEV");  aliases+=("develop"); labels+=("開発組織"); }
    fi

    local i
    for i in "${!suffixes[@]}"; do
        local suffix="${suffixes[$i]}" org_alias="${aliases[$i]}" label="${labels[$i]}"
        log "HEADER" "  ${label}（${suffix}）の設定"

        local consumer_key username instance_url
        read_or_quit consumer_key  "    コンシューマーキーを入力してください："
        read_or_quit username      "    接続ユーザー名を入力してください："

        instance_url="https://login.salesforce.com"
        if [[ "$suffix" != "PROD" ]]; then
            ask_yn "    Sandbox ですか？" \
                && instance_url="https://test.salesforce.com" \
                || instance_url="https://login.salesforce.com"
        fi

        _test_jwt_login "$org_alias" "$suffix" "$label" "$consumer_key" "$username" "$instance_url" "$key_file"

        run gh secret set "SF_CONSUMER_KEY_${suffix}" --body "$consumer_key" -R "$REPO_FULL_NAME" \
            || die "SF_CONSUMER_KEY_${suffix} の更新に失敗しました。"
        run gh secret set "SF_USERNAME_${suffix}"     --body "$username"     -R "$REPO_FULL_NAME" \
            || die "SF_USERNAME_${suffix} の更新に失敗しました。"
        run gh secret set "SF_INSTANCE_URL_${suffix}" --body "$instance_url" -R "$REPO_FULL_NAME" \
            || die "SF_INSTANCE_URL_${suffix} の更新に失敗しました。"
        log "SUCCESS" "  ${label}の Secrets を更新しました。"
    done
}

# ------------------------------------------------------------------------------
# 6. メインメニュー
# ------------------------------------------------------------------------------
log "INFO" ""
log "INFO" "更新する項目を選択してください:"
log "INFO" "  1) 秘密鍵を更新（SF_PRIVATE_KEY）"
log "INFO" "  2) コンシューマーキーを更新（SF_CONSUMER_KEY_xxx）"
log "INFO" "  3) ユーザー名を更新（SF_USERNAME_xxx）"
log "INFO" "  4) すべて更新"

MENU_KEY=""
read_key MENU_KEY "" "[1234]"

case "$MENU_KEY" in
    1) _update_private_key  ;;
    2) _update_consumer_key ;;
    3) _update_username     ;;
    4) _update_all          ;;
esac

log "SUCCESS" "JWT Secrets の更新が完了しました。"
