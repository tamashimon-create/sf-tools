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
#   -t, --target     : 接続先組織のエイリアスを明示的に指定します（GitHub Actions等で利用）。
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. 共通の初期処理
# ------------------------------------------------------------------------------
# ターミナル出力用のカラー定義（標準出力用）
# 実行環境がインタラクティブなターミナルの場合のみ色を有効化し、ログファイル等を汚さないようにする
if [ -t 1 ]; then
    readonly CLR_INFO='\033[36m'; readonly CLR_SUCCESS='\033[32m';
    readonly CLR_ERR='\033[31m'; readonly CLR_PROMPT='\033[33m'; readonly CLR_RESET='\033[0m'
else
    readonly CLR_INFO=''; readonly CLR_SUCCESS=''; readonly CLR_ERR=''; readonly CLR_PROMPT=''; readonly CLR_RESET=''
fi

echo "======================================================="
echo -e "${CLR_INFO}📦 リリース・検証処理を開始します...${CLR_RESET}"
echo "======================================================="

# 実行ディレクトリのバリデーション
# プロジェクトルート（force-から始まるディレクトリ）以外での誤実行による事故を防止します
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ ! "$CURRENT_DIR_NAME" =~ ^force- ]]; then
    echo -e "${CLR_ERR}❌ エラー: このスクリプトは 'force-*' ディレクトリ内でのみ実行可能です。${CLR_RESET}"
    exit 1
fi

# 【安全性】スクリプト終了時に、プロセスID($$)が付与された一時ファイルを確実にクリーンアップする
# 正常終了時はもちろん、Ctrl+Cによる中断やエラー時にも作業ディレクトリを汚さないためのマナーです
trap 'rm -f ./cmd_output_$$.tmp ./cmd_exit_$$.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 1. 接続先組織 (TARGET_ORG) の動的判定
# ------------------------------------------------------------------------------
# 優先順位: 1.引数(-t) > 2.環境変数(SF_TARGET_ORG) > 3.ローカル接続情報(sf org display)
TARGET_ORG=""

# パターンA: 環境変数 (GitHub Actionsのsecrets等) が設定されているか確認
if [ -n "$SF_TARGET_ORG" ]; then
    TARGET_ORG="$SF_TARGET_ORG"
    echo -e "▶️  接続先判定: ${CLR_SUCCESS}${TARGET_ORG}${CLR_RESET} (環境変数 SF_TARGET_ORG より)"
fi

# パターンB: 環境変数がない場合、ローカルPCの現在の接続情報を自動取得
if [ -z "$TARGET_ORG" ]; then
    # sfコマンドのJSON出力から現在の接続組織を特定
    DISPLAY_JSON=$(sf org display --json 2>/dev/null || echo "")
    # JSONからエイリアス名を抽出し、余計な改行コードを除去
    CURRENT_ALIAS=$(echo "$DISPLAY_JSON" | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
    
    if [ -n "$CURRENT_ALIAS" ] && [ "$CURRENT_ALIAS" != "null" ]; then
        TARGET_ORG="$CURRENT_ALIAS"
        echo -e "▶️  接続先判定: ${CLR_SUCCESS}${TARGET_ORG}${CLR_RESET} (ローカル接続より自動取得)"
    fi
fi

# ------------------------------------------------------------------------------
# 2. 実行時引数の解析 (オプション)
# ------------------------------------------------------------------------------
# 初期状態は「最も安全な設定（検証のみ、ブラウザ開く）」に固定
IS_VALIDATE_MODE=1
OPEN_BROWSER=1
IGNORE_CONFLICTS=0
OUTPUT_JSON=0

# 引数解析ループ：指定されたオプションに応じてフラグを切り替える
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --release|-r) IS_VALIDATE_MODE=0 ;; # 明示的に指定した場合のみ本番リリースを許可
        --no-open|-n) OPEN_BROWSER=0 ;;      # CI環境などブラウザがない環境で利用
        --force|-f)   IGNORE_CONFLICTS=1 ;;  # 複数人開発でのコンフリクトを強制上書き
        --json|-j)    OUTPUT_JSON=1 ;;       # 機械読み取り用の出力形式に固定
        --target|-t)  TARGET_ORG="$2"; shift ;; # ターゲットを引数で直接指定（最優先）
        --*)
            echo -e "${CLR_ERR}❌ [INIT]${CLR_RESET} 不明なオプションです: $1" >&2
            exit 1
            ;;
        *)
            echo -e "${CLR_ERR}❌ [INIT]${CLR_RESET} 不明な引数です: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# 最終チェック: ターゲットがどこからも特定できない場合は、事故防止のため処理を中断
