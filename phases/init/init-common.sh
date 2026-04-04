#!/bin/bash
# ==============================================================================
# init-common.sh - sf-init.sh 専用ヘルパー関数ライブラリ
# ==============================================================================
# sf-init.sh の各フェーズスクリプトが source して使用する共通ヘルパー関数集。
# このファイルは lib/common.sh の source 後に読み込むこと。
#
# 【提供する関数】
#   open_browser URL          ... OS を判定してブラウザを開く（lib/common.sh に同名関数あり）
#   generate_jwt_cert         ... JWT 用秘密鍵・証明書を openssl で生成する
#   register_jwt_secret       ... JWT 認証情報を取得・テストして GitHub Secret に登録する
#                                 テスト失敗時はスキップして続行するか確認する（DE 組織対応）
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
# JWT 用秘密鍵・証明書を openssl で生成する
# 引数:
#   $1 - jwt_dir  : 保存先ディレクトリ（例: ~/.sf-jwt/force-test）
#   $2 - repo_name: リポジトリ名（証明書の CN に使用）
# 出力:
#   $jwt_dir/server.key（秘密鍵）
#   $jwt_dir/server.crt（公開鍵証明書）
# ------------------------------------------------------------------------------
generate_jwt_cert() {
    local jwt_dir="$1"
    local repo_name="$2"

    mkdir -p "$jwt_dir"
    chmod 700 "$jwt_dir" 2>/dev/null || true  # run 不使用: ファイル権限保護（Windows は効果なし）

    # 既存の証明書があればスキップ（--resume 時の再生成による Salesforce との不一致を防ぐ）
    if [[ -f "${jwt_dir}/server.key" && -f "${jwt_dir}/server.crt" ]]; then
        log "INFO" "既存の証明書を使用します（スキップ）: ${jwt_dir}/"
        log "INFO" "  秘密鍵: ${jwt_dir}/server.key"
        log "INFO" "  証明書: ${jwt_dir}/server.crt"
        return 0
    fi

    log "INFO" "JWT 用証明書を生成中: ${jwt_dir}/"
    # run 不使用: 変数代入・openssl の終了コードを直接確認するため
    # OpenSSL 3.x は genrsa が PKCS#8 を出力するため、-traditional で PKCS#1(RSA) に変換する
    # Salesforce JWT Bearer Flow は PKCS#1 形式（-----BEGIN RSA PRIVATE KEY-----）を要求する
    openssl genrsa -out "${jwt_dir}/server.key.tmp" 2048 2>/dev/null \
        || die "秘密鍵の生成に失敗しました。openssl がインストールされているか確認してください。"
    # -traditional: OpenSSL 3.x で PKCS#1 形式を強制。1.x では不要なためフォールバック
    if openssl rsa -traditional -in "${jwt_dir}/server.key.tmp" \
                                -out "${jwt_dir}/server.key" 2>/dev/null; then
        rm -f "${jwt_dir}/server.key.tmp"
    else
        # OpenSSL 1.x は genrsa が元から PKCS#1 を出力するため tmp をそのまま使用
        mv "${jwt_dir}/server.key.tmp" "${jwt_dir}/server.key"
    fi
    # // プレフィックス: Git Bash が -subj の /CN= を Windows パスに変換するのを防ぐ定番の回避策
    openssl req -new -x509 -days 3650 \
        -key "${jwt_dir}/server.key" \
        -out "${jwt_dir}/server.crt" \
        -subj "//CN=sf-jwt-${repo_name}" \
        || die "証明書の生成に失敗しました。"

    chmod 600 "${jwt_dir}/server.key" 2>/dev/null || true  # run 不使用: 秘密鍵の権限保護

    log "SUCCESS" "証明書を生成しました。"
    log "INFO"    "  秘密鍵: ${jwt_dir}/server.key"
    log "INFO"    "  証明書: ${jwt_dir}/server.crt"
}

