#!/bin/bash
# ==============================================================================
# test_repo-settings.sh - repo-settings.sh とワークフローの整合性テスト
#
# ワークフロー job name と repo-settings.sh の required_status_checks context が
# 一致しているかを検証する。不一致があると PR の必須チェックが永遠に待機状態になる。
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== repo-settings.sh ===${CLR_RST}"

REUSABLE_DIR="$SF_TOOLS_DIR/.github/workflows"
REPO_SETTINGS="$SF_TOOLS_DIR/repo-settings.sh"

# repo-settings.sh から context 値を抽出する内部関数
_extract_contexts() {
    grep '"context":' "$REPO_SETTINGS" \
        | sed 's/.*"context": "\([^"]*\)".*/\1/' \
        | sort -u
}

# リユーザブル WF から GitHub が生成する context 名（<caller_key> / <job_name>）を構築する内部関数
# caller_key はリユーザブル WF のファイル名から導出: wf-validate-reusable.yml → validate
_extract_job_names() {
    for f in "$REUSABLE_DIR"/wf-*-reusable.yml; do
        local key
        key=$(basename "$f" | sed 's/^wf-//' | sed 's/-reusable\.yml$//')
        grep '^    name:' "$f" | sed "s/^    name: /${key} \/ /"
    done | sort -u
}

# ------------------------------------------------------------------------------
# repo-settings.sh の context がワークフロー job name に存在するか
# ------------------------------------------------------------------------------
test_contexts_exist_in_workflow_job_names() {
    local contexts job_names
    contexts=$(_extract_contexts)
    job_names=$(_extract_job_names)

    while IFS= read -r context; do
        [[ -z "$context" ]] && continue
        if echo "$job_names" | grep -qF "$context"; then
            pass "context '${context}' がワークフロー job name に存在する"
        else
            fail "context '${context}' がワークフロー job name に存在しない" \
                "repo-settings.sh と .github/workflows/wf-*-reusable.yml の不一致"
        fi
    done <<< "$contexts"
}

# ------------------------------------------------------------------------------
# wf-validate-reusable.yml の job name が repo-settings.sh の context に登録されているか
# ------------------------------------------------------------------------------
test_wf_validate_job_registered_in_contexts() {
    local job_name full_context
    job_name=$(grep '^    name:' "$REUSABLE_DIR/wf-validate-reusable.yml" \
        | grep -v "対象ファイル確認" | head -1 | sed 's/^    name: //')
    full_context="validate / ${job_name}"

    if grep -qF "\"${full_context}\"" "$REPO_SETTINGS"; then
        pass "wf-validate-reusable.yml の job name が repo-settings.sh の context に登録されている"
    else
        fail "wf-validate-reusable.yml の job name が repo-settings.sh の context に未登録" \
            "context: '${full_context}'"
    fi
}

# ------------------------------------------------------------------------------
# wf-sequence-reusable.yml の job name が repo-settings.sh の context に登録されているか
# ------------------------------------------------------------------------------
test_wf_sequence_job_registered_in_contexts() {
    local job_name full_context
    job_name=$(grep '^    name:' "$REUSABLE_DIR/wf-sequence-reusable.yml" \
        | grep -v "対象ファイル確認" | head -1 | sed 's/^    name: //')
    full_context="sequence / ${job_name}"

    if grep -qF "\"${full_context}\"" "$REPO_SETTINGS"; then
        pass "wf-sequence-reusable.yml の job name が repo-settings.sh の context に登録されている"
    else
        fail "wf-sequence-reusable.yml の job name が repo-settings.sh の context に未登録" \
            "context: '${full_context}'"
    fi
}

# テスト実行
test_contexts_exist_in_workflow_job_names
test_wf_validate_job_registered_in_contexts
test_wf_sequence_job_registered_in_contexts
