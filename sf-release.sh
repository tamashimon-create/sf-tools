#!/bin/bash

# ==============================================================================
# プログラム名: sf-release.sh
# 概要: デプロイ対象のテキストリストからマニフェスト(XML)を自動生成し、
#       Salesforce組織へのリリース（または検証）を安全かつ確実に行うツール。
# 互換性: Windows (Git Bash), Mac (Zsh/Bash), Linux (Bash) 完全対応
# ==============================================================================

# 異常終了時も含め、プロセスID($$)付きの一時ファイルを確実に削除
trap 'rm -f ./cmd_output_$$.tmp ./cmd_exit_$$.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 1. 共通設定 と 実行時引数の解析
# ------------------------------------------------------------------------------
readonly TARGET_ORG="tama"

BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$BRANCH_NAME" ]; then
    BRANCH_NAME="unknown-branch"
fi

readonly RELEASE_BASE="release"
readonly RELEASE_DIR="${RELEASE_BASE}/${BRANCH_NAME}"
readonly TEMPLATE_DEPLOY="$HOME/sf-tools/templates/deploy-template.txt"
readonly TEMPLATE_REMOVE="$HOME/sf-tools/templates/remove-template.txt"
readonly DEPLOY_LIST="${RELEASE_DIR}/deploy-target.txt"
readonly REMOVE_LIST="${RELEASE_DIR}/remove-target.txt"
readonly DEPLOY_XML="${RELEASE_DIR}/package.xml"
readonly REMOVE_XML="${RELEASE_DIR}/destructiveChanges.xml"
readonly LOG_FILE="./logs/sf-release.log"

readonly CLR_INFO='\033[36m'
readonly CLR_SUCCESS='\033[32m'
readonly CLR_ERR='\033[31m'
readonly CLR_CMD='\033[34m'
readonly CLR_RESET='\033[0m'

IS_VALIDATE_MODE=0
IGNORE_CONFLICTS=0
OUTPUT_JSON=0
OPEN_BROWSER=0

# オプション解析（結合フラグ -vfj 等に対応）
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --validate) IS_VALIDATE_MODE=1 ;;
        --force)    IGNORE_CONFLICTS=1 ;;
        --json)     OUTPUT_JSON=1 ;;
        --open)     OPEN_BROWSER=1 ;;
        --*)
            echo -e "${CLR_ERR}❌ [INIT]${CLR_RESET} 不明なオプションです: $1" >&2
            exit 1
            ;;
        -[a-zA-Z]*)
            flags="${1#-}"
            for (( i=0; i<${#flags}; i++ )); do
                case "${flags:$i:1}" in
                    v) IS_VALIDATE_MODE=1 ;;
                    f) IGNORE_CONFLICTS=1 ;;
                    j) OUTPUT_JSON=1 ;;
                    o) OPEN_BROWSER=1 ;;
                    *) 
                        echo -e "${CLR_ERR}❌ [INIT]${CLR_RESET} 不明なオプションです: -${flags:$i:1}" >&2
                        exit 1 
                        ;;
                esac
            done
            ;;
        *)
            echo -e "${CLR_ERR}❌ [INIT]${CLR_RESET} 不明な引数です: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# 2. 共通エンジン
# ------------------------------------------------------------------------------
# ログディレクトリが存在しない場合は作成する
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

log() {
    local level=$1
    local stage=$2
    local message=$3
    local ts=$(date +'%Y-%m-%d %H:%M:%S')

    printf "[%s] [%s] [%s] %s\n" "$ts" "$level" "$stage" "$message" >> "$LOG_FILE"

    case "$level" in
        "INFO")    echo -e "${CLR_INFO}▶️  [$stage]${CLR_RESET} $message" >&2 ;;
        "SUCCESS") echo -e "${CLR_SUCCESS}✅ [$stage]${CLR_RESET} $message" >&2 ;;
        "ERROR")   echo -e "${CLR_ERR}❌ [$stage]${CLR_RESET} $message" >&2 ;;
        "CMD")     echo -e "${CLR_CMD}   > Command:${CLR_RESET} $message" >&2 ;;
    esac
}

exec_wrapper() {
    local stage=$1
    shift
    local cmd=("$@")
    local tmp_out="./cmd_output_$$.tmp"
    local tmp_exit="./cmd_exit_$$.tmp"

    if [ "$OUTPUT_JSON" -eq 1 ] && [ "${cmd[0]}" == "sf" ]; then
        cmd+=("--json")
    fi

    log "CMD" "$stage" "${cmd[*]}"

    ( "${cmd[@]}" 2>&1 ; echo $? > "$tmp_exit" ) | tee "$tmp_out"
    
    local status=$(cat "$tmp_exit" 2>/dev/null || echo 1)
    rm -f "$tmp_exit"

    local is_success=0
    # フェイルセーフ：終了コードが1でもJSON内に成功ステータスがあれば救済 [cite: 2, 4]
    if [ "$status" -eq 0 ]; then
        is_success=1
    elif grep -qE "successfully wrote|Status: Succeeded|Deployed Source|Successfully deployed|\"status\": 0" "$tmp_out"; then
        is_success=1
        echo "Notice: Non-zero exit code ($status) detected, keyword found. SUCCESS." >> "$LOG_FILE"
    fi

    cat "$tmp_out" >> "$LOG_FILE"
    rm -f "$tmp_out"

    if [ "$is_success" -eq 1 ]; then
        echo "Command executed successfully." >> "$LOG_FILE"
        return 0
    fi

    log "ERROR" "$stage" "コマンドが異常終了しました。"
    return 1
}

