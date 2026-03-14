#!/bin/bash
# ==============================================================================
# test_sf-restart.sh - sf-restart.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-restart.sh ===${CLR_RST}"

# 設定ファイルがクリアされる
test_clears_config_files() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    echo '{"target-org":"oldorg"}' > "$td/.sf/config.json"
    echo '{"defaultusername":"oldorg"}' > "$td/.sfdx/sfdx-config.json"

    # モック sf-start.sh（ローカルラッパー）を作成
    cat > "$td/sf-start.sh" << 'EOF'
#!/bin/bash
echo "sf-start called FORCE_RELOGIN=$FORCE_RELOGIN" >> "$MOCK_CALL_LOG"
exit 0
EOF
    chmod +x "$td/sf-start.sh"

    cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-restart.sh" 2>&1 >/dev/null

    assert_file_not_exists "$td/.sf/config.json" ".sf/config.json がクリアされた"
    assert_file_not_exists "$td/.sfdx/sfdx-config.json" ".sfdx/sfdx-config.json がクリアされた"
    teardown "$td" "$mb" "$mh"
}

# sf-start.sh が FORCE_RELOGIN=1 で呼び出される
test_calls_sf_start_with_force_relogin() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    cat > "$td/sf-start.sh" << 'EOF'
#!/bin/bash
echo "sf-start called FORCE_RELOGIN=$FORCE_RELOGIN" >> "$MOCK_CALL_LOG"
exit 0
EOF
    chmod +x "$td/sf-start.sh"

    cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-restart.sh" 2>&1 >/dev/null

    assert_file_contains "$MOCK_CALL_LOG" "FORCE_RELOGIN=1" "sf-start.sh が FORCE_RELOGIN=1 で呼び出された"
    teardown "$td" "$mb" "$mh"
}

# sf-start.sh が存在しない → エラー
test_no_sf_start() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"
    # sf-start.sh を用意しない

    local out; out=$(cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-restart.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "sf-start.sh なし → エラー終了"
    teardown "$td" "$mb" "$mh"
}

# force-* 以外で実行 → エラー
test_outside_force_dir() {
    local rd mb mh
    rd=$(setup_regular_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    local out; out=$(cd "$rd" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-restart.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "force-* 外 → エラー終了"
    teardown "$rd" "$mb" "$mh"
}

test_clears_config_files
test_calls_sf_start_with_force_relogin
test_no_sf_start
test_outside_force_dir

print_summary
