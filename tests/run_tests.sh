#!/bin/bash
# ==============================================================================
# run_tests.sh - sf-tools テストスイート実行スクリプト
# ==============================================================================
# 使い方: bash tests/run_tests.sh [テストファイル名]
#   引数なし → 全テストを順番に実行
#   引数あり → 指定したテストのみ実行（例: bash run_tests.sh test_sf-hook.sh）
# ==============================================================================

# Windows Git Bash の場合は WSL で自動リダイレクト（高速化）
if [[ "$(uname -s)" =~ MINGW|MSYS ]] && command -v wsl >/dev/null 2>&1; then
    WSL_SCRIPT=$(echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")" \
        | sed 's|^/\([a-z]\)/|/mnt/\1/|')
    MSYS_NO_PATHCONV=1 exec wsl bash "$WSL_SCRIPT" "$@"
fi

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$TESTS_DIR/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run_tests.log"
TOTAL_PASSED=0
TOTAL_FAILED=0

CLR_PASS='\033[32m'
CLR_FAIL='\033[31m'
CLR_HEAD='\033[36m'
CLR_RST='\033[0m'

# 実行するテストファイルを順番に定義
TEST_FILES=(
    test_common.sh
    test_sf-unhook.sh
    test_sf-hook.sh
    test_sf-upgrade.sh
    test_sf-install.sh
    test_sf-start.sh
    test_sf-restart.sh
    test_sf-metasync.sh
    test_sf-release.sh
    test_sf-deploy.sh
    test_repo-settings.sh
    test_sf-job.sh
)

# 引数指定があれば対象を絞る
if [[ $# -gt 0 ]]; then
    TEST_FILES=("$@")
fi

# 画面とログファイルの両方に出力する関数
tee_log() { tee -a "$LOG_FILE"; }

# ログファイルを初期化
echo "====== テスト開始: $(date '+%Y-%m-%d %H:%M:%S') ======" > "$LOG_FILE"

echo ""
echo "========================================"
echo "  sf-tools テストスイート"
echo "========================================"

for test_file in "${TEST_FILES[@]}"; do
    test_path="$TESTS_DIR/$test_file"
    if [[ ! -f "$test_path" ]]; then
        echo -e "${CLR_FAIL}[SKIP] $test_file が見つかりません${CLR_RST}" | tee_log
        continue
    fi

    echo "" | tee_log
    # サブシェルで実行してカウンターを独立させる
    output=$(bash "$test_path" 2>&1)
    echo "$output" | tee_log

    # PASS / FAIL 件数を集計（ANSI カラーコードが含まれるため ^ アンカーなし）
    passed=$(echo "$output" | grep -c '\[PASS\]' || true)
    failed=$(echo "$output" | grep -c '\[FAIL\]' || true)
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
done

# 総合サマリー
TOTAL=$((TOTAL_PASSED + TOTAL_FAILED))
# 緑太文字 / 赤太文字（背景なし）
CLR_OK='\033[32;1m'
CLR_NG='\033[31;1m'

echo "" | tee_log
W=60  # バナー内側の幅
_banner_line() { local c="$1" msg="$2"; local pad=$(( (W - ${#msg}) / 2 )); printf "${c}    %${pad}s%s%$(( W - pad - ${#msg} ))s    ${CLR_RST}\n" "" "$msg" ""; }
_banner_border() { local c="$1"; printf "${c}    "; printf '=%.0s' $(seq 1 $W); printf "    ${CLR_RST}\n"; }
_banner_blank() { local c="$1"; printf "${c}    %${W}s    ${CLR_RST}\n" ""; }

if [[ $TOTAL_FAILED -eq 0 ]]; then
    MSG=">>> ALL ${TOTAL} TESTS PASSED !! <<<"
    {
        echo ""
        _banner_blank  "$CLR_OK"
        _banner_border "$CLR_OK"
        _banner_blank  "$CLR_OK"
        _banner_line   "$CLR_OK" "$MSG"
        _banner_blank  "$CLR_OK"
        _banner_border "$CLR_OK"
        _banner_blank  "$CLR_OK"
        echo ""
    } | tee_log
    exit 0
else
    MSG=">>> FAILED: ${TOTAL_FAILED} / ${TOTAL} TESTS <<<"
    {
        echo ""
        _banner_blank  "$CLR_NG"
        _banner_border "$CLR_NG"
        _banner_blank  "$CLR_NG"
        _banner_line   "$CLR_NG" "$MSG"
        _banner_blank  "$CLR_NG"
        _banner_border "$CLR_NG"
        _banner_blank  "$CLR_NG"
        echo ""
    } | tee_log
    exit 1
fi
