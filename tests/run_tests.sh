#!/bin/bash
# ==============================================================================
# run_tests.sh - sf-tools テストスイート実行スクリプト
# ==============================================================================
# 使い方: bash tests/run_tests.sh [テストファイル名]
#   引数なし → 全テストを順番に実行
#   引数あり → 指定したテストのみ実行（例: bash run_tests.sh test_sf-hook.sh）
# ==============================================================================

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASSED=0
TOTAL_FAILED=0

CLR_PASS='\033[32m'
CLR_FAIL='\033[31m'
CLR_HEAD='\033[36m'
CLR_RST='\033[0m'

# 実行するテストファイルを順番に定義
TEST_FILES=(
    test_sf-unhook.sh
    test_sf-hook.sh
    test_sf-upgrade.sh
    test_sf-install.sh
    test_sf-start.sh
    test_sf-restart.sh
    test_sf-metasync.sh
    test_sf-release.sh
    test_sf-deploy.sh
)

# 引数指定があれば対象を絞る
if [[ $# -gt 0 ]]; then
    TEST_FILES=("$@")
fi

echo ""
echo "========================================"
echo "  sf-tools テストスイート"
echo "========================================"

for test_file in "${TEST_FILES[@]}"; do
    test_path="$TESTS_DIR/$test_file"
    if [[ ! -f "$test_path" ]]; then
        echo -e "${CLR_FAIL}[SKIP] $test_file が見つかりません${CLR_RST}"
        continue
    fi

    echo ""
    # サブシェルで実行してカウンターを独立させる
    output=$(bash "$test_path" 2>&1)
    echo "$output"

    # PASS / FAIL 件数を集計（ANSI カラーコードが含まれるため ^ アンカーなし）
    passed=$(echo "$output" | grep -c '\[PASS\]' || true)
    failed=$(echo "$output" | grep -c '\[FAIL\]' || true)
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
done

# 総合サマリー
echo ""
echo "========================================"
echo "  総合結果"
echo "========================================"
TOTAL=$((TOTAL_PASSED + TOTAL_FAILED))
if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "${CLR_PASS}すべてのテストが成功しました: ${TOTAL_PASSED}/${TOTAL} 件${CLR_RST}"
    exit 0
else
    echo -e "${CLR_FAIL}失敗: ${TOTAL_FAILED} 件 / 成功: ${TOTAL_PASSED} 件 / 合計: ${TOTAL} 件${CLR_RST}"
    exit 1
fi
