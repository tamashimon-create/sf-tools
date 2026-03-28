#!/bin/bash
# ==============================================================================
# test_security.sh - セキュリティ監査テスト
# ==============================================================================
# セキュリティ修正のリグレッションを静的解析と実行時検証で検出する。
#
# 【静的解析】
#   1. run 経由の sf org display --verbose 禁止（sfdxAuthUrl ログ漏洩防止）
#   2. lib/common.sh で mktemp を使用していること（TOCTOU 対策）
#   3. バックグラウンド実行の stderr を /dev/null に捨てていないこと
#   4. .sf-init.env に chmod 600 が設定されていること
#
# 【実行時検証】
#   5. sf-update-secret.sh 実行後にログに sfdxAuthUrl が記録されないこと
#   6. ログディレクトリに chmod 700 が設定されること（Linux/WSL のみ）
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== セキュリティ監査テスト ===${CLR_RST}"

# ==============================================================================
# 静的解析テスト
# ==============================================================================

# --- 1. run 経由の sf org display --verbose 禁止 ---
# sfdxAuthUrl を含む出力が run ラッパー経由でログに記録されないよう、
# 直接実行に変更した修正のリグレッションを検出する。
test_static_no_run_sf_org_display() {
    local found
    found=$(grep -rEn 'run\b.*sf\b.*org\b.*display\b.*--verbose' \
        "$SF_TOOLS_DIR/bin/" "$SF_TOOLS_DIR/phases/" 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)

    if [[ -z "$found" ]]; then
        pass "run 経由の sf org display --verbose が存在しない"
    else
        fail "run 経由の sf org display --verbose が検出された（sfdxAuthUrl 漏洩リスク）" "$found"
    fi
}

# --- 2. lib/common.sh で mktemp を使用していること ---
# 一時ファイルを予測不可能な名前で生成する修正のリグレッションを検出する。
test_static_mktemp_used_in_common() {
    if grep -q 'mktemp' "$SF_TOOLS_DIR/lib/common.sh"; then
        pass "lib/common.sh で mktemp を使用している"
    else
        fail "lib/common.sh で mktemp が使用されていない（TOCTOU リスク）"
    fi
}

# --- 3. バックグラウンド実行で stderr を /dev/null に捨てていないこと ---
# sf-install.sh の bg 実行で stderr をログに記録するよう変更した修正のリグレッションを検出する。
test_static_no_devnull_bg_stderr() {
    local found
    found=$(grep -rEn '>/dev/null[[:space:]]+2>&1[[:space:]]*&' \
        "$SF_TOOLS_DIR/bin/" "$SF_TOOLS_DIR/phases/" 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)

    if [[ -z "$found" ]]; then
        pass "バックグラウンド実行で stderr を /dev/null に捨てていない"
    else
        fail "バックグラウンド実行で stderr が /dev/null に捨てられている（エラーが追跡不能になる）" "$found"
    fi
}

# --- 4. .sf-init.env に chmod 600 が設定されていること ---
# PAT_TOKEN 等の機密情報を含む .sf-init.env にファイル権限を設定する修正のリグレッションを検出する。
test_static_chmod600_sf_init_env() {
    local target="$SF_TOOLS_DIR/phases/init/02_project_info.sh"
    if grep -qE 'chmod 600.*(SF_INIT_ENV_FILE|sf-init\.env)' "$target"; then
        pass "02_project_info.sh に chmod 600 が設定されている"
    else
        fail "02_project_info.sh に chmod 600 が見つからない（.sf-init.env が保護されていない）" "$target"
    fi
}

# ==============================================================================
# 実行時検証テスト
# ==============================================================================

# --- 5. sfdxAuthUrl がログに記録されないこと ---
# sf org display の出力を直接実行に変更した修正を実際の動作で検証する。
# モックの sf コマンドが canary 値を含む sfdxAuthUrl を返すことを前提とする。
test_runtime_sfdxauthurl_not_logged() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"

    # canary 値: ログに記録されたら即検出できるユニークな文字列
    local canary="force://PlatformCLI::CANARY_SECRET_sfdxAuthUrl_TOKEN@canary.salesforce.com"

    # git モック
    cat > "$mb/git" << 'EOF'
