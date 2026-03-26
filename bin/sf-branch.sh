#!/bin/bash

# ==============================================================================
# sf-branch.sh - ブランチ構成を選択して自動セットアップ
# ==============================================================================
# ブランチ構成パターンを対話式で選択すると、branches.txt を自動更新し、
# 必要なブランチを GitHub に作成します。
# 既に存在するブランチはスキップします。
#
# 【使い方】
#   sf-branch.sh
#
# 【表示例】
#   ブランチ構成を選択してください:
#   ─────────────────────────────────────────────
#   [1] main / staging / develop
#       標準構成。開発→検証→本番の3段階リリース
#
#   [2] main / staging
#       開発組織を使わない場合。検証→本番の2段階
#
#   [3] main
#       小規模プロジェクト・単独開発向け
#   [q] 中断
#   ─────────────────────────────────────────────
#
# 【オプション】
#   -v, --verbose       : コマンドの応答（出力）をコンソールにも表示します
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
COMMON_LIB="${SCRIPT_DIR}/../lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

trap '' INT  # Ctrl+C を無効化（q で中断すること）

# ------------------------------------------------------------------------------
# 3. 事前チェック
# ------------------------------------------------------------------------------
log "HEADER" "ブランチ構成をセットアップします (${SCRIPT_NAME}.sh)"

check_force_dir || die "force-* ディレクトリ内で実行してください。"

OLD_BRANCHES=()

# 既にブランチ構成が設定済みか確認（コメント・空行以外の行があるか）
if [[ -f "$BRANCH_LIST_FILE" ]]; then
    ACTIVE_LINES=$(grep -v '^[[:space:]]*#' "$BRANCH_LIST_FILE" | grep -v '^[[:space:]]*$' | tr -d '\r')
    if [[ -n "$ACTIVE_LINES" ]]; then
        OLD_BRANCHES=($ACTIVE_LINES)
        log "INFO" "現在の構成: $(echo "$ACTIVE_LINES" | tr '\n' ' ')"
        echo "" >&2
        ask_yn "ブランチ構成は設定済みです。変更しますか？" \
            || { log "INFO" "変更せずに終了します。"; exit $RET_OK; }
    fi
fi

# ------------------------------------------------------------------------------
# 4. ブランチ構成の選択
# ------------------------------------------------------------------------------
echo "" >&2
echo -e "  ${CLR_INFO}ブランチ構成を選択してください:${CLR_RESET}" >&2
echo -e "  ${CLR_INFO}─────────────────────────────────────────────${CLR_RESET}" >&2
echo -e "  ${CLR_INFO}[1]${CLR_RESET} main / staging / develop" >&2
echo "      標準構成。開発→検証→本番の3段階リリース" >&2
echo "" >&2
echo -e "  ${CLR_INFO}[2]${CLR_RESET} main / staging" >&2
echo "      開発組織を使わない場合。検証→本番の2段階" >&2
echo "" >&2
echo -e "  ${CLR_INFO}[3]${CLR_RESET} main" >&2
echo "      小規模プロジェクト・単独開発向け" >&2
echo -e "  ${CLR_INFO}─────────────────────────────────────────────${CLR_RESET}" >&2
echo "" >&2
while true; do
    read -rp "  番号を入力 [1-3/q]: " choice || die "入力が中断されました。"  # EOF → 中断
    case "$choice" in
        1) BRANCHES=("main" "staging" "develop"); break ;;
        2) BRANCHES=("main" "staging"); break ;;
        3) BRANCHES=("main"); break ;;
        [Qq]) die "中断しました。" ;;
        "") ;;  # 空 Enter → 無視
        *) echo "  1〜3 または q を入力してください。" >&2 ;;
    esac
done

# ------------------------------------------------------------------------------
# 5. branches.txt を更新
# ------------------------------------------------------------------------------
log "INFO" "branches.txt を更新します..."
run mkdir -p "sf-tools/config"

# コメントヘッダーを保持し、ブランチ行だけ差し替える
{
    # 既存ファイルのコメント行（# で始まる行）を残す
    if [[ -f "$BRANCH_LIST_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            [[ "$line" =~ ^[[:space:]]*# ]] && echo "$line"
        done < "$BRANCH_LIST_FILE"
    fi
    # コメント末尾から1行空けてブランチ名を記載
    echo ""
    for b in "${BRANCHES[@]}"; do
        echo "$b"
    done
} > "${BRANCH_LIST_FILE}.tmp"
run mv "${BRANCH_LIST_FILE}.tmp" "$BRANCH_LIST_FILE"

log "SUCCESS" "branches.txt を更新しました: ${BRANCHES[*]}"

# ------------------------------------------------------------------------------
# 6. main 以外のブランチを作成
# ------------------------------------------------------------------------------
CREATED=0
SKIPPED=0

for branch in "${BRANCHES[@]}"; do
    [[ "$branch" == "main" ]] && continue

    # リモートに既に存在するか確認
    if git ls-remote --exit-code --heads origin "$branch" > /dev/null 2>&1; then
        log "INFO" "${branch} — スキップ（既に存在）"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    run git checkout -B "$branch" || die "${branch} ブランチの作成に失敗しました。"
    run git push --no-verify -u origin "$branch" || die "${branch} ブランチのプッシュに失敗しました。"
    log "SUCCESS" "${branch} ブランチを作成しました。"
    CREATED=$((CREATED + 1))
done

# main に戻る
run git checkout main || die "main ブランチへの切り替えに失敗しました。"

# ------------------------------------------------------------------------------
# 7. 結果表示
# ------------------------------------------------------------------------------
echo "" >&2
log "SUCCESS" "完了（作成: ${CREATED} / スキップ: ${SKIPPED}）"

# 構成変更時は変更前後を表示
if [[ ${#OLD_BRANCHES[@]} -gt 0 ]]; then
    HAS_REMOVED=false
    for old in "${OLD_BRANCHES[@]}"; do
        found=false
        for new in "${BRANCHES[@]}"; do
            [[ "$old" == "$new" ]] && found=true && break
        done
        [[ "$found" == false ]] && HAS_REMOVED=true && break
    done
    if [[ "$HAS_REMOVED" == true ]]; then
        echo "" >&2
        echo -e "  ${CLR_INFO}変更前:${CLR_RESET} ${OLD_BRANCHES[*]}" >&2
        echo -e "  ${CLR_INFO}変更後:${CLR_RESET} ${BRANCHES[*]}" >&2
        echo "" >&2
        log "WARNING" "不要になったブランチがあれば GitHub で手動削除してください。"
    fi
fi
