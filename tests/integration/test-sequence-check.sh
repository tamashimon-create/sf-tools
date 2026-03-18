#!/usr/bin/env bash
# ==============================================================================
# test-sequence-check.sh - シーケンスチェック全パターン統合テスト
# ==============================================================================
# gh CLI を使って全 PR パターンを自動検証する。
#
# 【テスト対象パターン】
#   ❌ エラーブロック  : develop→staging / develop→main / staging→main
#   ⚠️  警告のみ（pass）: feature/*→staging（develop未マージ）/ feature/*→main（staging未マージ）
#   ✅ 正常通過        : feature/*→develop / feature/*→staging（develop済）/ feature/*→main（staging済）
#
# 【使用方法】
#   cd /c/home/dev/test/force-tama
#   bash ~/sf-tools/tests/test-sequence-check.sh
#
# 【前提条件】
#   - gh auth login 済み
#   - リポジトリ admin 権限を持つ PAT で認証済み（staging への直接 push に必要）
#
# 【ブランチ設計】
#   FEATURE_A : develop のみにマージ → ✅ staging テスト用
#   FEATURE_B : develop + staging にマージ → ✅ main テスト用
#   FEATURE_C : どこにもマージしない → ⚠️ テスト + ✅ develop テスト用
# ==============================================================================

set -uo pipefail

REPO="tamashimon-create/force-tama"
TS=$(date +%H%M%S)

# ログ出力先（force-tama ルートの sf-tools/logs/）
ROOT_DIR_EARLY=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
LOG_DIR="$ROOT_DIR_EARLY/sf-tools/logs"
LOG_FILE="$LOG_DIR/test-sequence-check.log"
mkdir -p "$LOG_DIR"
# 画面とログファイルに同時出力
exec > >(tee "$LOG_FILE") 2>&1
echo "====== テスト開始: $(date '+%Y-%m-%d %H:%M:%S') ======"
FEATURE_A="feature/seq-test-dev-${TS}"      # develop のみマージ済み
FEATURE_B="feature/seq-test-both-${TS}"     # develop + staging マージ済み
FEATURE_C="feature/seq-test-none-${TS}"     # 未マージ

PASS=0; FAIL=0; SKIP=0
CREATED_PRS=()
CREATED_BRANCHES=("$FEATURE_A" "$FEATURE_B" "$FEATURE_C")

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
  git checkout main 2>/dev/null || true
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
    if ! echo "$checks" | grep -qE "\s(pending|in_progress)\s"; then
      local seq_result
      seq_result=$(echo "$checks" | grep "マージ順序を検証" | awk -F'\t' '{print $2}' | head -1)
      if [[ -z "$seq_result" ]]; then
        actual="pass(skipped)"   # develop 向け PR はジョブ自体がスキップ → pass 扱い
      else
        actual="$seq_result"
      fi
      break
    fi
    echo "  待機中... $((i * 15))s"
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
    git checkout main
    git branch -D "$tmp" 2>/dev/null || true
    echo "  [ERROR] $feature → $target のマージに失敗しました" >&2
    return 1
  fi
  git push origin "$tmp:$target"
  git checkout main && git branch -D "$tmp"
}

# ==============================================================================
# セットアップ
# ==============================================================================
ROOT_DIR="$ROOT_DIR_EARLY"
cd "$ROOT_DIR"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  シーケンスチェック統合テスト ($TS)${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "\n${YELLOW}━━━ セットアップ ━━━${NC}"
git fetch origin main develop staging

# FEATURE_A: develop のみにマージ（✅ staging テスト用）
echo "FEATURE_A を作成（develop のみマージ）..."
git checkout -b "$FEATURE_A" origin/main
git commit --allow-empty -m "test(seq-check): FEATURE_A $TS"
git push origin "$FEATURE_A"
merge_to "$FEATURE_A" "develop"

# FEATURE_B: develop + staging にマージ（✅ main テスト用）
echo "FEATURE_B を作成（develop + staging にマージ）..."
git checkout -b "$FEATURE_B" origin/main
git commit --allow-empty -m "test(seq-check): FEATURE_B $TS"
git push origin "$FEATURE_B"
merge_to "$FEATURE_B" "develop"
merge_to "$FEATURE_B" "staging"

# FEATURE_C: 未マージ（⚠️ テスト + ✅ develop テスト用）
echo "FEATURE_C を作成（未マージ）..."
git checkout -b "$FEATURE_C" origin/main
git commit --allow-empty -m "test(seq-check): FEATURE_C $TS"
git push origin "$FEATURE_C"
git checkout main

echo "セットアップ完了"

# ==============================================================================
# テスト実行
# ==============================================================================
echo -e "\n${YELLOW}━━━ テスト実行 ━━━${NC}"

# ❌ エラーブロック（マージ不可）
test_scenario "❌ develop → staging（ブロック）" "develop"   "staging" "fail"
test_scenario "❌ develop → main（ブロック）"    "develop"   "main"    "fail"
test_scenario "❌ staging → main（ブロック）"    "staging"   "main"    "fail"

# ⚠️ 警告のみ（マージ可・Slack 通知あり）
test_scenario "⚠️  feature/* → staging（develop未マージ）" "$FEATURE_C" "staging" "pass"
test_scenario "⚠️  feature/* → main（staging未マージ）"    "$FEATURE_C" "main"    "pass"

# ✅ 正常通過
test_scenario "✅ feature/* → develop（制限なし）"         "$FEATURE_C" "develop" "pass"
test_scenario "✅ feature/* → staging（develop済み）"      "$FEATURE_A" "staging" "pass"
test_scenario "✅ feature/* → main（staging済み）"         "$FEATURE_B" "main"    "pass"

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