#!/bin/bash
echo "git $*" >> "${MOCK_CALL_LOG:-/dev/null}"
case "$1" in
    remote) echo "https://github.com/testowner/force-test.git"; exit 0 ;;
    *)      exit 0 ;;
esac
EOF
    chmod +x "$mb/git"

    # sf モック: canary 値を含む sfdxAuthUrl を返す（外側の << EOF で ${canary} を展開）
    cat > "$mb/sf" << EOF
#!/bin/bash
echo "sf \$*" >> "\${MOCK_CALL_LOG:-/dev/null}"
cat << 'SFEOF'
{
  "status": 0,
  "result": {
    "username": "test@example.com",
    "sfdxAuthUrl": "${canary}"
  }
}
SFEOF
exit 0
EOF
    chmod +x "$mb/sf"

    # gh モック
    cat > "$mb/gh" << 'EOF'
#!/bin/bash
echo "gh $*" >> "${MOCK_CALL_LOG:-/dev/null}"
exit 0
EOF
    chmod +x "$mb/gh"

    # "n" を入力して ask_yn で中止（gh secret set の前に終了させる）
    local log_file="$td/sf-tools/logs/sf-update-secret.log"
    ( cd "$td" && echo "n" | PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-update-secret.sh" > /dev/null 2>&1 ) || true

    if [[ ! -f "$log_file" ]]; then
        skip "ログファイルが生成されなかった（テスト環境依存）"
    elif grep -qF "$canary" "$log_file" 2>/dev/null; then
        fail "sfdxAuthUrl がログに記録されている（機密情報漏洩リスク）" "$log_file"
    else
        pass "sfdxAuthUrl がログに記録されていない"
    fi

    teardown "$td" "$mb"
}

# --- 6. ログディレクトリに chmod 700 が設定されること（Linux/WSL のみ） ---
# lib/common.sh の _init_log でログディレクトリに chmod 700 を設定する修正を実際の動作で検証する。
test_runtime_log_dir_permission() {
    # Windows（NTFS）と macOS では chmod が機能しないためスキップ
    local uname_s; uname_s=$(uname -s)
    if [[ "$uname_s" != "Linux" ]]; then
        skip "ログディレクトリ権限チェック（Linux/WSL 以外はスキップ: $uname_s）"
        return
    fi

    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"

    # 最小限のモック（ログ初期化まで到達させるため）
    cat > "$mb/git" << 'EOF'
#!/bin/bash
case "$1" in
    remote) echo "https://github.com/testowner/force-test.git" ;;
    *)      ;;
esac
exit 0
EOF
    chmod +x "$mb/git"

    cat > "$mb/sf" << 'EOF'
#!/bin/bash
cat << 'SFEOF'
{"status":0,"result":{"username":"test@example.com","sfdxAuthUrl":"force://x::y@z.com"}}
SFEOF
exit 0
EOF
    chmod +x "$mb/sf"

    cat > "$mb/gh" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mb/gh"

    # スクリプトを起動してログ初期化を走らせる（n で即中止）
    local log_dir="$td/sf-tools/logs"
    ( cd "$td" && echo "n" | PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/bin/sf-update-secret.sh" > /dev/null 2>&1 ) || true

    local perm; perm=$(stat -c "%a" "$log_dir" 2>/dev/null || echo "unknown")
    if [[ "$perm" == "700" ]]; then
        pass "ログディレクトリの権限が 700 に設定されている"
    elif [[ "$perm" == "unknown" ]]; then
        skip "ログディレクトリの権限を取得できなかった"
    else
        fail "ログディレクトリの権限が 700 ではない: $perm"
    fi

    teardown "$td" "$mb"
}

# ==============================================================================
# テスト実行
# ==============================================================================
test_static_no_run_sf_org_display
test_static_mktemp_used_in_common
test_static_no_devnull_bg_stderr
test_static_chmod600_sf_init_env
test_runtime_sfdxauthurl_not_logged
test_runtime_log_dir_permission

echo ""
echo -e "  結果: ${CLR_PASS}${TESTS_PASSED} PASS${CLR_RST} / ${CLR_FAIL}${TESTS_FAILED} FAIL${CLR_RST}"
