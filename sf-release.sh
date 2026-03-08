#!/bin/bash

# ==============================================================================
# プログラム名: sf-release.sh
# 概要: デプロイ対象のテキストリストからマニフェスト(XML)を自動生成し、
#       Salesforce組織へのリリース（または検証）を安全かつ確実に行うツール。
# 互換性: Windows (Git Bash), Mac (Zsh/Bash), Linux (Bash) 完全対応
#
# 【実行時オプション】
#   (デフォルト動作) : 何も指定しない場合、最も安全な「検証モード(Dry-Run)」で実行され、
#                      確認のために自動でブラウザ（リリース状況画面）を開きます。
#
#   -r, --release    : 検証ではなく、実際に組織への【本番リリース】を実行します。
#   -n, --no-open    : ブラウザを開かずにバックグラウンドで実行します。
#   -f, --force      : コンフリクト検知を無効化し、強制上書き(--ignore-conflicts)します。
#   -j, --json       : sfコマンドの出力をJSON形式にします（CI/CDの機械読み取り用）。
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. 共通の初期処理
# ------------------------------------------------------------------------------
# カラー定義
if [ -t 1 ]; then
    readonly CLR_INFO='\033[36m'
    readonly CLR_SUCCESS='\033[32m'
    readonly CLR_ERR='\033[31m'
    readonly CLR_PROMPT='\033[33m'
    readonly CLR_RESET='\033[0m'
else
    readonly CLR_INFO=''; readonly CLR_SUCCESS=''; readonly CLR_ERR=''; readonly CLR_PROMPT=''; readonly CLR_RESET=''
fi

echo "======================================================="
echo -e "${CLR_INFO}📦 リリース・検証処理を開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# 【安全性】スクリプト終了時（異常終了やCtrl+Cによる中断も含む）に、
# プロセスID($$)が付与された一時ファイルを確実に削除し、ディレクトリを汚さないようにする
trap 'rm -f ./cmd_output_$$.tmp ./cmd_exit_$$.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 1. 共通設定 と 実行時引数の解析
# ------------------------------------------------------------------------------
# 接続先のSalesforce組織（sf org list で確認できるエイリアス）
readonly TARGET_ORG="tama"

# 現在のGitブランチ名を自動取得（取得できない場合は unknown-branch とする）
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$BRANCH_NAME" ]; then
    BRANCH_NAME="unknown-branch"
fi

# 各種パスの定義
readonly RELEASE_BASE="release"
readonly RELEASE_DIR="${RELEASE_BASE}/${BRANCH_NAME}"
# デプロイ・削除リストの雛形は、共通ツールリポジトリから参照する
readonly TEMPLATE_DEPLOY="$HOME/sf-tools/templates/deploy-template.txt"
readonly TEMPLATE_REMOVE="$HOME/sf-tools/templates/remove-template.txt"
readonly DEPLOY_LIST="${RELEASE_DIR}/deploy-target.txt"
readonly REMOVE_LIST="${RELEASE_DIR}/remove-target.txt"
readonly DEPLOY_XML="${RELEASE_DIR}/package.xml"
readonly REMOVE_XML="${RELEASE_DIR}/destructiveChanges.xml"
# ログファイルは専用の logs フォルダに集約する
readonly LOG_FILE="./logs/sf-release.log"

# ターミナル出力用のカラー装飾定義（環境に応じて自動切替）
if [ -t 2 ]; then
    # 本物のターミナル(Git Bash等)で実行されている場合は色をつける
    readonly CLR_INFO='\033[36m'
    readonly CLR_SUCCESS='\033[32m'
    readonly CLR_ERR='\033[31m'
    readonly CLR_CMD='\033[34m'
    readonly CLR_RESET='\033[0m'
else
    # TortoiseGitなどのGUIツールやパイプ処理時は色をつけない（文字化け防止）
    readonly CLR_INFO=''
    readonly CLR_SUCCESS=''
    readonly CLR_ERR=''
    readonly CLR_CMD=''
    readonly CLR_RESET=''
fi

