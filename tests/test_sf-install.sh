#!/bin/bash
# ==============================================================================
# test_sf-install.sh - sf-install.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-install.sh ===${CLR_RST}"

# 正常実行 → git pull、マージドライバー登録、npm install が行われる
test_normal_run() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    local out; out=$(cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-install.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "正常実行 → 終了コード 0"
    assert_file_contains "$MOCK_CALL_LOG" "git -C" "sf-tools の git pull が呼び出された"
    assert_file_contains "$MOCK_CALL_LOG" "git config merge.ours.driver" "マージドライバーが登録された"
    teardown "$td" "$mb" "$mh"
}

# ラッパースクリプトが存在しない → 新規生成される
test_wrapper_generated() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-install.sh" 2>&1 >/dev/null

    assert_file_exists "$td/sf-start.sh" "sf-start.sh が生成された"
    assert_file_exists "$td/sf-restart.sh" "sf-restart.sh が生成された"
    assert_executable "$td/sf-start.sh" "sf-start.sh に実行権限がある"
    teardown "$td" "$mb" "$mh"
}

# ラッパースクリプトが既に存在する → スキップ（上書きされない）
test_wrapper_skip_if_exists() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    echo "#!/bin/bash" > "$td/sf-start.sh"
    echo "echo existing_wrapper" >> "$td/sf-start.sh"
    chmod +x "$td/sf-start.sh"

    cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-install.sh" 2>&1 >/dev/null

    assert_file_contains "$td/sf-start.sh" "existing_wrapper" "既存ラッパーは上書きされない"
    teardown "$td" "$mb" "$mh"
}

# スタンプファイルが新しい（24h以内）→ sf-upgrade.sh がバックグラウンド起動されない
test_upgrade_skipped_within_24h() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    # 1時間前のタイムスタンプでスタンプファイルを作成
    touch -t "$(date -d '1 hour ago' +'%Y%m%d%H%M' 2>/dev/null || date -v -1H +'%Y%m%d%H%M' 2>/dev/null || date +'%Y%m%d%H%M')" "$mh/.sf-tools-last-update" 2>/dev/null \
        || touch "$mh/.sf-tools-last-update"

    local out; out=$(cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-install.sh" 2>&1)

    echo "$out" | grep -q "スキップ" && pass "24h 以内のためスキップメッセージが表示された" \
        || fail "24h 以内のためスキップメッセージが表示された"
    teardown "$td" "$mb" "$mh"
}

# スタンプファイルなし（初回）→ sf-upgrade.sh がバックグラウンド起動される
test_upgrade_triggered_on_first_run() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    # スタンプファイルなし（初回実行を再現）
    rm -f "$mh/.sf-tools-last-update"

    cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-install.sh" 2>&1 >/dev/null
    sleep 1  # バックグラウンド起動を少し待つ

    assert_file_exists "$mh/.sf-tools-last-update" "スタンプファイルが作成された"
    teardown "$td" "$mb" "$mh"
}

# package.json が存在しない → npm install がスキップされる
test_npm_install_skipped_no_package_json() {
    local td mb mh
    td=$(setup_force_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"
    rm -f "$mh/.sf-tools-last-update"  # アップグレードも動かすが npm install のみ確認

    local out; out=$(cd "$td" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-install.sh" 2>&1)

    echo "$out" | grep -q "package.json が見つかりません" \
        && pass "package.json なし → npm install スキップメッセージ" \
        || fail "package.json なし → npm install スキップメッセージ"
    teardown "$td" "$mb" "$mh"
}

# force-* 以外で実行 → エラー
test_outside_force_dir() {
    local rd mb mh
    rd=$(setup_regular_dir); mb=$(setup_mock_bin); export MOCK_CALL_LOG="$mb/calls.log"; mh=$(setup_mock_home)
    create_all_mocks "$mb"

    local out; out=$(cd "$rd" && HOME="$mh" PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-install.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "force-* 外 → エラー終了"
    teardown "$rd" "$mb" "$mh"
}

test_normal_run
test_wrapper_generated
test_wrapper_skip_if_exists
test_upgrade_skipped_within_24h
test_upgrade_triggered_on_first_run
test_npm_install_skipped_no_package_json
test_outside_force_dir

print_summary
