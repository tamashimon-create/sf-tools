#!/bin/bash
# ==============================================================================
# test_sf-metasync.sh - sf-metasync.sh のテスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== sf-metasync.sh ===${CLR_RST}"

# 変更あり → commit と push が実行される
test_changes_are_committed() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    create_all_mocks "$mb"

    # diff-index が 1 を返す（未コミット変更あり）→ stash 実行
    # diff-index が 0 を返す（ステージ後に変化なし）→ RET_NO_CHANGE を避けるため 1 を返す
    export MOCK_GIT_DIFF_EXIT=1
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-metasync.sh" 2>&1)
    local ec=$?

    assert_file_contains "$MOCK_CALL_LOG" "git commit" "変更あり → commit が実行された"
    assert_file_contains "$MOCK_CALL_LOG" "git push" "変更あり → push が実行された"
    unset MOCK_GIT_DIFF_EXIT MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# 変更なし → commit されずに正常終了
test_no_changes() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    create_all_mocks "$mb"

    # diff-index が 0 を返す（変更なし）
    export MOCK_GIT_DIFF_EXIT=0
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-metasync.sh" 2>&1)
    local ec=$?

    assert_exit_ok $ec "変更なし → 正常終了"
    ! grep -q "git commit" "$MOCK_CALL_LOG" 2>/dev/null \
        && pass "変更なし → commit は実行されない" \
        || fail "変更なし → commit は実行されない"
    unset MOCK_GIT_DIFF_EXIT MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# main 以外のブランチ → 下流伝播がスキップされる
test_non_main_skips_propagation() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)
    create_all_mocks "$mb"

    export MOCK_GIT_BRANCH="feature/test"
    export MOCK_GIT_DIFF_EXIT=0
    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'

    local out; out=$(cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-metasync.sh" 2>&1)

    echo "$out" | grep -q "伝播スキップ" \
        && pass "main 以外 → 伝播スキップメッセージが表示された" \
        || fail "main 以外 → 伝播スキップメッセージが表示された"
    ! grep -q "git-merge-arg:" "$MOCK_CALL_LOG" 2>/dev/null \
        && pass "main 以外 → merge が実行されない" \
        || fail "main 以外 → merge が実行されない"
    unset MOCK_GIT_BRANCH MOCK_GIT_DIFF_EXIT MOCK_SF_ORG_JSON
    teardown "$td" "$mb"
}

# staging チェックアウト失敗 → development は main からマージする（prev_branch バグ修正確認）
test_staging_fail_dev_merges_main() {
    local td mb
    td=$(setup_force_dir); mb=$(setup_mock_bin)

    # git モックをカスタマイズ（staging チェックアウトのみ失敗）
    cat > "$mb/git" << 'EOF'
#!/bin/bash
echo "git $*" >> "${MOCK_CALL_LOG:-/dev/null}"
case "$1" in
    symbolic-ref)   echo "main"; exit 0 ;;
    -C)             case "$3" in pull) exit 0 ;; *) exit 0 ;; esac ;;
    checkout)
        if [[ "$2" == "staging" ]]; then exit 1; fi
        exit 0 ;;
    merge)
        echo "git-merge-arg: $2" >> "${MOCK_CALL_LOG:-/dev/null}"
        exit 0 ;;
    ls-remote)      exit 0 ;;
    diff-index)     exit 0 ;;
    *)              exit 0 ;;
esac
EOF
    chmod +x "$mb/git"
    create_mock_sf "$mb"
    create_mock_npm "$mb"
    create_mock_code "$mb"

    export MOCK_SF_ORG_JSON='{"result":{"alias":"testorg","id":"00D000000000001AAA"}}'
    export MOCK_GIT_DIFF_EXIT=0

    cd "$td" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-metasync.sh" 2>&1 >/dev/null

    # development のマージ元が "main" であることを確認（staging ではない）
    assert_file_contains "$MOCK_CALL_LOG" "git-merge-arg: main" "staging 失敗後、development は main からマージした"
    ! grep -q "git-merge-arg: staging" "$MOCK_CALL_LOG" 2>/dev/null \
        && pass "staging からのマージは実行されない" \
        || fail "staging からのマージは実行されない"
    unset MOCK_SF_ORG_JSON MOCK_GIT_DIFF_EXIT
    teardown "$td" "$mb"
}

# force-* 以外で実行 → エラー
test_outside_force_dir() {
    local rd mb
    rd=$(setup_regular_dir); mb=$(setup_mock_bin)
    create_all_mocks "$mb"

    local out; out=$(cd "$rd" && PATH="$mb:$PATH" bash "$SF_TOOLS_DIR/sf-metasync.sh" 2>&1)
    local ec=$?

    assert_exit_fail $ec "force-* 外 → エラー終了"
    teardown "$rd" "$mb"
}

test_changes_are_committed
test_no_changes
test_non_main_skips_propagation
test_staging_fail_dev_merges_main
test_outside_force_dir

print_summary
