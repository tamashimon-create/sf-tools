#!/bin/bash

# ==============================================================================
# プログラム名: sf-metasync.sh
# 概要: Salesforce組織の最新メタデータを取得し、Gitリポジトリへ自動コミット・Pushする
# 
# 運用想定: 
#   1. 手動実行による環境同期
#   2. cronやGitHub Actions等による「Sandboxの変更を毎日自動でGitに保存する」定期実行
# ==============================================================================

# 【安全性】スクリプト終了時に一時ファイルを確実に削除する（プロセスID $$ を利用して競合防止）
trap 'rm -rf "$DELTA_DIR" ./cmd_output_$$.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 1. 設定項目
# ------------------------------------------------------------------------------
# 接続先のSalesforce組織（sf org list で確認できるエイリアス）
readonly TARGET_ORG="tama"

# 現在のGitブランチ名の取得（自動実行時は HEAD から直接取得）
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$BRANCH_NAME" ]; then
    BRANCH_NAME="unknown-branch"
fi

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

# ------------------------------------------------------------------------------
# 2. 共通エンジン（ログ管理とコマンド実行制御）
# ------------------------------------------------------------------------------
# ディレクトリ作成とログファイルの初期化
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

# 進行状況の出力（人間向けのメッセージは標準エラー出力 >&2 へ逃がす）
log() {
    local level=$1 stage=$2 message=$3
    local ts=$(date +'%Y-%m-%d %H:%M:%S')

    # ファイルに記録
    printf "[%s] [%s] [%s] %s\n" "$ts" "$level" "$stage" "$message" >> "$LOG_FILE"

    case "$level" in
        "INFO")    echo -e "${CLR_INFO}▶️  [$stage]${CLR_RESET} $message" >&2 ;;
        "SUCCESS") echo -e "${CLR_SUCCESS}✅ [$stage]${CLR_RESET} $message" >&2 ;;
        "ERROR")   echo -e "${CLR_ERR}❌ [$stage]${CLR_RESET} $message" >&2 ;;
        "CMD")     echo -e "${CLR_CMD}   > Command:${CLR_RESET} $message" >&2 ;;
    esac
}

# 全コマンドの実行管理（JSONモード自動付与と成功キーワード検知）
exec_wrapper() {
    local stage=$1; shift
    local cmd=("$@")
    local tmp_out="./cmd_output_$$.tmp"

    # sfコマンドには自動的に --json を付与して解析可能にする
    [[ "${cmd[0]}" == "sf" ]] && cmd+=("--json")
    log "CMD" "$stage" "${cmd[*]}"

    # 実行
    "${cmd[@]}" > "$tmp_out" 2>&1
    local status=$?

    # 成功判定：終了コード0、または「変更なし」を意味する特定キーワードが含まれる場合
    if [ $status -eq 0 ] || \
       grep -qE "nothing to commit|Already up to date|No local changes|\"status\": 0" "$tmp_out"; then
        echo "Command executed successfully." >> "$LOG_FILE"
        rm -f "$tmp_out"
        return 0
    fi

    # 失敗時は詳細をログに残す
    cat "$tmp_out" >> "$LOG_FILE"
    rm -f "$tmp_out"
    return 1
}

# ------------------------------------------------------------------------------
# 3. 作業フェーズ定義
# ------------------------------------------------------------------------------

# フェーズ1: Gitローカル環境の整理
phase_git_update() {
    log "INFO" "GIT" "現在の作業を待避し、リモートの最新状態へリベース中..."
    exec_wrapper "GIT" git stash
    exec_wrapper "GIT" git fetch origin
    # 競合でスクリプトが止まらないよう、失敗時はリベースを中断するケア
    if ! exec_wrapper "GIT" git pull origin "$BRANCH_NAME" --rebase; then
        exec_wrapper "GIT" git rebase --abort
        return 1
    fi
    return 0
}

# フェーズ2: Salesforce Git Diff (SGD) による差分分析
phase_analyze_delta() {
    log "INFO" "DELTA" "前回のコミットからの変更箇所を特定中..."
    exec_wrapper "DELTA" mkdir -p "$DELTA_DIR"
    # originのブランチと現在のHEADの差分から package.xml を生成
    exec_wrapper "DELTA" sf sgd source delta --from "origin/$BRANCH_NAME" --to HEAD --output-dir "$DELTA_DIR"
}

# フェーズ3: メタデータのダウンロード（Retrieve）
phase_retrieve_metadata() {
    # 1. 差分分析で特定された項目を優先取得
    if [ -f "$DELTA_DIR/package/package.xml" ]; then
        log "INFO" "RETRIEVE" "特定された差分ファイルをダウンロード中..."
        exec_wrapper "RETRIEVE" sf project retrieve start --manifest "$DELTA_DIR/package/package.xml" --target-org "$TARGET_ORG" --ignore-conflicts
    fi

    # 2. 定義された重要メタデータ種別の最新化（定期メンテナンス）
    log "INFO" "RETRIEVE" "主要メタデータ（Apex/Flow/Layout等）をリフレッシュ中..."
    exec_wrapper "RETRIEVE" sf project retrieve start --metadata "${METADATA_TYPES[@]}" --target-org "$TARGET_ORG" --ignore-conflicts
}

# フェーズ4: Gitリポジトリへの反映とPush
phase_git_sync() {
    log "INFO" "SYNC" "GitリポジトリへコミットおよびPush中..."
    
    # 変更をステージング
    if ! exec_wrapper "SYNC" git add -A; then return 1; fi

    # 組織に変更がなかった（差分ゼロ）場合は、何もしない(Status 2)
    if git diff-index --quiet HEAD --; then
        return 2
    fi

    # コミット実行
    if ! exec_wrapper "SYNC" git commit -m "$COMMIT_MSG"; then return 1; fi

    # リモートへPush。他者の割り込みで失敗した場合は一度リベースして再トライ
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

# mainブランチ以外での実行をブロックする安全装置
if [ "$BRANCH_NAME" != "main" ]; then
    log "ERROR" "INIT" "このツールは 'main' ブランチでのみ実行可能です。処理を中断します。"
    echo "-------------------------------------------------------" >&2
    exit 1
fi

# 各フェーズを順次実行
if ! phase_git_update; then log "ERROR" "GIT" "失敗"; exit 1; fi
log "SUCCESS" "GIT" "完了"

if ! phase_analyze_delta; then log "ERROR" "DELTA" "失敗"; exit 1; fi
log "SUCCESS" "DELTA" "完了"

if ! phase_retrieve_metadata; then log "ERROR" "RETRIEVE" "失敗"; exit 1; fi
log "SUCCESS" "RETRIEVE" "完了"

# Git同期の実行と結果判定
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

# 終了処理
log "SUCCESS" "FINISH" "すべての工程が正常に完了しました"
echo "-------------------------------------------------------" >&2
exit 0