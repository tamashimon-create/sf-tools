#!/bin/bash

# ==============================================================================
# sf-deploy.sh - 本番リリース実行スクリプト（sf-release.sh のラッパー）
# ==============================================================================
# sf-release.sh を --release オプション付きで呼び出します。
# 追加オプションはそのまま sf-release.sh へ引き渡されます。
#
# 【固定オプション】
#   --release           : 本番リリースモードで実行（dry-run しない）
#
# 【追加オプション（sf-release.sh に転送）】
#   -n, --no-open       : ブラウザを開かずに実行します
#   -t, --target ALIAS  : 接続先組織のエイリアスを明示的に指定します
#   -v, --verbose       : コマンドの応答（出力）をコンソールにも表示します
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./sf-tools/logs/${SCRIPT_NAME}.log"
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
# 3. 初期チェック
# ------------------------------------------------------------------------------
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "強制デプロイを開始します (${SCRIPT_NAME}.sh)"

RELEASE_SH="${SCRIPT_DIR}/sf-release.sh"
[[ -f "$RELEASE_SH" ]] || die "スクリプトが見つかりません: ${RELEASE_SH}"

CURRENT_BRANCH=$(run git symbolic-ref --short HEAD)
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "staging" || "$CURRENT_BRANCH" == "development" ]]; then
    die "main / staging / development ブランチでは実行できません。現在のブランチ: ${CURRENT_BRANCH}"
fi

# ------------------------------------------------------------------------------
# 4. sf-release.sh を本番リリースモードで呼び出す
# ------------------------------------------------------------------------------
exec bash "$RELEASE_SH" --release "$@"