if [ -z "$TARGET_ORG" ]; then
    echo -e "${CLR_ERR}❌ エラー: 接続先の組織エイリアスを特定できません。${CLR_RESET}" >&2
    echo -e "💡 sf-start.sh でログインするか、-t オプションで指定してください。" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. 共通設定 と パス定義
# ------------------------------------------------------------------------------
# 現在のGitブランチ名を自動取得（リリース管理ディレクトリの特定に使用）
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null || echo "unknown-branch")

# 各種パスの定義：プロジェクト構造に基づいた絶対/相対パスを設定
readonly RELEASE_BASE="release"
readonly RELEASE_DIR="${RELEASE_BASE}/${BRANCH_NAME}"
readonly TEMPLATE_DEPLOY="$HOME/sf-tools/templates/deploy-template.txt"
readonly TEMPLATE_REMOVE="$HOME/sf-tools/templates/remove-template.txt"
readonly DEPLOY_LIST="${RELEASE_DIR}/deploy-target.txt"
readonly REMOVE_LIST="${RELEASE_DIR}/remove-target.txt"
readonly DEPLOY_XML="${RELEASE_DIR}/package.xml"
readonly REMOVE_XML="${RELEASE_DIR}/destructiveChanges.xml"
readonly LOG_FILE="./logs/sf-release.log"

# カラー装飾定義（ログファイルやパイプ用には色をつけない）
if [ -t 2 ]; then
    readonly CLR_CMD='\033[34m'
else
    readonly CLR_CMD=''
fi

# ------------------------------------------------------------------------------
# 4. 共通エンジン (サブルーチンの詳細説明)
# ------------------------------------------------------------------------------
# ログ出力先ディレクトリを準備し、実行のたびにフレッシュな状態にする
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

# 【logサブルーチン】: ログ管理と画面出力を統合
# 引数: $1=レベル(INFO/SUCCESS/ERROR/CMD), $2=ステージ名, $3=メッセージ
# ロジック:
#   1. 進捗状況を標準エラー出力(>&2)へカラー表示。これにより、標準出力をパイプ等で活用可能。
#   2. タイムスタンプを付与し、すべての履歴をログファイルへ永続的に記録。
log() {
    local level=$1 stage=$2 message=$3
    local ts=$(date +'%Y-%m-%d %H:%M:%S')
    
    # 記録用ログファイルへの書き込み
    printf "[%s] [%s] [%s] %s\n" "$ts" "$level" "$stage" "$message" >> "$LOG_FILE"

    # コンソール表示用（視認性を考慮したカラー装飾）
    case "$level" in
        "INFO")    echo -e "${CLR_INFO}▶️  [$stage]${CLR_RESET} $message" >&2 ;;
        "SUCCESS") echo -e "${CLR_SUCCESS}✅ [$stage]${CLR_RESET} $message" >&2 ;;
        "ERROR")   echo -e "${CLR_ERR}❌ [$stage]${CLR_RESET} $message" >&2 ;;
        "CMD")     echo -e "${CLR_CMD}   > Command:${CLR_RESET} $message" >&2 ;;
    esac
}