# ------------------------------------------------------------------------------
# JWT 認証情報を取得・テストして GitHub Secret に登録する
# 引数:
#   $1 - org_alias        : Salesforce 組織エイリアス（例: prod, staging, develop）
#   $2 - suffix           : Secret 名のサフィックス（例: PROD, STG, DEV）
#   $3 - label            : 表示用ラベル（例: 本番組織）
#   $4 - key_file         : 秘密鍵ファイルパス
#   $5 - is_sandbox_override: "Y"/"N" で対話をスキップ（省略時は対話で確認）
# 登録する Secrets / Variables:
#   SF_CONSUMER_KEY_<suffix>  （Secret）
#   SF_USERNAME_<suffix>      （Variable）
#   SF_INSTANCE_URL_<suffix>  （Variable）
# ------------------------------------------------------------------------------
register_jwt_secret() {
    local org_alias="$1"
    local suffix="$2"
    local label="$3"
    local key_file="$4"
    local is_sandbox_override="${5:-}"  # 省略時は対話で確認

    log "HEADER" "${label}（SF_*_${suffix}）の設定"

    # Sandbox か確認して接続 URL を決定
    local instance_url="https://login.salesforce.com"
    local is_sandbox_input
    if [[ -n "$is_sandbox_override" ]]; then
        is_sandbox_input="$is_sandbox_override"
    else
        ask_yn "  ${label}は Sandbox ですか？" && is_sandbox_input="Y" || is_sandbox_input="N"
    fi
    if [[ "$is_sandbox_input" =~ ^[Yy] ]]; then
        instance_url="https://test.salesforce.com"
    fi
    log "INFO" "  接続 URL: ${instance_url}"

    # コンシューマーキーを入力
    local consumer_key
    read_or_quit consumer_key "  コンシューマーキーを入力してください："

    # 接続ユーザー名を入力
    local username
    read_or_quit username "  接続ユーザー名を入力してください（例: admin@example.com）："

    # JWT 接続テスト
    log "INFO" "  JWT 接続テストを実行中..."
    log "INFO" "  [jwt cmd] sf org login jwt --client-id ***masked*** --jwt-key-file ${key_file} --username ${username} --instance-url ${instance_url} --alias ${org_alias}"
    # run 不使用: sf org login jwt は exit code が信頼できない場合があるため直接実行して確認
    # VAR=$(cmd) 形式のため run 不使用（stderr をキャプチャしてログに残す）
    local jwt_err
    jwt_err=$(sf org login jwt \
        --client-id    "$consumer_key" \
        --jwt-key-file "$key_file" \
        --username     "$username" \
        --instance-url "$instance_url" \
        --alias        "$org_alias" 2>&1)
    local jwt_exit=$?
    # sf org login jwt は成功時でも非0終了コードを返す場合がある（stderr に成功メッセージを出力）
    # そのため終了コードが非0でも "Successfully authorized" が含まれていれば成功とみなす
    if [[ $jwt_exit -ne 0 ]] && ! echo "$jwt_err" | grep -q "Successfully authorized"; then
        log "ERROR" "  [jwt error] ${jwt_err}"
        log "WARNING" "  JWT 接続テストに失敗しました。以下を確認してください:"
        log "WARNING" "  ・コンシューマーキーが正しいか（コピーミスに注意）"
        log "WARNING" "  ・ユーザー名が正しいか"
        log "WARNING" "  ・「指名ユーザーの JWT ベースアクセストークンを発行」にチェックが入っているか"
        log "WARNING" "  ・プロファイルに接続ユーザーが割り当てられているか"
        log "WARNING" "  ・Connected App 保存後 2〜10 分経過しているか（反映待ち）"
        log "WARNING" "  ・Trailhead Playground / orgfarm-* 系は JWT Bearer Flow 非対応のため使用不可"
        log "WARNING" "  ・Developer Edition 組織では認証反映が遅延・失敗する場合があります"
        # テスト失敗時はスキップして続行するか確認する
        # （DE 組織などローカルで認証できない場合でも GitHub Secrets への登録だけ済ませて
        #   GitHub Actions で動作確認できるようにするため）
        if ask_yn "  接続テストをスキップして GitHub Secrets への登録のみ行いますか？（GitHub Actions で後でテストできます）"; then
            log "WARNING" "  接続テストをスキップします。GitHub Actions で動作を確認してください。"
        else
            die "  JWT 接続テストに失敗しました。設定を見直してから再実行してください。"
        fi
    else
        log "SUCCESS" "  JWT 接続テスト成功。"
    fi

    # GitHub Secrets / Variables に登録
    # SF_CONSUMER_KEY は機密情報のため Secret、SF_USERNAME と SF_INSTANCE_URL は Variable（平文で管理）
    run gh secret   set      "SF_CONSUMER_KEY_${suffix}" --body "$consumer_key" -R "$REPO_FULL_NAME" \
        || die "SF_CONSUMER_KEY_${suffix} の登録に失敗しました。"
    run gh variable set      "SF_USERNAME_${suffix}"     --body "$username"     -R "$REPO_FULL_NAME" \
        || die "SF_USERNAME_${suffix} の登録に失敗しました。"
    run gh variable set      "SF_INSTANCE_URL_${suffix}" --body "$instance_url" -R "$REPO_FULL_NAME" \
        || die "SF_INSTANCE_URL_${suffix} の登録に失敗しました。"

    log "SUCCESS" "  SF_CONSUMER_KEY_${suffix}（Secret）/ SF_USERNAME_${suffix}（Variable）/ SF_INSTANCE_URL_${suffix}（Variable）を登録しました。"
}