# 【重要】デフォルト値を「安全側（検証する＆ブラウザを開く）」に設定
IS_VALIDATE_MODE=1
OPEN_BROWSER=1
IGNORE_CONFLICTS=0
OUTPUT_JSON=0

# 実行時引数（オプション）の自作解析エンジン（-r, -n, -f, -j などに対応）
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --release) IS_VALIDATE_MODE=0 ;;
        --no-open) OPEN_BROWSER=0 ;;
        --force)   IGNORE_CONFLICTS=1 ;;
        --json)    OUTPUT_JSON=1 ;;
        --*)
            echo -e "${CLR_ERR}❌ [INIT]${CLR_RESET} 不明なオプションです: $1" >&2
            exit 1
            ;;
        -[a-zA-Z]*)
            flags="${1#-}"
            for (( i=0; i<${#flags}; i++ )); do
                case "${flags:$i:1}" in
                    r) IS_VALIDATE_MODE=0 ;; # rを指定すると検証モードが解除(0)される
                    n) OPEN_BROWSER=0 ;;   # nを指定するとブラウザ起動が解除(0)される
                    f) IGNORE_CONFLICTS=1 ;;
                    j) OUTPUT_JSON=1 ;;
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
# 2. 共通エンジン（ログ管理とコマンド実行制御）
# ------------------------------------------------------------------------------
# ログ出力先ディレクトリが存在しない場合は自動作成し、ログを空にする
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

# 進行状況の出力（人間向けのメッセージは標準エラー出力 >&2 へ逃がす）
log() {
    local level=$1 stage=$2 message=$3
    local ts=$(date +'%Y-%m-%d %H:%M:%S')

    # ファイルにはすべての情報を記録
    printf "[%s] [%s] [%s] %s\n" "$ts" "$level" "$stage" "$message" >> "$LOG_FILE"

    # 画面（コンソール）出力時はカラー装飾付きで出力
    case "$level" in
        "INFO")    echo -e "${CLR_INFO}▶️  [$stage]${CLR_RESET} $message" >&2 ;;
        "SUCCESS") echo -e "${CLR_SUCCESS}✅ [$stage]${CLR_RESET} $message" >&2 ;;
        "ERROR")   echo -e "${CLR_ERR}❌ [$stage]${CLR_RESET} $message" >&2 ;;
        "CMD")     echo -e "${CLR_CMD}   > Command:${CLR_RESET} $message" >&2 ;;
    esac
}

