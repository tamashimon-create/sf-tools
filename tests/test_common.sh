#!/bin/bash
# ==============================================================================
# test_common.sh - lib/common.sh の共通関数テスト
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== common.sh ===${CLR_RST}"

# check_authorized_user / check_admin_user は廃止済み。
# 権限チェックは警告ボックス + ask_yn に置き換えられたため、テストなし。

print_summary
