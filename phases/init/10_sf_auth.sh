#!/bin/bash
# ==============================================================================
# 10_sf_auth.sh - Phase 10: JWT 認証情報の設定
# ==============================================================================
# JWT（OAuth 2.0 JWT Bearer Flow）方式で Salesforce 組織への認証情報を
# GitHub Secrets に登録する。
#
# 【処理フロー】
#   1. openssl で秘密鍵・証明書を生成（~/.sf-jwt/<REPO_NAME>/）
#   2. Connected App 設定手順を案内（証明書をアップロードするまで待機）
#   3. 秘密鍵を SF_PRIVATE_KEY として GitHub Secrets に登録
#   4. 組織ごとにコンシューマーキー・ユーザー名を入力して JWT 接続テスト
#   5. SF_CONSUMER_KEY_xxx / SF_USERNAME_xxx / SF_INSTANCE_URL_xxx を登録
#
# 【登録する GitHub Secrets】
#   SF_PRIVATE_KEY              （全組織共通・秘密鍵 PEM）
#   SF_CONSUMER_KEY_PROD / _STG / _DEV
#   SF_USERNAME_PROD     / _STG / _DEV
#   SF_INSTANCE_URL_PROD / _STG / _DEV
#
# 【備考】
#   秘密鍵は ~/.sf-jwt/<REPO_NAME>/server.key に保存される。
#   証明書（server.crt）は各組織の Connected App にアップロードが必要。
#   BRANCH_COUNT は Phase 5 で .sf-init.env に書き出される。
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
[[ -z "$REPO_NAME" ]]      && die "REPO_NAME が未設定です。Phase 2 が完了しているか確認してください。"
BRANCH_COUNT="${BRANCH_COUNT:-1}"

# JWT 証明書の保存先
JWT_DIR="$HOME/.sf-jwt/${REPO_NAME}"

# ------------------------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------------------------
log "HEADER" "Phase 6: JWT 認証情報の設定"

# --------------------------------------------------------------------------
# Step 1: 証明書の生成
# --------------------------------------------------------------------------
log "HEADER" "Phase 6-1: JWT 用証明書を生成します。"

if [[ -f "${JWT_DIR}/server.key" && -f "${JWT_DIR}/server.crt" ]]; then
    log "INFO" "既存の証明書が見つかりました: ${JWT_DIR}/"
    ask_yn "  既存の証明書を再利用しますか？（N を選ぶと再生成します）" \
        && log "INFO" "  既存の証明書を使用します。" \
        || generate_jwt_cert "$JWT_DIR" "$REPO_NAME"
else
    generate_jwt_cert "$JWT_DIR" "$REPO_NAME"
fi

# --------------------------------------------------------------------------
# Step 2: Connected App 設定案内
# --------------------------------------------------------------------------
log "HEADER" "Phase 6-2: Salesforce Connected App を設定してください。"
log "INFO" ""
log "INFO" "  ▼ 以下の証明書（公開鍵）を各組織の Connected App にアップロードしてください。"
log "INFO" "  ─────────────────────────────────────────────────"
# run 不使用: cat の出力をそのまま画面に表示するため
cat "${JWT_DIR}/server.crt" >&2
log "INFO" "  ─────────────────────────────────────────────────"
log "INFO" ""
log "INFO" "  【Connected App 作成手順（組織ごとに実施）】"
log "INFO" "  1. Salesforce 管理画面 → 設定 → アプリケーション → 接続アプリケーション"
log "INFO" "  2. 「新規接続アプリケーション」をクリック"
log "INFO" "  3. OAuth 設定を有効化 → コールバック URL に dummy://callback を入力"
log "INFO" "  4. 「デジタル署名を使用」にチェック → 上記の server.crt をアップロード"
log "INFO" "  5. OAuth スコープに「フルアクセス(full)」または必要なスコープを追加"
log "INFO" "  6. 保存後、「コンシューマーキーとシークレット」でキーをコピー"
log "INFO" "  7. プロファイル/権限セットに接続ユーザーを追加して「接続アプリケーションを管理」"
log "INFO" "  8. 「事前に許可済みユーザーに制限」に設定"
log "INFO" ""
press_enter "設定が完了したら Enter を押してください（q で中断）"

# --------------------------------------------------------------------------
# Step 3: SF_PRIVATE_KEY を GitHub Secrets に登録
# --------------------------------------------------------------------------
log "HEADER" "Phase 6-3: SF_PRIVATE_KEY を GitHub Secrets に登録します。"
# run 不使用: 秘密鍵の内容をログに記録しないため直接実行
gh secret set "SF_PRIVATE_KEY" < "${JWT_DIR}/server.key" -R "$REPO_FULL_NAME" \
    || die "SF_PRIVATE_KEY の登録に失敗しました。"
log "SUCCESS" "SF_PRIVATE_KEY を登録しました。"

# --------------------------------------------------------------------------
# Step 4: 組織ごとの JWT 設定
# --------------------------------------------------------------------------
log "HEADER" "Phase 6-4: 各組織の JWT 認証情報を設定します。"

# 6-4-1. 本番組織（必須）
register_jwt_secret "prod" "PROD" "本番組織" "${JWT_DIR}/server.key" "N"

# 6-4-2. ステージング組織（2 階層以上）
if [[ $BRANCH_COUNT -ge 2 ]]; then
    register_jwt_secret "staging" "STG" "ステージング組織" "${JWT_DIR}/server.key"
fi

# 6-4-3. 開発組織（3 階層）
if [[ $BRANCH_COUNT -ge 3 ]]; then
    register_jwt_secret "develop" "DEV" "開発組織" "${JWT_DIR}/server.key"
fi

log "SUCCESS" "Phase 6 完了: JWT 認証情報の設定 OK。"
exit $RET_OK
