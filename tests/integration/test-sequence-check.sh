#!/usr/bin/env bash
# ==============================================================================
# test-sequence-check.sh - シーケンスチェック全パターン統合テスト
# ==============================================================================
# gh CLI を使って全 PR パターンを自動検証する。
# テスト対象のブランチ構成は sf-tools/config/branches.txt から動的に読み込む。
#
# 【テスト対象パターン（3ブランチ構成の場合）】
#   ❌ エラーブロック  : develop→staging / develop→main / staging→main
#   ⚠️  警告のみ（pass）: feature/*→staging（develop未マージ）/ feature/*→main（staging未マージ）
#   ✅ 正常通過        : feature/*→develop / feature/*→staging（develop済）/ feature/*→main（staging済）
#
# 【使用方法】
#   cd /c/home/dev/test/force-tama
#   bash ~/sf-tools/tests/integration/test-sequence-check.sh
#
# 【前提条件】
#   - gh auth login 済み
#   - リポジトリ admin 権限を持つ PAT で認証済み（staging への直接 push に必要）
#   - sf-tools/config/branches.txt が配置済み
# ==============================================================================

set -uo pipefail

REPO="tama-create/force-tama"
TS=$(date +%H%M%S)

# ログ出力先（force-tama ルートの sf-tools/logs/）
ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOG_DIR="$ROOT_DIR/sf-tools/logs"
LOG_FILE="$LOG_DIR/test-sequence-check.log"
mkdir -p "$LOG_DIR"
# 画面とログファイルに同時出力
exec > >(tee "$LOG_FILE") 2>&1
echo "====== テスト開始: $(date '+%Y-%m-%d %H:%M:%S') ======"

# ==============================================================================
# branches.txt の読み込み
# ==============================================================================
BRANCH_LIST_FILE="$ROOT_DIR/sf-tools/config/branches.txt"
if [[ ! -f "$BRANCH_LIST_FILE" ]]; then
    BRANCH_LIST_FILE="$HOME/sf-tools/templates/config/branches.txt"
fi
if [[ ! -f "$BRANCH_LIST_FILE" ]]; then
    echo "[ERROR] branches.txt が見つかりません" >&2
    exit 1
fi

# BRANCHES: branches.txt の記載順（main, staging, develop）
BRANCHES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    BRANCHES+=("$line")
done < "$BRANCH_LIST_FILE"

