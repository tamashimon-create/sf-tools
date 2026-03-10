#!/bin/bash

# ==============================================================================
# プログラム名: sf-metasync.sh
# 概要: Salesforce組織の最新メタデータを取得し、Gitリポジトリへ自動コミット・Pushする
# 
# 運用想定: 
#   1. 手動実行による環境同期
#   2. cronやGitHub Actions等による「Sandboxの変更を毎日自動でGitに保存する」定期実行
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. 共通の初期処理
# ------------------------------------------------------------------------------
# カラー定義 (標準出力用)
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

echo "======================================================="
echo -e "${CLR_INFO}🔄 メタデータ同期（Sandbox -> Git）を開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# 【安全性】スクリプト終了時に一時ファイルを確実に削除する
trap 'rm -rf "$DELTA_DIR" ./cmd_output_$$.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 1. 設定項目 と 動的ターゲット判定
# ------------------------------------------------------------------------------
TARGET_ORG=""

# パターンA: 環境変数 (GitHub Actionsのsecrets等) が設定されているか確認
if [ -n "$SF_TARGET_ORG" ]; then
    TARGET_ORG="$SF_TARGET_ORG"
    echo -e "▶️  接続先判定: ${CLR_SUCCESS}${TARGET_ORG}${CLR_RESET} (環境変数 SF_TARGET_ORG より)"
fi

# パターンB: 環境変数がない場合、ローカルの接続情報を自動取得
if [ -z "$TARGET_ORG" ]; then
    DISPLAY_JSON=$(sf org display --json 2>/dev/null || echo "")
    CURRENT_ALIAS=$(echo "$DISPLAY_JSON" | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
    
    if [ -n "$CURRENT_ALIAS" ] && [ "$CURRENT_ALIAS" != "null" ]; then
        TARGET_ORG="$CURRENT_ALIAS"
        echo -e "▶️  接続先判定: ${CLR_SUCCESS}${TARGET_ORG}${CLR_RESET} (ローカル接続より自動取得)"
    fi
fi

if [ -z "$TARGET_ORG" ]; then
    echo -e "${CLR_ERR}❌ エラー: 同期元の組織エイリアスを特定できません。${CLR_RESET}" >&2
    exit 1
fi

# 現在のGitブランチ名の取得
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null || echo "unknown-branch")

# コミットメッセージ
readonly COMMIT_MSG="定期更新 (Salesforceの変更を自動反映)"

# 【並列実行対応】プロセスIDを付与した一時ディレクトリ名
readonly DELTA_DIR="./temp_delta_$$"

# ログ出力先
readonly LOG_FILE="./logs/sf-metaasync.log"

# 定期的に全件取得（リフレッシュ）する重要なメタデータ種別
readonly METADATA_TYPES=(
    ApexClass
    ApexPage
    LightningComponentBundle
    CustomObject
    CustomField
    Layout
    FlexiPage
    Flow
    PermissionSet
    CustomLabels
)

# ------------------------------------------------------------------------------
# 2. 共通エンジン（ログ管理とコマンド実行制御）
# ------------------------------------------------------------------------------
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

log() {
    local level=$1 stage=$2 message=$3
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
    local stage=$1; shift
    local cmd=("$@")
    local tmp_out="./cmd_output_$$.tmp"

    [[ "${cmd[0]}" == "sf" ]] && cmd+=("--json")
    log "CMD" "$stage" "${cmd[*]}"

    "${cmd[@]}" > "$tmp_out" 2>&1
    local status=$?

    if [ $status -eq 0 ] || grep -qE "nothing to commit|Already up to date|No local changes|\"status\": 0" "$tmp_out"; then
        echo "Command executed successfully." >> "$LOG_FILE"
        rm -f "$tmp_out"
        return 0
    fi

    cat "$tmp_out" >> "$LOG_FILE"
    rm -f "$tmp_out"
    return 1
}

# ------------------------------------------------------------------------------
# 3. 作業フェーズ定義
# ------------------------------------------------------------------------------
phase_git_update() {
    log "INFO" "GIT" "現在の作業を待避し、リモートの最新状態へリベース中..."
    exec_wrapper "GIT" git stash
    exec_wrapper "GIT" git fetch origin
    if ! exec_wrapper "GIT" git pull origin "$BRANCH_NAME" --rebase; then
        exec_wrapper "GIT" git rebase --abort
        return 1
    fi
    return 0
}

phase_analyze_delta() {
    log "INFO" "DELTA" "前回のコミットからの変更箇所を特定中..."
    exec_wrapper "DELTA" mkdir -p "$DELTA_DIR"
    exec_wrapper "DELTA" sf sgd source delta --from "origin/$BRANCH_NAME" --to HEAD --output-dir "$DELTA_DIR"
}

phase_retrieve_metadata() {
    if [ -f "$DELTA_DIR/package/package.xml" ]; then
        log "INFO" "RETRIEVE" "特定された差分ファイルをダウンロード中..."
        exec_wrapper "RETRIEVE" sf project retrieve start --manifest "$DELTA_DIR/package/package.xml" --target-org "$TARGET_ORG" --ignore-conflicts
    fi

    log "INFO" "RETRIEVE" "主要メタデータ（Apex/Flow/Layout等）をリフレッシュ中..."
    exec_wrapper "RETRIEVE" sf project retrieve start --metadata "${METADATA_TYPES[@]}" --target-org "$TARGET_ORG" --ignore-conflicts
}

phase_git_sync() {
    log "INFO" "SYNC" "GitリポジトリへコミットおよびPush中..."
    
    if ! exec_wrapper "SYNC" git add -A; then return 1; fi

    if git diff-index --quiet HEAD --; then
        return 2 # 変更なし
    fi

    if ! exec_wrapper "SYNC" git commit -m "$COMMIT_MSG"; then return 1; fi

    if ! exec_wrapper "SYNC" git push origin "$BRANCH_NAME"; then
        log "INFO" "SYNC" "Push失敗。最新を取り込んで再試行..."
        exec_wrapper "SYNC" git pull origin "$BRANCH_NAME" --rebase
        exec_wrapper "SYNC" git push origin "$BRANCH_NAME"
    fi
}

# ------------------------------------------------------------------------------
# 4. メインフロー制御
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------" >&2
log "INFO" "INIT" "非同期同期処理を開始 (Target: $TARGET_ORG, Branch: $BRANCH_NAME)"

if [ "$BRANCH_NAME" != "main" ]; then
    log "ERROR" "INIT" "このツールは 'main' ブランチでのみ実行可能です。処理を中断します。"
    echo "-------------------------------------------------------" >&2
    exit 1
fi

if ! phase_git_update; then log "ERROR" "GIT" "失敗"; exit 1; fi
log "SUCCESS" "GIT" "完了"

if ! phase_analyze_delta; then log "ERROR" "DELTA" "失敗"; exit 1; fi
log "SUCCESS" "DELTA" "完了"

if ! phase_retrieve_metadata; then log "ERROR" "RETRIEVE" "失敗"; exit 1; fi
log "SUCCESS" "RETRIEVE" "完了"

phase_git_sync
RES=$?

if [ $RES -eq 0 ]; then
    log "SUCCESS" "SYNC" "完了 (リポジトリを更新しました)"
elif [ $RES -eq 2 ]; then
    log "INFO" "SYNC" "Salesforce組織に変更は検出されませんでした"
    log "SUCCESS" "SYNC" "完了"
else
    log "ERROR" "SYNC" "失敗"
    exit 1
fi

log "SUCCESS" "FINISH" "すべての工程が正常に完了しました"
echo "-------------------------------------------------------" >&2
exit 0