# 【exec_wrapperサブルーチン】: コマンド実行の司令塔
# 引数: $1=ステージ名, $2以降=実際に実行するコマンドと引数
# ロジック:
#   1. --json モードが有効な場合、sfコマンドに自動付与し機械可読性を確保。
#   2. teeコマンドにより、実行時の出力をリアルタイムで画面に映しつつ一時ファイルへ保存。
#   3. 特殊判定：Salesforce CLI特有の「成功メッセージはあるが終了コードが1」のケースを
#      キーワード走査によって救済し、自動化を不当に停止させない。
exec_wrapper() {
    local stage=$1; shift
    local cmd=("$@")
    local tmp_out="./cmd_output_$$.tmp"
    local tmp_exit="./cmd_exit_$$.tmp"

    # JSON出力フラグに基づき、sfコマンドのみ動的に引数を追加
    [[ "$OUTPUT_JSON" -eq 1 ]] && [[ "${cmd[0]}" == "sf" ]] && cmd+=("--json")
    
    # 実行するコマンド自体をロギングし、透明性を確保
    log "CMD" "$stage" "${cmd[*]}"

    # コマンド実行。標準出力・エラーを統合し、teeで分岐。パイプ終了後に$?を回収。
    ( "${cmd[@]}" 2>&1 ; echo $? > "$tmp_exit" ) | tee "$tmp_out"
    local status=$(cat "$tmp_exit" 2>/dev/null || echo 1)
    
    local is_success=0
    # 成功判定のフェイルセーフ：コード0、または出力テキストに成功キーワードが含まれるかチェック
    if [ "$status" -eq 0 ] || grep -qE "successfully wrote|Status: Succeeded|Deployed Source|Successfully deployed|\"status\": 0" "$tmp_out"; then
        is_success=1
        # 非ゼロ終了コードからの救済時はログに注釈を残す
        [[ "$status" -ne 0 ]] && echo "Notice: Rescued exit code $status by success keyword." >> "$LOG_FILE"
    fi

    # 個別コマンドの実行ログを統合ログファイルにマージ
    cat "$tmp_out" >> "$LOG_FILE"
    rm -f "$tmp_out" "$tmp_exit"

    if [[ "$is_success" -eq 1 ]]; then
        return 0
    else
        log "ERROR" "$stage" "コマンドが異常終了しました。ログファイルを参照してください。"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 5. 作業フェーズ定義 (ビジネスロジック)
# ------------------------------------------------------------------------------

# フェーズ1: 対象リストの準備（ディレクトリおよび雛形の自動生成）
phase_check_target() {
    local created=0
    mkdir -p "$RELEASE_DIR"
    # デプロイ用と削除用、それぞれのリストファイルを確認
    for target in "$DEPLOY_LIST" "$REMOVE_LIST"; do
        if [ ! -f "$target" ]; then
            template="${TEMPLATE_DEPLOY}"
            [[ "$target" == "$REMOVE_LIST" ]] && template="${TEMPLATE_REMOVE}"
            if [ -f "$template" ]; then
                cp "$template" "$target"
                created=1
            fi
        fi
    done
    # 新規作成された場合は、ユーザーに記入を促すため一度停止
    [[ "$created" -eq 1 ]] && log "ERROR" "CHECK" "リストを作成しました。中身を記入して再実行してください。" && return 1
    return 0
}

# フェーズ2: テキストリストからマニフェストファイル(XML)を自動生成
phase_generate_manifest() {
    rm -f "$DEPLOY_XML" "$REMOVE_XML"
    local deploy_args=()
    local remove_args=()
    
    # 補助関数: リストファイルを走査し、コメント等を除外してsfコマンド用引数を組み立てる
    process_list() {
        local list=$1; shift; local -n ref=$1
        while IFS= read -r line || [ -n "$line" ]; do
            # 改行コード除去、空白トリム
            clean_line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            # 有効なパス（空行・コメント以外）であれば配列に格納
            [[ -n "$clean_line" ]] && [[ "$clean_line" != \#* ]] && ref+=("--source-dir" "$clean_line")
        done < "$list"
        
        # ★TortoiseGit でのサイレントエラー対策★
        # whileループの最後の行が空行等で false になった場合でも、関数としては「成功(0)」を返すように明示する
        return 0 
    }
    
    process_list "$DEPLOY_LIST" deploy_args || return 1
    process_list "$REMOVE_LIST" remove_args || return 1

    # 追加/変更用の package.xml 生成
    if [ ${#deploy_args[@]} -gt 0 ]; then
        log "INFO" "MANIFEST" "デプロイ対象（${#deploy_args[@]}件）を検出"
        exec_wrapper "MANIFEST" sf project generate manifest "${deploy_args[@]}" --output-dir "$RELEASE_DIR" --name "package.xml" || return 1
    else
        # 対象ゼロでもCLIエラーを防ぐために最小構成のXMLを作成
        echo '<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>60.0</version></Package>' > "$DEPLOY_XML"
    fi
    
    # 削除用の destructiveChanges.xml 生成（存在する場合のみ）
    [[ ${#remove_args[@]} -gt 0 ]] && exec_wrapper "MANIFEST" sf project generate manifest "${remove_args[@]}" --output-dir "$RELEASE_DIR" --name "destructiveChanges.xml"
    
    return 0
}

# フェーズ3: Salesforce への最終的なデプロイ/検証の実行
phase_release() {
    # ターゲット組織とマニフェストを指定してコマンドを構成
    local deploy_cmd=("sf" "project" "deploy" "start" "--target-org" "$TARGET_ORG" "--manifest" "$DEPLOY_XML")
    [[ -f "$REMOVE_XML" ]] && deploy_cmd+=("--pre-destructive-changes" "$REMOVE_XML")
    [[ "$IGNORE_CONFLICTS" -eq 1 ]] && deploy_cmd+=("--ignore-conflicts")
    
    # 検証/本番モードの最終判定
    if [ "$IS_VALIDATE_MODE" -eq 1 ]; then
        log "INFO" "RELEASE" "🧪 検証モード (Dry-Run) を開始します"
        deploy_cmd+=("--dry-run")
    else
        log "INFO" "RELEASE" "🚨 本番環境へのリリースを実行します！"
    fi

    # インタラクティブ実行時はブラウザで進捗画面を自動表示
    if [ "$OPEN_BROWSER" -eq 1 ]; then
        log "INFO" "RELEASE" "🌐 リリース状況画面をブラウザで表示します..."
        sf org open --target-org "$TARGET_ORG" --path "lightning/setup/DeployStatus/home" > /dev/null 2>&1 &
        log "INFO" "RELEASE" "⏳ ブラウザ描画待機 (5秒)"
        sleep 5
    fi
    
    # 構築した全コマンドをラッパー経由で安全に実行
    exec_wrapper "RELEASE" "${deploy_cmd[@]}"
}

# ------------------------------------------------------------------------------
# 6. メインフロー制御
# ------------------------------------------------------------------------------
echo "-------------------------------------------------------" >&2
log "INFO" "INIT" "リリース処理開始 (Target: $TARGET_ORG, Branch: $BRANCH_NAME)"

# 各フェーズを順次実行。一つでも失敗すればそこで即停止し、後続のリリースを未然に防ぐ。
phase_check_target || exit 1
log "SUCCESS" "CHECK" "完了"

phase_generate_manifest || exit 1
log "SUCCESS" "MANIFEST" "完了"

phase_release || exit 1
log "SUCCESS" "RELEASE" "完了"

# 全行程が無事に終了したことを告げ、カラー装飾で成功を強調。
log "SUCCESS" "FINISH" "すべての工程が正常に終了しました。"
echo "-------------------------------------------------------" >&2
exit 0