NUM_BRANCHES=${#BRANCHES[@]}
MAIN_BRANCH="${BRANCHES[0]}"

echo "ブランチ構成: ${BRANCHES[*]} (${NUM_BRANCHES}ブランチ)"
echo "構成ファイル: $BRANCH_LIST_FILE"

# MERGE_PATH: マージ順序（下位→上位: develop, staging, main）
MERGE_PATH=()
for ((i=NUM_BRANCHES-1; i>=0; i--)); do
    MERGE_PATH+=("${BRANCHES[$i]}")
done

# NON_MAIN: main 以外のブランチ（マージ順序）
NON_MAIN=()
for b in "${MERGE_PATH[@]}"; do
    [[ "$b" != "$MAIN_BRANCH" ]] && NON_MAIN+=("$b")
done
NUM_NON_MAIN=${#NON_MAIN[@]}

# ==============================================================================
# Feature ブランチの設計
# ==============================================================================
# FEATURES[i] = NON_MAIN[0..i] にマージ済み（i 番目の上位ブランチのテスト用）
# FEATURE_UNMERGED = どこにもマージしない（警告テスト＋最下位ブランチテスト用）
FEATURES=()
for ((i=0; i<NUM_NON_MAIN; i++)); do
    FEATURES+=("feature/seq-test-${i}-${TS}")
done
FEATURE_UNMERGED="feature/seq-test-none-${TS}"

# クリーンアップ対象のブランチ一覧
CREATED_BRANCHES=("${FEATURES[@]}" "$FEATURE_UNMERGED")

PASS=0; FAIL=0; SKIP=0
CREATED_PRS=()

# カラー
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

# ==============================================================================
# クリーンアップ（EXIT 時に必ず実行）
# ==============================================================================
cleanup() {
  echo -e "\n${YELLOW}━━━ クリーンアップ ━━━${NC}"

  # テスト用 PR をクローズ
  for pr in "${CREATED_PRS[@]:-}"; do
    [[ -z "$pr" ]] && continue
    gh pr close "$pr" --repo "$REPO" --comment "[自動テスト完了] クローズします。" 2>/dev/null \
      && echo "  PR#$pr クローズ" || true
  done

  # テスト用ブランチを削除
  for br in "${CREATED_BRANCHES[@]:-}"; do
    [[ -z "$br" ]] && continue
    gh api "repos/$REPO/git/refs/heads/$br" -X DELETE 2>/dev/null \
      && echo "  remote: $br 削除" || true
    git branch -D "$br" 2>/dev/null || true
  done

  # 中断状態のリセット
  git merge --abort 2>/dev/null || true
  git rebase --abort 2>/dev/null || true
  git checkout "$MAIN_BRANCH" 2>/dev/null || true
  echo "  完了"
}
trap cleanup EXIT

# ==============================================================================
# PR 作成 → マージ順序を検証の結果を確認
# ==============================================================================
test_scenario() {
  local desc="$1"
  local head="$2"
  local base="$3"
  local expected="$4"   # pass | fail

  echo -e "\n${BLUE}▶ $desc${NC}"
  echo    "  $head → $base  (期待: $expected)"

  # PR 作成
  local pr_output
  pr_output=$(gh pr create --repo "$REPO" \
    --head "$head" --base "$base" \
    --title "[SEQ-TEST-$TS] $desc" \
    --body "⚠️ 自動テスト用 PR です。マージしないでください。" 2>&1) || true

  if ! echo "$pr_output" | grep -qE "^https://"; then
    echo -e "  ${YELLOW}⚠ スキップ${NC}: PR 作成失敗 → $pr_output"
    ((SKIP++)); return
  fi

  local pr_num
  pr_num=$(echo "$pr_output" | grep -oE '[0-9]+$')
  CREATED_PRS+=("$pr_num")
  echo "  PR#$pr_num 作成"

  # チェック完了まで最大 5 分待機
  local actual="timeout"
  for i in $(seq 1 20); do
    sleep 15
    local checks
    checks=$(gh pr checks "$pr_num" --repo "$REPO" 2>&1 || true)

    # チェックがまだ登録されていない場合は待機を継続
    if echo "$checks" | grep -qi "no checks"; then
      echo "  待機中... $((i * 15))s (チェック未登録)"
      continue
    fi

    # pending / in_progress が残っている場合は待機を継続
    if echo "$checks" | grep -qE "\s(pending|in_progress)\s"; then
      echo "  待機中... $((i * 15))s"
      continue
    fi

    # チェック完了 — 結果を取得
    local seq_result
    seq_result=$(echo "$checks" | grep "マージ順序を検証" | awk -F'\t' '{print $2}' | head -1)
    if [[ -z "$seq_result" ]]; then
      actual="pass(skipped)"   # 最下位ブランチ向け PR はジョブ自体がスキップ → pass 扱い
    else
      actual="$seq_result"
    fi
    break
  done

  echo "  マージ順序を検証: $actual"

  # 判定
  local ok=false
  if [[ "$expected" == "fail" && "$actual" == "fail" ]]; then ok=true; fi
  if [[ "$expected" == "pass" ]] && echo "$actual" | grep -qE "^pass"; then ok=true; fi

  if $ok; then
    echo -e "  ${GREEN}✅ PASS${NC}"
    ((PASS++))
  else
    echo -e "  ${RED}❌ FAIL${NC}  (期待: $expected, 実際: $actual)"
    ((FAIL++))
  fi
}

# ブランチを指定先に直接マージして push するヘルパー
merge_to() {
  local feature="$1"
  local target="$2"
  local tmp="_${target}_tmp"
  git checkout -B "$tmp" "origin/$target"
  if ! git merge "$feature" --no-ff -X theirs -m "test(seq-check): merge $feature to $target"; then
    git merge --abort 2>/dev/null || true
    git checkout "$MAIN_BRANCH"
    git branch -D "$tmp" 2>/dev/null || true
    echo "  [ERROR] $feature → $target のマージに失敗しました" >&2
    return 1
  fi
  git push origin "$tmp:$target"
  git checkout "$MAIN_BRANCH" && git branch -D "$tmp"
}

# ==============================================================================
# セットアップ
# ==============================================================================
cd "$ROOT_DIR"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  シーケンスチェック統合テスト ($TS)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 前回の残骸ブランチをリモートから自動クリーンアップ
echo -e "\n${YELLOW}━━━ クリーンアップ（前回の残骸） ━━━${NC}"
stale_branches=$(git ls-remote --heads origin "refs/heads/feature/seq-test-*" 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||')
if [[ -n "$stale_branches" ]]; then
  while IFS= read -r br; do
    git push origin --delete "$br" 2>/dev/null && echo "  remote: $br 削除" || true
    git branch -D "$br" 2>/dev/null || true
  done <<< "$stale_branches"
else
  echo "  残骸ブランチなし"
fi

echo -e "\n${YELLOW}━━━ セットアップ ━━━${NC}"
git fetch origin "${BRANCHES[@]}"

# Feature ブランチのセットアップ
# FEATURES[i]: NON_MAIN[0..i] にマージ済みのブランチを作成
for ((i=0; i<NUM_NON_MAIN; i++)); do
  # マージ先の説明を組み立て
  local_desc=""
  for ((j=0; j<=i; j++)); do
    [[ -n "$local_desc" ]] && local_desc+="+"
    local_desc+="${NON_MAIN[$j]}"
  done
  echo "FEATURES[$i] を作成（${local_desc} にマージ）..."

  git checkout -b "${FEATURES[$i]}" "origin/$MAIN_BRANCH"
  git commit --allow-empty -m "test(seq-check): FEATURES[$i] $TS"
  git push origin "${FEATURES[$i]}"

  # NON_MAIN[0..i] にマージ
  for ((j=0; j<=i; j++)); do
    merge_to "${FEATURES[$i]}" "${NON_MAIN[$j]}"
  done
done

# 未マージの Feature ブランチ
echo "FEATURE_UNMERGED を作成（未マージ）..."
git checkout -b "$FEATURE_UNMERGED" "origin/$MAIN_BRANCH"
git commit --allow-empty -m "test(seq-check): FEATURE_UNMERGED $TS"
git push origin "$FEATURE_UNMERGED"
git checkout "$MAIN_BRANCH"

echo "セットアップ完了"

# ==============================================================================
# テスト実行
# ==============================================================================
echo -e "\n${YELLOW}━━━ テスト実行 ━━━${NC}"

# ❌ エラーブロック（保護ブランチ間の PR はすべてブロック）
for ((i=0; i<NUM_BRANCHES; i++)); do
  for ((j=i+1; j<NUM_BRANCHES; j++)); do
    test_scenario "❌ ${BRANCHES[$j]} → ${BRANCHES[$i]}（ブロック）" \
      "${BRANCHES[$j]}" "${BRANCHES[$i]}" "fail"
  done
done

# ⚠️ 警告のみ（前提ブランチ未マージの feature PR → マージ可・Slack 通知あり）
# MERGE_PATH[0] は最下位ブランチ（前提条件なし）なのでスキップ
for ((i=1; i<${#MERGE_PATH[@]}; i++)); do
  target="${MERGE_PATH[$i]}"
  prereq="${MERGE_PATH[$((i-1))]}"
  test_scenario "⚠️  feature/* → ${target}（${prereq}未マージ）" \
    "$FEATURE_UNMERGED" "$target" "pass"
done

# ✅ 正常通過
if [[ $NUM_NON_MAIN -gt 0 ]]; then
  # 最下位ブランチへの PR（前提条件なし）
  test_scenario "✅ feature/* → ${NON_MAIN[0]}（制限なし）" \
    "$FEATURE_UNMERGED" "${NON_MAIN[0]}" "pass"

  # 各ブランチへの PR（前提条件を満たした状態）
  for ((i=0; i<NUM_NON_MAIN; i++)); do
    if ((i < NUM_NON_MAIN - 1)); then
      target="${NON_MAIN[$((i+1))]}"
    else
      target="$MAIN_BRANCH"
    fi
    test_scenario "✅ feature/* → ${target}（${NON_MAIN[$i]}済み）" \
      "${FEATURES[$i]}" "$target" "pass"
  done
else
  # main のみ構成 — feature→main は常に pass
  test_scenario "✅ feature/* → ${MAIN_BRANCH}（制限なし）" \
    "$FEATURE_UNMERGED" "$MAIN_BRANCH" "pass"
fi

# ==============================================================================
# 結果サマリー
# ==============================================================================
TOTAL=$((PASS + FAIL + SKIP))
echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  テスト結果: ${GREEN}✅ $PASS 件成功${NC} / ${RED}❌ $FAIL 件失敗${NC} / ${YELLOW}⚠ $SKIP 件スキップ${NC}  (計 $TOTAL 件)"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ $FAIL -eq 0 && $SKIP -eq 0 ]]; then
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                                              ║${NC}"
  echo -e "${GREEN}║   🎉🎉🎉  全テスト 100% パス！  🎉🎉🎉       ║${NC}"
  echo -e "${GREEN}║                                              ║${NC}"
  echo -e "${GREEN}║   シーケンスチェック、完璧に動いています！   ║${NC}"
  echo -e "${GREEN}║                                              ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
fi

[[ $FAIL -gt 0 ]] && exit 1 || exit 0
