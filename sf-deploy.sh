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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_SH="${SCRIPT_DIR}/sf-release.sh"

if [[ ! -f "$RELEASE_SH" ]]; then
    echo "[FATAL ERROR] スクリプトが見つかりません: $RELEASE_SH" >&2
    exit 1
fi

exec bash "$RELEASE_SH" --release --force "$@"
