#!/bin/bash
# ==============================================================================
# test_sf-check.sh - sf-check.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-check.sh ===${CLR_RST}"

# ------------------------------------------------------------------------------
# [files] セクション: 存在するパスのみ → 正常終了
# ------------------------------------------------------------------------------
test_files_valid_path() {
    local td
    td=$(setup_force_dir)
    mkdir -p "$td/force-app/main/default/classes"
    touch "$td/force-app/main/default/classes/MyClass.cls"

    local deploy="$td/deploy.txt"
    printf '[files]\nforce-app/main/default/classes/MyClass.cls\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_ok "$ret" "[files] 存在するパス → 正常終了"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# [files] セクション: 存在しないパス → エラー終了・行番号付きメッセージ
# ------------------------------------------------------------------------------
test_files_missing_path() {
    local td
    td=$(setup_force_dir)

    local deploy="$td/deploy.txt"
    printf '[files]\nforce-app/main/default/classes/Missing.cls\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_fail "$ret" "[files] 存在しないパス → エラー終了"
    echo "$out" | grep -q ":2" \
        && pass "[files] 存在しないパス → 行番号が表示された" \
        || fail "[files] 存在しないパス → 行番号が表示された"
    echo "$out" | grep -q "Missing.cls" \
        && pass "[files] 存在しないパス → ファイル名が表示された" \
        || fail "[files] 存在しないパス → ファイル名が表示された"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# [members] セクション: 正しい書式（種別:名前） → 正常終了
# ------------------------------------------------------------------------------
test_members_valid_format() {
    local td
    td=$(setup_force_dir)

    local deploy="$td/deploy.txt"
    printf '[members]\nCustomLabel:MyLabel\nProfile:Admin\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_ok "$ret" "[members] 正しい書式 → 正常終了"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# [members] セクション: コロンなし → エラー終了・行番号付きメッセージ
# ------------------------------------------------------------------------------
test_members_invalid_format() {
    local td
    td=$(setup_force_dir)

    local deploy="$td/deploy.txt"
    printf '[members]\nCustomLabelMyLabel\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_fail "$ret" "[members] コロンなし → エラー終了"
    echo "$out" | grep -q ":2" \
        && pass "[members] コロンなし → 行番号が表示された" \
        || fail "[members] コロンなし → 行番号が表示された"
    echo "$out" | grep -q "書式エラー（種別名:メンバー名）" \
        && pass "[members] コロンなし → 書式エラーメッセージが表示された" \
        || fail "[members] コロンなし → 書式エラーメッセージが表示された"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# [files]/[members] マーカーのみ・コメントのみ → 正常終了（エラーなし）
# ------------------------------------------------------------------------------
test_markers_only_no_error() {
    local td
    td=$(setup_force_dir)

    local deploy="$td/deploy.txt"
    printf '[files]\n# コメント\n\n[members]\n# コメント\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_ok "$ret" "[files]/[members] マーカーのみ → エラーなし"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# ファイルが存在しない → スキップして正常終了
# ------------------------------------------------------------------------------
test_file_not_exists() {
    local td
    td=$(setup_force_dir)

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$td/no-deploy.txt" "$td/no-remove.txt" 2>&1)
    local ret=$?

    assert_exit_ok "$ret" "ファイルが存在しない → スキップして正常終了"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# 引数省略: branch_name.txt から自動解決 → 正常終了
# ------------------------------------------------------------------------------
test_auto_resolve_branch() {
    local td
    td=$(setup_force_dir)
    setup_release_dir "$td"
    # setup_release_dir が作る deploy-target.txt は存在しないパスを参照するため
    # 空ファイルに差し替え
    printf '[files]\n' > "$td/sf-tools/release/feature/test/deploy-target.txt"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" 2>&1)
    local ret=$?

    assert_exit_ok "$ret" "引数省略 → branch_name.txt から自動解決して正常終了"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# テストクラス不足: 通常 Apex のみで対応テストクラスがローカルに存在する → WARNING
# ------------------------------------------------------------------------------
test_missing_test_class_warning() {
    local td
    td=$(setup_force_dir)
    mkdir -p "$td/force-app/main/default/classes"
    printf 'public class MyClass {}\n' \
        > "$td/force-app/main/default/classes/MyClass.cls"
    printf '@isTest\npublic class MyClassTest {}\n' \
        > "$td/force-app/main/default/classes/MyClassTest.cls"

    local deploy="$td/deploy.txt"
    printf '[files]\nforce-app/main/default/classes/MyClass.cls\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_ok  "$ret" "テストクラス不足 → exit 0（warning のみ）"
    echo "$out" | grep -qi "warning" \
        && pass "テストクラス不足 → warning が表示された" \
        || fail "テストクラス不足 → warning が表示された"
    echo "$out" | grep -q "MyClassTest" \
        && pass "テストクラス不足 → テストクラス名が表示された" \
        || fail "テストクラス不足 → テストクラス名が表示された"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# テストクラス不足: テストクラスが deploy-target.txt に含まれている → WARNING なし
# ------------------------------------------------------------------------------
test_no_warning_when_test_included() {
    local td
    td=$(setup_force_dir)
    mkdir -p "$td/force-app/main/default/classes"
    printf 'public class MyClass {}\n' \
        > "$td/force-app/main/default/classes/MyClass.cls"
    printf '@isTest\npublic class MyClassTest {}\n' \
        > "$td/force-app/main/default/classes/MyClassTest.cls"

    local deploy="$td/deploy.txt"
    printf '[files]\nforce-app/main/default/classes/MyClass.cls\nforce-app/main/default/classes/MyClassTest.cls\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_ok "$ret" "テストクラス含まれている → exit 0"
    echo "$out" | grep -qi "テストクラス不足の可能性" \
        && fail "テストクラス含まれている → warning なし" \
        || pass "テストクラス含まれている → warning なし"
    teardown "$td"
}

# ------------------------------------------------------------------------------
# テストクラス不足: @isTest クラス自身のみ → WARNING なし
# ------------------------------------------------------------------------------
test_no_warning_for_test_class_itself() {
    local td
    td=$(setup_force_dir)
    mkdir -p "$td/force-app/main/default/classes"
    printf '@isTest\npublic class MyClassTest {}\n' \
        > "$td/force-app/main/default/classes/MyClassTest.cls"

    local deploy="$td/deploy.txt"
    printf '[files]\nforce-app/main/default/classes/MyClassTest.cls\n' > "$deploy"
    local remove="$td/remove.txt"
    printf '[files]\n' > "$remove"

    local out; out=$(cd "$td" && bash "$SF_TOOLS_DIR/bin/sf-check.sh" "$deploy" "$remove" 2>&1)
    local ret=$?

    assert_exit_ok "$ret" "@isTest クラス自身 → exit 0"
    echo "$out" | grep -qi "テストクラス不足の可能性" \
        && fail "@isTest クラス自身 → warning なし" \
        || pass "@isTest クラス自身 → warning なし"
    teardown "$td"
}

test_files_valid_path
test_files_missing_path
test_members_valid_format
test_members_invalid_format
test_markers_only_no_error
test_file_not_exists
test_auto_resolve_branch
test_missing_test_class_warning
test_no_warning_when_test_included
test_no_warning_for_test_class_itself

print_summary
