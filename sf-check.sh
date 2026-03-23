#!/bin/bash

# ==============================================================================
# sf-check.sh - デプロイターゲットファイル構文チェッカー
# ==============================================================================
# deploy-target.txt / remove-target.txt の構文を検証します。
# sf-release.sh から自動呼び出しされますが、単体実行も可能です。
#
# 【使い方】
#   sf-check.sh [deploy-target.txt] [remove-target.txt]
#   引数省略時は sf-tools/release/<branch>/ 配下を自動解決します。
#
# 【チェック内容】
#   - [files]   セクション: パスがリポジトリ内に存在するか
#   - [members] セクション: 「種別名:メンバー名」形式になっているか
#
# 【終了コード】
#   0: エラーなし
#   1: 構文エラーあり
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="APPEND"

# ------------------------------------------------------------------------------
# 2. 共通ライブラリの読み込み
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

# ------------------------------------------------------------------------------
# 3. ターゲットファイルの解決
# ------------------------------------------------------------------------------
if [[ $# -ge 2 ]]; then
    DEPLOY_LIST="$1"
    REMOVE_LIST="$2"
elif [[ $# -eq 1 ]]; then
    DEPLOY_LIST="$1"
    REMOVE_LIST=""
else
    # 引数省略時: sf-tools/release/branch_name.txt から自動解決
    BRANCH_NAME_FILE="sf-tools/release/branch_name.txt"
    if [[ ! -f "$BRANCH_NAME_FILE" ]]; then
        log "INFO" "ブランチ情報ファイルが見つかりません。構文チェックをスキップします。(${BRANCH_NAME_FILE})"
        exit 0
    fi
    BRANCH_NAME=$(tr -d '\r\n' < "$BRANCH_NAME_FILE")
    DEPLOY_LIST="sf-tools/release/${BRANCH_NAME}/deploy-target.txt"
    REMOVE_LIST="sf-tools/release/${BRANCH_NAME}/remove-target.txt"
fi

# ------------------------------------------------------------------------------
# 4. GCC/Clang スタイルエラー出力関数
# ------------------------------------------------------------------------------

# GCC/Clang スタイルでエラーを表示する
# 引数: $1 = ファイル名, $2 = 行番号, $3 = 行内容, $4 = エラーメッセージ
print_gcc_error() {
    local file="$1" lineno="$2" content="$3" message="$4"
    printf "  ${CLR_INFO}%s:%s:${CLR_RESET} ${CLR_ERR}error:${CLR_RESET} %s\n" "$file" "$lineno" "$message"
    printf "    ${CLR_WARNING}→${CLR_RESET} %s\n" "$content"
}

# ------------------------------------------------------------------------------
# 5. チェック関数
# ------------------------------------------------------------------------------

# ターゲットファイルの構文チェック
# 引数: $1 = ファイルパス, $2 = ファイル種別ラベル
check_target_file() {
    local file="$1"
    local label="$2"
    local error_count=0
    local entry_count=0
    local section="files"
    local lineno=0

    if [[ ! -f "$file" ]]; then
        log "INFO" "${label}: ファイルが存在しません。スキップします。(${file})"
        return 0
    fi

    log "INFO" "${label} を検証します: ${file}"

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$(( lineno + 1 ))

        # \r 除去・前後空白トリム
        local clean
        clean="${line//$'\r'/}"
        clean="${clean#"${clean%%[^[:space:]]*}"}"
        clean="${clean%"${clean##*[^[:space:]]}"}"

        # 空行・コメント行はスキップ
        [[ -z "$clean" || "$clean" == \#* ]] && continue

        # セクションマーカー
        if [[ "$clean" == "[files]" ]]; then
            section="files"; continue
        elif [[ "$clean" == "[members]" ]]; then
            section="members"; continue
        fi

        entry_count=$(( entry_count + 1 ))

        if [[ "$section" == "files" ]]; then
            # [files]: パスがリポジトリ内に存在するか
            if [[ ! -e "$clean" ]]; then
                print_gcc_error "$label" "$lineno" "$clean" "パスが存在しません"
                error_count=$(( error_count + 1 ))
            fi
        else
            # [members]: 「種別名:メンバー名」形式チェック
            if [[ "$clean" != *:* ]]; then
                print_gcc_error "$label" "$lineno" "$clean" "書式エラー（種別名:メンバー名）"
                error_count=$(( error_count + 1 ))
            fi
        fi
    done < "$file"

    if [[ "$entry_count" -eq 0 ]]; then
        log "WARNING" "${label}: 何も書かれていません。"
        return 0
    fi

    if [[ "$error_count" -eq 0 ]]; then
        log "SUCCESS" "${label}: 問題なし。"
    fi

    return "$error_count"
}

# ------------------------------------------------------------------------------
# 6. メイン処理
# ------------------------------------------------------------------------------
log "HEADER" "デプロイターゲットファイルを検証します (${SCRIPT_NAME}.sh)"

deploy_errors=0
remove_errors=0

check_target_file "$DEPLOY_LIST" "deploy-target.txt" || deploy_errors=$?
check_target_file "$REMOVE_LIST" "remove-target.txt"  || remove_errors=$?

total_errors=$(( deploy_errors + remove_errors ))

if [[ "$total_errors" -gt 0 ]]; then
    printf "\n${CLR_ERR}error${CLR_RESET}: %s 件のエラーが検出されました。deploy-target.txt / remove-target.txt を修正してください。\n\n" "$total_errors"
    exit 1
fi

log "SUCCESS" "構文チェック完了。問題はありませんでした。"
exit 0