# 全コマンドの実行管理（JSONモードの自動付与と、エラーコードの救済処理）
exec_wrapper() {
    local stage=$1; shift
    local cmd=("$@")
    local tmp_out="./cmd_output_$$.tmp"
    local tmp_exit="./cmd_exit_$$.tmp"

    # --json オプション指定時は自動的に付与
    if [ "$OUTPUT_JSON" -eq 1 ] && [ "${cmd[0]}" == "sf" ]; then
        cmd+=("--json")
    fi

    log "CMD" "$stage" "${cmd[*]}"

    # 出力をファイルに保存しつつ画面にも表示。終了コードは tmp_exit に記録
    ( "${cmd[@]}" 2>&1 ; echo $? > "$tmp_exit" ) | tee "$tmp_out"
    
    local status=$(cat "$tmp_exit" 2>/dev/null || echo 1)
    rm -f "$tmp_exit"

    local is_success=0
    # フェイルセーフ：SFDX CLI特有の「成功しているのに終了コード1を返す」バグを救済
    if [ "$status" -eq 0 ]; then
        is_success=1
    elif grep -qE "successfully wrote|Status: Succeeded|Deployed Source|Successfully deployed|\"status\": 0" "$tmp_out"; then
        is_success=1
        echo "Notice: Non-zero exit code ($status) detected, keyword found. SUCCESS." >> "$LOG_FILE"
    fi

    # 実行結果をログファイルへ追記
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

# フェーズ1: 対象リストの準備（雛形がなければコピーしてくる）
phase_check_target() {
    local created=0
    mkdir -p "$RELEASE_DIR"

    # deploy と remove の2つのリストをチェック
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

    # 新規作成された場合は、リストを埋めてもらうために一度停止する
    if [ $created -eq 1 ]; then
        log "ERROR" "CHECK" "雛形から作成しました。リストを埋めて再実行してください。"
        return 1
    fi
    return 0
}

# フェーズ2: テキストリストから package.xml 等を自動生成する
phase_generate_manifest() {
    rm -f "$DEPLOY_XML" "$REMOVE_XML"
    local deploy_args=()
    local remove_args=()

    # リストファイルをパースし、有効なパスを配列に格納する内部関数
    process_list() {
        local list=$1; shift
        local -n ref=$1
        while IFS= read -r line || [ -n "$line" ]; do
            # CRLFの除去と前後の空白トリム
            clean_line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            # 空行およびコメント(#)行は無視
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

    # 追加/更新（Deploy）用XMLの生成
    if [ ${#deploy_args[@]} -gt 0 ]; then
        log "INFO" "MANIFEST" "対象（${#deploy_args[@]}件）を検知"
        exec_wrapper "MANIFEST" sf project generate manifest "${deploy_args[@]}" --output-dir "$RELEASE_DIR" --name "package.xml" || return 1
    else
        # 対象がない場合は空のXMLを作成（SFDXのエラー回避）
        echo '<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>60.0</version></Package>' > "$DEPLOY_XML"
    fi

    # 削除（Remove）用XMLの生成
    if [ ${#remove_args[@]} -gt 0 ]; then
        log "INFO" "MANIFEST" "削除（${#remove_args[@]}件）を検知"
        exec_wrapper "MANIFEST" sf project generate manifest "${remove_args[@]}" --output-dir "$RELEASE_DIR" --name "destructiveChanges.xml" || return 1
    fi
    return 0
}

# フェーズ3: コマンドの構築と Salesforce へのリリース（または検証）の実行
phase_release() {
    # 基本のデプロイコマンド
    local deploy_cmd=("sf" "project" "deploy" "start" "--target-org" "$TARGET_ORG" "--manifest" "$DEPLOY_XML")

    # 破壊的変更(削除)ファイルが存在すれば追加
    [ -f "$REMOVE_XML" ] && deploy_cmd+=("--pre-destructive-changes" "$REMOVE_XML")
    
    # オプション: 強制上書き
    [ "$IGNORE_CONFLICTS" -eq 1 ] && deploy_cmd+=("--ignore-conflicts")
    
    # 【最重要】デフォルトでは --dry-run (検証) を適用。-r 指定時のみ本番リリース。
    if [ "$IS_VALIDATE_MODE" -eq 1 ]; then
        log "INFO" "RELEASE" "🧪 検証モード (Dry-Run) で実行します"
        deploy_cmd+=("--dry-run")
    else
        log "INFO" "RELEASE" "🚨 本番環境へのリリースを実行します！"
    fi

    # 【重要】デフォルトではブラウザでリリース状況画面を開く。-n 指定時は開かない。
    if [ "$OPEN_BROWSER" -eq 1 ]; then
        log "INFO" "RELEASE" "🌐 リリース状況画面をブラウザで起動します..."
        # バックグラウンドでブラウザを開き、描画のためのウェイトを置く
        sf org open --target-org "$TARGET_ORG" --path "lightning/setup/DeployStatus/home" > /dev/null 2>&1 &
        log "INFO" "RELEASE" "⏳ 描画待機（5秒）"
        sleep 5
    fi

    # 構築したコマンド配列をラッパー関数に渡して実行
    exec_wrapper "RELEASE" "${deploy_cmd[@]}"
}

# ------------------------------------------------------------------------------
# 4. メインフロー制御
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------" >&2
log "INFO" "INIT" "リリース処理開始 (Branch: $BRANCH_NAME)"

# 各フェーズを順次実行し、失敗(return 1)した場合は即座に異常終了(exit 1)する
phase_check_target || exit 1
log "SUCCESS" "CHECK" "完了"

phase_generate_manifest || exit 1
log "SUCCESS" "MANIFEST" "完了"

phase_release || exit 1
log "SUCCESS" "RELEASE" "完了"

log "SUCCESS" "FINISH" "全工程 正常完了"
echo "-------------------------------------------------------" >&2
exit 0