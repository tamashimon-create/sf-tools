#!/bin/bash

# ==============================================================================
# sf-next.sh - 次のPR先ブランチを確認するスクリプト
# ==============================================================================
# 現在のブランチがブランチ階層のどこまでマージ済みかを確認し、
# 次にPRを出すべきブランチを表示します。
#
# 【使い方】
#   bash ~/sf-tools/sf-next.sh
#
# 【表示例（main/staging/develop 構成で develop のみマージ済み）】
#   ┌─────────────────────────────────────┐
#   │  test のマージ状況                  │
#   ├─────────────────────────────────────┤
#   │  ✔ develop   マージ済み             │
#   │  ▶ staging   次のPR先               │
#   │  ✘ main                             │
#   └─────────────────────────────────────┘
#   staging にPRを出しますか？ [Y/N]:
#
# 【判定方法】
#   git merge-base --is-ancestor で、現在のブランチの HEAD が
#   各ターゲットブランチに含まれているかを判定します。
#
# 【前提条件】
#   - force-* ディレクトリ内で実行すること
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
# 3. ブランチ階層の取得
# ------------------------------------------------------------------------------
log "HEADER" "次のPR先を確認します (${SCRIPT_NAME}.sh)"

CURRENT_BRANCH=$(run git symbolic-ref --short HEAD) \
    || die "現在のブランチを取得できません。"

# 保護ブランチ（main/staging/develop）からは実行不可
if is_protected_branch "$CURRENT_BRANCH"; then
    die "${CURRENT_BRANCH} は保護ブランチです。feature ブランチから実行してください。"
fi

BRANCH_LIST=$(get_branch_list) || die "ブランチ構成を取得できません。"

# branches.txt の順序（main → staging → develop）を逆順にしてマージ順にする
# マージ順: develop → staging → main
MERGE_ORDER=()
while IFS= read -r b; do
    MERGE_ORDER+=("$b")
done <<< "$BRANCH_LIST"

# 逆順に並べ替え
REVERSED=()
for ((i=${#MERGE_ORDER[@]}-1; i>=0; i--)); do
    REVERSED+=("${MERGE_ORDER[$i]}")
done

# ------------------------------------------------------------------------------
# 4. リモートの最新状態を取得
# ------------------------------------------------------------------------------
log "INFO" "リモートの最新状態を取得中..."
run git fetch origin "${REVERSED[@]}" 2>/dev/null \
    || die "リモートブランチの取得に失敗しました。"

# ------------------------------------------------------------------------------
# 5. 各ブランチへのマージ状況を確認（Git 到達可能性で判定）
# ------------------------------------------------------------------------------
NEXT_TARGET=""
STATUSES=()

for target in "${REVERSED[@]}"; do
    if git merge-base --is-ancestor HEAD "origin/$target" 2>/dev/null; then
        STATUSES+=("merged")
    else
        STATUSES+=("none")
        [[ -z "$NEXT_TARGET" ]] && NEXT_TARGET="$target"
    fi
done

# ------------------------------------------------------------------------------
# 6. ブランチ名の最大幅を計算（表示の桁揃え用）
# ------------------------------------------------------------------------------
MAX_LEN=0
for target in "${REVERSED[@]}"; do
    (( ${#target} > MAX_LEN )) && MAX_LEN=${#target}
done

# スペースを生成するヘルパー
pad() {
    local len="$1" s=""
    for ((n=0; n<len; n++)); do s+=" "; done
    echo "$s"
}

# ------------------------------------------------------------------------------
# 7. 結果表示
# ------------------------------------------------------------------------------
echo "" >&2
echo -e "  ${CLR_INFO}${CURRENT_BRANCH} のマージ状況${CLR_RESET}" >&2
echo -e "  ${CLR_INFO}────────────────────────────${CLR_RESET}" >&2

for idx in "${!REVERSED[@]}"; do
    target="${REVERSED[$idx]}"
    status="${STATUSES[$idx]}"
    name_pad=$(pad $(( MAX_LEN - ${#target} )))

    case "$status" in
        merged)
            echo -e "    ${CLR_SUCCESS}✓ ${target}${name_pad}   マージ済み${CLR_RESET}" >&2
            ;;
        none)
            if [[ "$target" == "$NEXT_TARGET" ]]; then
                echo -e "    ${CLR_WARNING}▶ ${target}${name_pad}   次のPR先${CLR_RESET}" >&2
            else
                echo -e "    ${CLR_ERR}✗ ${target}${CLR_RESET}" >&2
            fi
            ;;
    esac
done

echo "" >&2

# ------------------------------------------------------------------------------
# 8. PR 作成の確認
# ------------------------------------------------------------------------------
if [[ -z "$NEXT_TARGET" ]]; then
    log "SUCCESS" "全ブランチへのマージが完了しています！"
    exit $RET_OK
fi

echo -ne "  ${NEXT_TARGET} にPRを出しますか？ [Y/N]: " >&2
read -r answer
case "$answer" in
    [Yy]|[Yy][Ee][Ss])
        # リモートリポジトリ情報を取得
        REPO_URL=$(git remote get-url origin 2>/dev/null \
            | sed 's|git@github\.com:|https://github.com/|; s|\.git$||')
        PR_URL="${REPO_URL}/compare/${NEXT_TARGET}...${CURRENT_BRANCH}?expand=1"
        log "INFO" "ブラウザでPR作成画面を開きます..."
        run start "$PR_URL" 2>/dev/null \
            || run open "$PR_URL" 2>/dev/null \
            || run xdg-open "$PR_URL" 2>/dev/null \
            || { log "WARNING" "ブラウザを開けません。以下のURLを手動で開いてください:"; echo "  $PR_URL" >&2; }
        ;;
    *)
        log "INFO" "PR 作成をスキップしました。"
        ;;
esac
