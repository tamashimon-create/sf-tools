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
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"         # 実行のたびにログをリセット
readonly SILENT_EXEC=1          # コマンドの標準出力はログファイルのみに記録

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
# 3. 初期チェック
# ------------------------------------------------------------------------------
# プロジェクトディレクトリ（force-で始まる）にいるか確認
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "" "リリース・検証処理を開始します..."

# 一時ファイルおよび一時ディレクトリの自動削除設定
DELTA_DIR="./temp_delta_$$"
trap 'rm -rf "$DELTA_DIR" ./cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. 接続先組織 (TARGET_ORG) の動的判定
# ------------------------------------------------------------------------------
# 優先順位: 1.引数(-t) > 2.環境変数(SF_TARGET_ORG) > 3.ローカル接続情報(sf org display)
TARGET_ORG=""

# パターンA: 環境変数 (GitHub Actionsのsecrets等) が設定されているか確認
if [ -n "$SF_TARGET_ORG" ]; then
    TARGET_ORG="$SF_TARGET_ORG"
    log "INFO" "ORG" "接続先判定: ${TARGET_ORG}(環境変数 SF_TARGET_ORG より)"
fi

# パターンB: 環境変数がない場合、ローカルPCの現在の接続情報を自動取得
if [ -z "$TARGET_ORG" ]; then
    # sfコマンドのJSON出力から現在の接続組織を特定
    DISPLAY_JSON=$(sf org display --json 2>/dev/null || echo "")
    # JSONからエイリアス名を抽出し、余計な改行コードを除去
    CURRENT_ALIAS=$(echo "$DISPLAY_JSON" | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
    
    if [ -n "$CURRENT_ALIAS" ] && [ "$CURRENT_ALIAS" != "null" ]; then
        TARGET_ORG="$CURRENT_ALIAS"
        log "INFO" "ORG" "接続先判定: ${TARGET_ORG}(ローカル接続より自動取得)"
    fi
fi

# ------------------------------------------------------------------------------
# 5. 実行時引数の解析 (オプション)
# ------------------------------------------------------------------------------
# 初期状態は「最も安全な設定（検証のみ、ブラウザ開く）」に固定
IS_VALIDATE_MODE=1
OPEN_BROWSER=1
IGNORE_CONFLICTS=0
OUTPUT_JSON=0

# 引数解析ループ：指定されたオプションに応じてフラグを切り替える
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --validate|--dry-run) IS_VALIDATE_MODE=1 ;; # 検証モードを明示的に指定
        --release|-r) IS_VALIDATE_MODE=0 ;; # 明示的に指定した場合のみ本番リリースを許可
        --no-open|-n) OPEN_BROWSER=0 ;;      # CI環境などブラウザがない環境で利用
        --force|-f)   IGNORE_CONFLICTS=1 ;;  # 複数人開発でのコンフリクトを強制上書き
        --json|-j)    OUTPUT_JSON=1 ;;       # 機械読み取り用の出力形式に固定
        --target|-t)  TARGET_ORG="$2"; shift ;; # ターゲットを引数で直接指定（最優先）
        --*)
            log "ERROR" "ARG" "不明なオプションです: $1"
            exit 1
            ;;
        *)
            log "ERROR" "ARG" "不明な引数です: $1"
            exit 1
            ;;
    esac
    shift
done

# 最終チェック: ターゲットがどこからも特定できない場合は、事故防止のため処理を中断
if [ -z "$TARGET_ORG" ]; then
    log "ERROR" "OPTION" "接続先の組織エイリアスを特定できません。"
    exit 1
fi

# ------------------------------------------------------------------------------
# 6. 共通設定 と パス定義
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

# ------------------------------------------------------------------------------
# 7. 作業フェーズ定義 (ビジネスロジック)
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
        run "MANIFEST" sf project generate manifest "${deploy_args[@]}" --output-dir "$RELEASE_DIR" --name "package.xml" || return 1
    else
        # 対象ゼロでもCLIエラーを防ぐために最小構成のXMLを作成
        echo '<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>60.0</version></Package>' > "$DEPLOY_XML"
    fi
    
    # 削除用の destructiveChanges.xml 生成（存在する場合のみ）
    [[ ${#remove_args[@]} -gt 0 ]] && run "MANIFEST" sf project generate manifest "${remove_args[@]}" --output-dir "$RELEASE_DIR" --name "destructiveChanges.xml"
    
    return 0
}

# フェーズ3: Salesforce へのデプロイ/検証の実行
phase_release() {
    # ターゲット組織とマニフェストを指定してコマンドを構成
    local deploy_cmd=("sf" "project" "deploy" "start" "--target-org" "$TARGET_ORG" "--manifest" "$DEPLOY_XML")
    [[ -f "$REMOVE_XML" ]] && deploy_cmd+=("--pre-destructive-changes" "$REMOVE_XML")
    [[ "$IGNORE_CONFLICTS" -eq 1 ]] && deploy_cmd+=("--ignore-conflicts")
    
    # 検証/本番モードの最終判定
    if [ "$IS_VALIDATE_MODE" -eq 1 ]; then
        log "INFO" "RELEASE" "検証モード (Dry-Run) を開始します"
        deploy_cmd+=("--dry-run")
    else
        log "INFO" "RELEASE" "本番環境へのリリースを実行します！"
    fi

    # インタラクティブ実行時はブラウザで進捗画面を自動表示
    if [ "$OPEN_BROWSER" -eq 1 ]; then
        log "INFO" "RELEASE" "リリース状況画面をブラウザで表示します..."
        run "RELEASE" sf org open --target-org "$TARGET_ORG" --path "lightning/setup/DeployStatus/home"
        log "INFO" "RELEASE" "ブラウザ描画待機 (5秒)"
        sleep 5
    fi
    
    # 構築した全コマンドをラッパー経由で安全に実行
    run "RELEASE" "${deploy_cmd[@]}"
}

# ------------------------------------------------------------------------------
# 8. メインフロー制御 (修正箇所)
# ------------------------------------------------------------------------------
log "INFO" "INIT" "リリース処理開始 (Target: ${TARGET_ORG:-未指定}, Branch: $(git symbolic-ref --short HEAD 2>/dev/null))"

# フェーズ1 & 2 は厳密にチェック
phase_check_target      || die "対象リストの準備に失敗しました。"
log "SUCCESS" "CHECK" "完了"

phase_generate_manifest || die "マニフェスト生成に失敗しました。"
log "SUCCESS" "MANIFEST" "完了"

# フェーズ3: リリース実行。RET_NO_CHANGE (2) の場合は正常終了として扱う
phase_release
res=$?

if [[ $res -eq $RET_OK ]]; then
    log "SUCCESS" "RELEASE" "完了"
    log "SUCCESS" "FINISH" "すべての工程が正常に終了しました。"
elif [[ $res -eq $RET_NO_CHANGE ]]; then
    log "SUCCESS" "RELEASE" "変更がないため処理をスキップしました。"
    log "SUCCESS" "FINISH" "正常に終了しました（変更なし）。"
else
    die "Salesforce へのデプロイ/検証の実行に失敗しました。"
fi

exit 0