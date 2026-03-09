#!/bin/bash

# ==============================================================================
# プログラム名: pre-push (実体)
# 設置場所: ~/sf-tools/hooks/pre-push
# プログラム名: pre-push.sh (フックの実体)
# 概要: Gitのpre-pushフックから呼び出され、sf-release.shを検証モードで実行する。
#       検証に失敗した場合、Pushを自動的に中断する。
# 設置場所: ~/sf-tools/hooks/
# 呼び出し元: .git/hooks/pre-push (ラッパースクリプト)
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

echo "=======================================================" >&2
echo -e "${CLR_INFO}▶️  [PRE-PUSH] Salesforce 組織への検証(Dry-Run)を自動開始します...${CLR_RESET}" >&2
echo "=======================================================" >&2

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}" >&2
    exit 1
fi

# sf-release.sh のパス（フック実体と同じ sf-tools 内にある前提）
# ログファイル定義
readonly LOG_FILE="./logs/sf-hooks.log"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

# ------------------------------------------------------------------------------
# 1. 共通エンジン (ログ出力)
# ------------------------------------------------------------------------------
# sf-release.sh と同じ形式のログ出力関数
log() {
    local level=$1 stage=$2 message=$3
    local ts=$(date +'%Y-%m-%d %H:%M:%S')
    printf "[%s] [%s] [%s] %s\n" "$ts" "$level" "$stage" "$message" >> "$LOG_FILE"
    case "$level" in
        "INFO")    echo -e "${CLR_INFO}▶️  [$stage]${CLR_RESET} $message" >&2 ;;
        "SUCCESS") echo -e "${CLR_SUCCESS}✅ [$stage]${CLR_RESET} $message" >&2 ;;
        "ERROR")   echo -e "${CLR_ERR}❌ [$stage]${CLR_RESET} $message" >&2 ;;
    esac
}

# ------------------------------------------------------------------------------
# 2. メイン処理
# ------------------------------------------------------------------------------
echo "=======================================================" >&2
log "INFO" "PRE-PUSH" "Salesforce 組織への検証(Dry-Run)を自動開始します..."
echo "=======================================================" >&2

# 検証スクリプト本体のパス
readonly SCRIPT_PATH="$HOME/sf-tools/sf-release.sh"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo -e "${CLR_ERR}❌ [PRE-PUSH] ツールが見つかりません: $SCRIPT_PATH ${CLR_RESET}" >&2
    log "ERROR" "PRE-PUSH" "ツールが見つかりません: $SCRIPT_PATH"
    exit 1
fi

# sf-release.sh を明示的に検証モードで実行
# 将来 sf-release.sh のデフォルト動作が変更されても、push時に意図せず本番リリースが走る事故を防ぐ
# sf-release.sh を明示的に検証モードで実行する
# 将来 sf-release.sh のデフォルト動作が変更されても、push時に意図せず本番リリースが走る事故を防ぐため
"$SCRIPT_PATH" --validate
RESULT=$?

echo "=======================================================" >&2
if [ $RESULT -eq 0 ]; then
    echo -e "${CLR_SUCCESS}✅ [PRE-PUSH] 検証成功！リモートリポジトリへ Push します。${CLR_RESET}" >&2
    log "SUCCESS" "PRE-PUSH" "検証成功！リモートリポジトリへ Push します。"
    exit 0
else
    echo -e "${CLR_ERR}❌ [PRE-PUSH] 組織の検証でエラーが発生したため、Push を中断しました。${CLR_RESET}" >&2
    echo -e "コンポーネントのエラー詳細は ./logs/sf-release.log を確認してください。" >&2
    log "ERROR" "PRE-PUSH" "組織の検証でエラーが発生したため、Push を中断しました。"
    log "INFO" "PRE-PUSH" "コンポーネントのエラー詳細は ./logs/sf-release.log を確認してください。"
    exit 1
fi