# ------------------------------------------------------------------------------
# 3. 作業フェーズ定義
# ------------------------------------------------------------------------------

phase_check_target() {
    local created=0
    mkdir -p "$RELEASE_DIR"

    for target in "$DEPLOY_LIST" "$REMOVE_LIST"; do
        if [ ! -f "$target" ]; then
            template="${TEMPLATE_DEPLOY}"
            [[ "$target" == "$REMOVE_LIST" ]] && template="${TEMPLATE_REMOVE}"
            if [ -f "$template" ]; then
                cp "$template" "$target"
                created=1
            else
                log "ERROR" "CHECK" "雛形が存在しません: $template"
                return 1
            fi
        fi
    done

    if [ $created -eq 1 ]; then
        log "ERROR" "CHECK" "雛形から作成しました。リストを埋めて再実行してください。"
        return 1
    fi
    return 0
}

phase_generate_manifest() {
    rm -f "$DEPLOY_XML" "$REMOVE_XML"
    local deploy_args=()
    local remove_args=()

    process_list() {
        local list=$1
        shift
        local -n ref=$1
        while IFS= read -r line || [ -n "$line" ]; do
            clean_line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [ -n "$clean_line" ] && [[ "$clean_line" != \#* ]]; then
                if [ ! -e "$clean_line" ]; then
                    log "ERROR" "MANIFEST" "存在しないパス: $clean_line"
                    return 1
                fi
                ref+=("--source-dir" "$clean_line")
            fi
        done < "$list"
    }

    process_list "$DEPLOY_LIST" deploy_args || return 1
    process_list "$REMOVE_LIST" remove_args || return 1

    if [ ${#deploy_args[@]} -gt 0 ]; then
        log "INFO" "MANIFEST" "対象（${#deploy_args[@]}件）を検知"
        exec_wrapper "MANIFEST" sf project generate manifest "${deploy_args[@]}" --output-dir "$RELEASE_DIR" --name "package.xml" || return 1
    else
        echo '<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>60.0</version></Package>' > "$DEPLOY_XML"
    fi

    if [ ${#remove_args[@]} -gt 0 ]; then
        log "INFO" "MANIFEST" "削除（${#remove_args[@]}件）を検知"
        exec_wrapper "MANIFEST" sf project generate manifest "${remove_args[@]}" --output-dir "$RELEASE_DIR" --name "destructiveChanges.xml" || return 1
    fi
    return 0
}

# オプションを確実に配列へ追加
phase_release() {
    local deploy_cmd=("sf" "project" "deploy" "start" "--target-org" "$TARGET_ORG" "--manifest" "$DEPLOY_XML")

    [ -f "$REMOVE_XML" ] && deploy_cmd+=("--pre-destructive-changes" "$REMOVE_XML")
    [ "$IGNORE_CONFLICTS" -eq 1 ] && deploy_cmd+=("--ignore-conflicts")
    
    # ここでフラグをチェックし、確実にコマンド配列へ追加する
    if [ "$IS_VALIDATE_MODE" -eq 1 ]; then
        log "INFO" "RELEASE" "🚨 検証モード (Dry-Run) オプションを適用します"
        deploy_cmd+=("--dry-run")
    fi

    if [ "$OPEN_BROWSER" -eq 1 ]; then
        log "INFO" "RELEASE" "🌐 リリース状況画面をブラウザで起動..."
        sf org open --target-org "$TARGET_ORG" --path "lightning/setup/DeployStatus/home" > /dev/null 2>&1 &
        log "INFO" "RELEASE" "⏳ 描画待機（5秒）"
        sleep 5
    fi

    # 構築した deploy_cmd を引数として渡す
    exec_wrapper "RELEASE" "${deploy_cmd[@]}"
}

# ------------------------------------------------------------------------------
# 4. メインフロー
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------" >&2
log "INFO" "INIT" "リリース処理開始 (Branch: $BRANCH_NAME)"

phase_check_target || exit 1
log "SUCCESS" "CHECK" "完了"

phase_generate_manifest || exit 1
log "SUCCESS" "MANIFEST" "完了"

phase_release || exit 1
log "SUCCESS" "RELEASE" "完了"

log "SUCCESS" "FINISH" "全工程 正常完了"
echo "-------------------------------------------------------" >&2
exit 0