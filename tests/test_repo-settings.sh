#!/bin/bash
# ==============================================================================
# test_repo-settings.sh - repo-settings.sh とワークフローの整合性テスト
#
# ワークフロー job name と repo-settings.sh の required_status_checks context が
# 一致しているかを検証する。不一致があると PR の必須チェックが永遠に待機状態になる。
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/test_helper.sh"
echo -e "${CLR_HEAD}=== repo-settings.sh ===${CLR_RST}"

WORKFLOWS_DIR="$SF_TOOLS_DIR/templates/.github/workflows"
REPO_SETTINGS="$SF_TOOLS_DIR/repo-settings.sh"

# repo-settings.sh から context 値を抽出する内部関数
_extract_contexts() {
    grep '"context":' "$REPO_SETTINGS" \
        | sed 's/.*"context": "\([^"]*\)".*/\1/' \
        | sort -u
}

# ワークフロー yml から job name を抽出する内部関数（4スペースインデントの name: 行）
# 内部チェックジョブ（"デプロイ対象ブランチを確認"）は required_status_checks 対象外のため除外する
_extract_job_names() {
    grep -h '^    name:' "$WORKFLOWS_DIR"/*.yml \
        | sed 's/^    name: //' \
        | grep -v "デプロイ対象ブランチを確認" \
        | sort -u
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
                "repo-settings.sh と templates/.github/workflows/ の不一致"
        fi
    done <<< "$contexts"
}

# ------------------------------------------------------------------------------
# wf-validate.yml の job name が repo-settings.sh の context に登録されているか
# ------------------------------------------------------------------------------
test_wf_validate_job_registered_in_contexts() {
    local job_name
    job_name=$(grep '^    name:' "$WORKFLOWS_DIR/wf-validate.yml" \
        | grep -v "デプロイ対象ブランチを確認" \
        | grep -v "対象ファイル確認" | head -1 | sed 's/^    name: //')

    if grep -qF "\"${job_name}\"" "$REPO_SETTINGS"; then
        pass "wf-validate.yml の job name が repo-settings.sh の context に登録されている"
    else
        fail "wf-validate.yml の job name が repo-settings.sh の context に未登録" \
            "job name: '${job_name}'"
    fi
}

# ------------------------------------------------------------------------------
# wf-sequence.yml の job name が repo-settings.sh の context に登録されているか
# ------------------------------------------------------------------------------
test_wf_sequence_job_registered_in_contexts() {
    local job_name
    job_name=$(grep '^    name:' "$WORKFLOWS_DIR/wf-sequence.yml" \
        | grep -v "デプロイ対象ブランチを確認" \
        | grep -v "対象ファイル確認" | head -1 | sed 's/^    name: //')

    if grep -qF "\"${job_name}\"" "$REPO_SETTINGS"; then
        pass "wf-sequence.yml の job name が repo-settings.sh の context に登録されている"
    else
        fail "wf-sequence.yml の job name が repo-settings.sh の context に未登録" \
            "job name: '${job_name}'"
    fi
}

# テスト実行
test_contexts_exist_in_workflow_job_names
test_wf_validate_job_registered_in_contexts
test_wf_sequence_job_registered_in_contexts
