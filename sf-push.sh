#!/bin/bash
# ==============================================================================
# sf-push.sh - カレント配下をコミットしてプッシュ
# ==============================================================================
# 現在のディレクトリ配下だけを Git の対象にして、VS Code でコミット
# メッセージを入力してから commit / push を実行する。
#
# 動作:
#   1. 現在のブランチ名を表示
#   2. カレント配下だけを git add --all
#   3. 変更の有無をチェック（なければ終了）
#   4. sf-check.sh でターゲットファイルを検証（エラーなら終了）
#   5. VS Code を別ウィンドウで開いてコミットメッセージを入力
#   6. 入力があれば git commit / git push
#   7. 未入力なら何もせず終了
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
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

# ------------------------------------------------------------------------------
# 3. 必須コマンドのチェック
# ------------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || die $'\u30b3\u30de\u30f3\u30c9\u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093: git'
command -v code >/dev/null 2>&1 || die $'\u30b3\u30de\u30f3\u30c9\u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093: code'

# ------------------------------------------------------------------------------
# 4. リポジトリ情報の取得
# ------------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die $'\u73fe\u5728\u306e\u30c7\u30a3\u30ec\u30af\u30c8\u30ea\u304b\u3089 Git \u30ea\u30dd\u30b8\u30c8\u30ea\u3092\u898b\u3064\u3051\u3089\u308c\u307e\u305b\u3093\u3002'

BRANCH_NAME="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null)" \
    || die $'Git \u306e\u30d6\u30e9\u30f3\u30c1\u540d\u3092\u53d6\u5f97\u3067\u304d\u307e\u305b\u3093\u3002'

REL_PREFIX="$(git rev-parse --show-prefix 2>/dev/null || true)"
if [[ -n "$REL_PREFIX" ]]; then
    TARGET_PATHSPEC="${REL_PREFIX%/}"
else
    TARGET_PATHSPEC="."
fi

# ------------------------------------------------------------------------------
# 5. 開始ログ
# ------------------------------------------------------------------------------
log "HEADER" "$(printf '%b' $'\u30ab\u30ec\u30f3\u30c8\u914d\u4e0b\u306e\u30b3\u30df\u30c3\u30c8\u30fb\u30d7\u30c3\u30b7\u30e5\u3092\u958b\u59cb\u3057\u307e\u3059') (${SCRIPT_NAME}.sh)"
log "INFO" $'\u5bfe\u8c61: '"${BRANCH_NAME}"

# ------------------------------------------------------------------------------
# 6. カレント配下だけをステージング
# ------------------------------------------------------------------------------
git -C "$REPO_ROOT" add --all -- "$TARGET_PATHSPEC" \
    || die $'git add \u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002'

if git -C "$REPO_ROOT" diff --cached --quiet -- "$TARGET_PATHSPEC"; then
    log "WARNING" $'\u73fe\u5728\u306e\u30c7\u30a3\u30ec\u30af\u30c8\u30ea\u914d\u4e0b\u306b\u3001\u30b3\u30df\u30c3\u30c8\u5bfe\u8c61\u306e\u5909\u66f4\u304c\u3042\u308a\u307e\u305b\u3093\u3002'
    exit $RET_OK
fi

# ------------------------------------------------------------------------------
# 7. ターゲットファイルの検証（sf-check.sh）
# ------------------------------------------------------------------------------
log "INFO" $'sf-check.sh \u3067\u30bf\u30fc\u30b2\u30c3\u30c8\u30d5\u30a1\u30a4\u30eb\u3092\u691c\u8a3c\u3057\u307e\u3059\u3002'
run bash "${SCRIPT_DIR}/sf-check.sh" \
    || die $'\u30bf\u30fc\u30b2\u30c3\u30c8\u30d5\u30a1\u30a4\u30eb\u306e\u691c\u8a3c\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002\u30b3\u30df\u30c3\u30c8\u3092\u4e2d\u6b62\u3057\u307e\u3059\u3002'

# ------------------------------------------------------------------------------
# 8. コミットメッセージ入力ファイルを作成
# ------------------------------------------------------------------------------
COMMIT_MSG_FILE="$(mktemp "${TMPDIR:-/tmp}/sf-push-commit-msg.XXXXXX.txt")" \
    || die $'\u4e00\u6642\u30d5\u30a1\u30a4\u30eb\u306e\u4f5c\u6210\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002'
trap 'rm -f "$COMMIT_MSG_FILE"' EXIT

printf '%b\n' \
    "# "$'\u0031\u884c\u76ee\u306b\u8981\u7d04\u3092\u66f8\u3044\u3066\u304f\u3060\u3055\u3044\u3002' \
    "# "$'\u4f8b: deploy-target.txt \u3092\u66f4\u65b0' \
    "#" \
    "# "$'\u5fc5\u8981\u306a\u3089\u8a73\u7d30\u3092\u4e0b\u306b\u66f8\u3044\u3066\u304f\u3060\u3055\u3044\u3002' \
    > "$COMMIT_MSG_FILE"

# ------------------------------------------------------------------------------
# 9. VS Code で入力してもらう
# ------------------------------------------------------------------------------
log "INFO" $'VS Code \u3067\u30b3\u30df\u30c3\u30c8\u30e1\u30c3\u30bb\u30fc\u30b8\u5165\u529b\u753b\u9762\u3092\u958b\u304d\u307e\u3059\u3002'
code --new-window --wait "$COMMIT_MSG_FILE" \
    || die $'VS Code \u306e\u8d77\u52d5\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002'

COMMIT_MSG="$(grep -v '^[[:space:]]*#' "$COMMIT_MSG_FILE" | sed '/^[[:space:]]*$/d')"
if [[ -z "$COMMIT_MSG" ]]; then
    log "INFO" $'\u30b3\u30df\u30c3\u30c8\u30e1\u30c3\u30bb\u30fc\u30b8\u304c\u672a\u5165\u529b\u306e\u305f\u3081\u3001\u4f55\u3082\u305b\u305a\u7d42\u4e86\u3057\u307e\u3059\u3002'
    exit $RET_OK
fi

# コメント除去済みのメッセージでファイルを上書き
printf '%s\n' "$COMMIT_MSG" > "$COMMIT_MSG_FILE"

# ------------------------------------------------------------------------------
# 10. commit / push
# ------------------------------------------------------------------------------
log "INFO" $'git commit \u3092\u5b9f\u884c\u3057\u307e\u3059\u3002'
run git -C "$REPO_ROOT" commit -F "$COMMIT_MSG_FILE" \
    || die $'git commit \u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002'

log "INFO" $'git push \u3092\u5b9f\u884c\u3057\u307e\u3059\u3002'
run git -C "$REPO_ROOT" push \
    || die $'git push \u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002'

log "SUCCESS" $'\u30ab\u30ec\u30f3\u30c8\u914d\u4e0b\u306e\u30b3\u30df\u30c3\u30c8\u30fb\u30d7\u30c3\u30b7\u30e5\u304c\u5b8c\u4e86\u3057\u307e\u3057\u305f\u3002'
