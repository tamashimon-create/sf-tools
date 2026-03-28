#!/bin/bash
# ==============================================================================
# init-common.sh - sf-init.sh 専用ヘルパー関数ライブラリ
# ==============================================================================
# sf-init.sh の各フェーズスクリプトが source して使用する共通ヘルパー関数集。
# このファイルは lib/common.sh の source 後に読み込むこと。
#
# 【提供する関数】
#   open_browser URL          ... OS を判定してブラウザを開く（lib/common.sh に同名関数あり）
#   register_sf_secret        ... SF認証URL取得と GitHub Secret 登録
#
# 【lib/common.sh から利用可能な関数】
#   press_enter [MSG]         ... Enter 待ち（q で中断）
#   read_or_quit VAR PROMPT   ... 入力受付（q で中断）
# ==============================================================================

# ------------------------------------------------------------------------------
# ブラウザを開く（OS 判定）- lib/common.sh で定義済みなら再定義しない
# ------------------------------------------------------------------------------
if ! declare -f open_browser &>/dev/null; then
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
fi

# ------------------------------------------------------------------------------
# Salesforce 認証 URL を取得して GitHub Secret に登録する
# 引数:
#   $1 - org_alias          : Salesforce 組織エイリアス（例: prod, staging, develop）
#   $2 - secret_name        : GitHub Secret 名（例: SFDX_AUTH_URL_PROD）
#   $3 - label              : 表示用ラベル（例: 本番組織）
#   $4 - is_sandbox_override: "Y"/"N" で対話をスキップ（省略時は対話で確認）
# 備考:
#   sf org login web は MINGW64 等の環境で exit code が信頼できないため直接実行する。
#   成否は続く sf org display の auth_url 取得で判定する（exit code は無視）。
# ------------------------------------------------------------------------------
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

    # ログイン前に既存エイリアスをクリアする。
    # これにより、ログイン失敗・中断時でも古い credentials が sf org display に残らず、
    # 後続の auth_url チェックで確実に失敗を検出できる。
    log "CMD" "[${SCRIPT_NAME}] sf org logout --target-org ${org_alias} --no-prompt"
    sf org logout --target-org "$org_alias" --no-prompt 2>/dev/null || true

    # sf org login web は exit code が信頼できないため直接実行する（run を使わない）。
    # 成否は続く sf org display の auth_url 取得で判定する。
    log "CMD" "[${SCRIPT_NAME}] sf org login web ${login_opts}"
    # shellcheck disable=SC2086
    sf org login web $login_opts || true

    log "INFO" "認証 URL を取得中..."
    local sf_json auth_url
    # run 不使用: 出力に sfdxAuthUrl を含むためログへの記録を避ける
    sf_json=$(sf org display --verbose --json --target-org "$org_alias" 2>/dev/null)
    auth_url=$(echo "$sf_json" \
        | grep '"sfdxAuthUrl"' \
        | sed 's/.*"sfdxAuthUrl": *"\([^"]*\)".*/\1/')

    [[ -z "$auth_url" ]] && die "${label}の認証 URL を取得できませんでした。\n  sf org display の出力を確認してください。"

    echo "$auth_url" | run gh secret set "$secret_name" -R "$REPO_FULL_NAME" \
        || die "${secret_name} の登録に失敗しました。"

    log "SUCCESS" "${secret_name} を登録しました。"
}
