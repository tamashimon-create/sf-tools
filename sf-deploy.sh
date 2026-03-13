#!/bin/bash

# ==============================================================================
# sf-deploy.sh - 本番リリース実行スクリプト（sf-release.sh のラッパー）
# ==============================================================================
# sf-release.sh を --release オプション付きで呼び出します。
# 追加オプションはそのまま sf-release.sh へ引き渡されます。
#
# 【固定オプション】
#   --release           : 本番リリースモードで実行（dry-run しない）
#   --force             : コンフリクト検知を無効化し、変更なしスキップも回避する
#
# 【追加オプション（sf-release.sh に転送）】
#   -n, --no-open       : ブラウザを開かずに実行します
#   -j, --json          : sf コマンドの出力を JSON 形式にします
#   -t, --target ALIAS  : 接続先組織のエイリアスを明示的に指定します
# ==============================================================================

CLR_INFO='\033[36m'; CLR_RESET='\033[0m'
echo "-------------------------------------------------------" >&2
echo -e "${CLR_INFO}>> 強制デプロイを開始します (sf-deploy.sh)${CLR_RESET}" >&2
echo "-------------------------------------------------------" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_SH="${SCRIPT_DIR}/sf-release.sh"

if [[ ! -f "$RELEASE_SH" ]]; then
    CLR_ERR='\033[31m'; CLR_RESET='\033[0m'
    echo -e "${CLR_ERR}-------------------------------------------------------${CLR_RESET}" >&2
    echo -e "${CLR_ERR}  FATAL ERROR: sf-deploy.sh${CLR_RESET}" >&2
    echo -e "${CLR_ERR}-------------------------------------------------------${CLR_RESET}" >&2
    echo -e "${CLR_ERR}  スクリプトが見つかりません: ${RELEASE_SH}${CLR_RESET}" >&2
    echo -e "${CLR_ERR}-------------------------------------------------------${CLR_RESET}" >&2
    exit 1
fi

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "staging" || "$CURRENT_BRANCH" == "development" ]]; then
    CLR_ERR='\033[31m'; CLR_RESET='\033[0m'
    echo -e "${CLR_ERR}-------------------------------------------------------${CLR_RESET}" >&2
    echo -e "${CLR_ERR}  実行禁止: sf-deploy.sh${CLR_RESET}" >&2
    echo -e "${CLR_ERR}-------------------------------------------------------${CLR_RESET}" >&2
    echo -e "${CLR_ERR}  main / staging / development ブランチでは実行できません。${CLR_RESET}" >&2
    echo -e "${CLR_ERR}  現在のブランチ: ${CURRENT_BRANCH}${CLR_RESET}" >&2
    echo -e "${CLR_ERR}-------------------------------------------------------${CLR_RESET}" >&2
    exit 1
fi

exec bash "$RELEASE_SH" --release --force "$@"
