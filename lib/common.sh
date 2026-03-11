#!/bin/bash
# ==============================================================================
# common.sh - sf-tools 共通関数ライブラリ (標準色CMD・マゼンタPROMPT版)
# ------------------------------------------------------------------------------
# 【処理概要】
#   ログ出力、コマンド実行、エラー停止などの基本機能を全スクリプトへ提供します。
#   画面出力はアイコン付きの色付きメッセージで視認性を高め、ログファイルには
#   詳細な実行履歴をプレーンテキストで記録します。
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 状態定数
# ------------------------------------------------------------------------------
readonly RET_OK=0           # 正常終了
readonly RET_NG=1           # 異常終了
readonly RET_NO_CHANGE=2    # 変更なし

# ------------------------------------------------------------------------------
# 2. 必須変数のバリデーションとログ初期化
# ------------------------------------------------------------------------------
if [[ -z "${LOG_FILE:-}" ]]; then
    echo "❌ [FATAL ERROR] LOG_FILE が未定義です。source 前に定義してください。" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
[[ "${LOG_MODE:-}" == "NEW" ]] && : > "$LOG_FILE"

# ------------------------------------------------------------------------------
# 3. カラー定義 (CMDは標準色、PROMPTはマゼンタ)
# ------------------------------------------------------------------------------
CLR_INFO='\033[36m'     # シアン (情報・進行中) 
CLR_SUCCESS='\033[32m'  # グリーン (成功・完了) 
CLR_WARNING='\033[33m'  # イエロー (警告) 
CLR_ERR='\033[31m'      # レッド (エラー) 
CLR_PROMPT='\033[35m'   # マゼンタ (入力要求用)
CLR_RESET='\033[0m'     # リセット 

# ------------------------------------------------------------------------------
# 4. log - 記録と表示の統合管理
# ------------------------------------------------------------------------------
# 【引数解説】
#   $1 (level)   : ログレベル (HEADER / INFO / SUCCESS / WARNING / ERROR / CMD)
#   $2 (stage)   : フェーズ名。空文字 "" で [ ] を省略。
#   $3 (message) : 出力メッセージ本文。
# 【処理概要】
#   標準エラー出力に色付きで表示し、ログファイルには色なしで書き込みます。
#   CMDレベルはユーザーの希望に基づき、色指定なしの標準テキストで出力します。 
# ------------------------------------------------------------------------------
log() {
    local level="$1" stage="$2" message="$3" dest="${4:-BOTH}"
    local ts=$(date +'%Y-%m-%d %H:%M:%S')

    # A. ログファイル出力 (色コードなし)
    if [[ "$dest" == "BOTH" || "$dest" == "FILE" ]]; then
        if [[ "$level" == "HEADER" ]]; then
            printf "\n[%s] [=== %s ===]\n" "$ts" "$message" >> "$LOG_FILE"
        else
            printf "[%s] [%s] [%s] %s\n" "$ts" "$level" "${stage:-SYS}" "$message" >> "$LOG_FILE"
        fi
    fi

    # B. 画面出力 (アイコンとメッセージの色をセットで統一)
    if [[ "$dest" == "BOTH" || "$dest" == "SCREEN" ]]; then
        case "$level" in
            HEADER)
                echo "-------------------------------------------------------" >&2
                echo -e "${CLR_INFO}▣ ${message}${CLR_RESET}" >&2
                echo "-------------------------------------------------------" >&2 ;;
            INFO)
                echo -e "${CLR_INFO}[${level}][${stage}] ${message}${CLR_RESET}" >&2 ;;
            SUCCESS)
                echo -e "${CLR_SUCCESS}[${level}][${stage}] ${message}${CLR_RESET}" >&2 ;;
            WARNING)
                echo -e "${CLR_WARNING}[${level}][${stage}] ${message}${CLR_RESET}" >&2 ;;
            ERROR)
                echo -e "${CLR_ERR}[${stage}] ${message}${CLR_RESET}" >&2 ;;
            CMD)
                # コマンド出力は色なし（標準色） 
                echo "   > Command: ${message}" >&2 ;;
            *)
                echo -e "[${stage}] ${message}" >&2 ;;
        esac
    fi
    return $RET_OK
}

# ------------------------------------------------------------------------------
# 5. run - コマンド実行ラッパー
# ------------------------------------------------------------------------------
# 【処理概要】
#   コマンドを実行し、実行内容をログに記録します。
#   SILENT_EXEC=1 の場合は詳細出力を画面に表示しません。 
# ------------------------------------------------------------------------------
run_old() {
    local stage="$1"; shift
    local cmd=("$@")
    local tmp_out="./cmd_out_$$.tmp"

    log "CMD" "$stage" "${cmd[*]}"
    if [[ "${SILENT_EXEC:-}" == "1" ]]; then
        "${cmd[@]}" > "$tmp_out" 2>&1
    else
        "${cmd[@]}" 2>&1 | tee "$tmp_out"
    fi
    local status=$?

    local is_success=$RET_NG
    if [[ $status -eq 0 ]] || grep -qE "Success|successfully|Succeeded|Deployed|Successfully|status\": 0|nothing|up to date" "$tmp_out"; then
        is_success=$RET_OK
    fi

    cat "$tmp_out" >> "$LOG_FILE"
    rm -f "$tmp_out"
    return $is_success
}
run() {
    local stage="$1"; shift
    local cmd=("$@")
    local tmp_out="./cmd_out_$$.tmp"

    log "CMD" "$stage" "${cmd[*]}"
    if [[ "${SILENT_EXEC:-}" == "1" ]]; then
        "${cmd[@]}" > "$tmp_out" 2>&1
    else
        "${cmd[@]}" 2>&1 | tee "$tmp_out"
    fi
    local status=$?

    local is_success=$RET_NG
    # A. 変更なし（NothingToDeploy）の検知
    if grep -qE "NothingToDeploy|No local changes to deploy" "$tmp_out"; then
        log "INFO" "$stage" "デプロイ対象の変更がないためスキップされました。"
        is_success=$RET_NO_CHANGE
    # B. 成功判定
    elif [[ $status -eq 0 ]] || grep -qE "Success|successfully|Succeeded|Deployed|Successfully|status\": 0" "$tmp_out"; then
        is_success=$RET_OK
    fi

    cat "$tmp_out" >> "$LOG_FILE"
    rm -f "$tmp_out"
    return $is_success
}

# ------------------------------------------------------------------------------
# 6. die - 強制終了 / 7. ユーティリティ
# ------------------------------------------------------------------------------
die() {
    log "ERROR" "FATAL" "$1"
    exit "${2:-$RET_NG}"
}

get_target_org() {
    local target="$1"
    [[ -z "$target" ]] && target="$SF_TARGET_ORG"
    if [[ -z "$target" ]]; then
        local current_alias=$(sf org display --json 2>/dev/null | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
        [[ -n "$current_alias" && "$current_alias" != "null" ]] && target="$current_alias"
    fi
    [[ -z "$target" ]] && return $RET_NG
    echo "$target"
    return $RET_OK
}

check_force_dir() {
    [[ "$(basename "$PWD")" =~ ^force- ]] && return $RET_OK
    return $RET_NG
}