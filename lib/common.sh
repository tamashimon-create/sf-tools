#!/bin/bash
# ==============================================================================
# common.sh - sf-tools 共通関数ライブラリ
# ==============================================================================
# sf-tools の全スクリプトが source して使用する共通ライブラリです。
#
# 【source 前に必須の変数定義】
#   readonly SCRIPT_NAME=...   スクリプト名（拡張子なし）
#   readonly LOG_FILE=...      ログファイルパス（例: ./logs/${SCRIPT_NAME}.log）
#   readonly LOG_MODE=...      NEW=実行ごとにリセット / APPEND=追記
#   readonly SILENT_EXEC=...   1=コマンド出力をログのみに記録 / 0=画面にも表示
#
# 【提供する関数】
#   log LEVEL MESSAGE [DEST]  ... 画面とログファイルへ出力
#   run CMD [ARGS...]         ... コマンドを実行してログに記録
#   die MESSAGE [EXIT_CODE]   ... エラーログを出力して終了
#   get_target_org [ALIAS]    ... 接続先組織エイリアスを解決
#   check_force_dir           ... force-* ディレクトリ内か確認
#
# 【戻り値定数】
#   RET_OK=0        正常終了
#   RET_NG=1        異常終了
#   RET_NO_CHANGE=2 変更なし（NothingToDeploy）
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
    echo "[FATAL ERROR] LOG_FILE が未定義です。source 前に定義してください。" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
[[ "${LOG_MODE:-}" == "NEW" ]] && : > "$LOG_FILE"

# ------------------------------------------------------------------------------
# 3. カラー定義
# ------------------------------------------------------------------------------
readonly CLR_INFO='\033[36m'    # シアン    (情報・進行中)
readonly CLR_SUCCESS='\033[32m' # グリーン  (成功・完了)
readonly CLR_WARNING='\033[33m' # イエロー  (警告)
readonly CLR_ERR='\033[31m'     # レッド    (エラー)
readonly CLR_PROMPT='\033[35m'  # マゼンタ  (ユーザー入力要求)
readonly CLR_RESET='\033[0m'    # リセット

# ------------------------------------------------------------------------------
# 4. log - 画面とログファイルへの統合出力
# ------------------------------------------------------------------------------
# 【使い方】
#   log LEVEL MESSAGE [DEST]
#
# 【引数】
#   LEVEL   : 出力レベル（下記参照）
#   MESSAGE : 出力するメッセージ本文
#   DEST    : 出力先。省略時は BOTH。
#               BOTH   = 画面とログファイルの両方（デフォルト）
#               SCREEN = 画面のみ
#               FILE   = ログファイルのみ
#
# 【LEVEL の種類と用途】
#   HEADER  : 処理ブロックの開始を区切り線つきで強調表示する
#   INFO    : 処理の進行状況を通知する（シアン）
#   SUCCESS : 処理の正常完了を通知する（グリーン）
#   WARNING : 問題があるが続行可能な状態を通知する（イエロー）
#   ERROR   : 処理を継続できないエラーを通知する（レッド）
#   CMD     : run 関数が実行コマンドを記録するために使用する（色なし）
#
# 【使用例】
#   log "INFO"    "処理を開始します..."
#   log "SUCCESS" "完了しました。"
#   log "WARNING" "接続に失敗しました（続行します）"
#   log "ERROR"   "致命的なエラーが発生しました"
#   log "HEADER"  "スタートアップを開始します"
# ------------------------------------------------------------------------------
log() {
    local level="$1" message="$2" dest="${3:-BOTH}"
    local ts
    ts=$(date +'%Y-%m-%d %H:%M:%S')

    # A. ログファイル出力 (色コードなし)
    if [[ "$dest" == "BOTH" || "$dest" == "FILE" ]]; then
        if [[ "$level" == "HEADER" ]]; then
            printf "\n[%s] [=== %s ===]\n" "$ts" "$message" >> "$LOG_FILE"
        elif [[ "$level" == "CMD" ]]; then
            printf "[%s] [CMD] Command: %s\n" "$ts" "$message" >> "$LOG_FILE"
        else
            printf "[%s] [%s] %s\n" "$ts" "$level" "$message" >> "$LOG_FILE"
        fi
    fi

    # B. 画面出力 (色付き)
    if [[ "$dest" == "BOTH" || "$dest" == "SCREEN" ]]; then
        case "$level" in
            HEADER)
                echo "-------------------------------------------------------" >&2
                echo -e "${CLR_INFO}>> ${message}${CLR_RESET}" >&2
                echo "-------------------------------------------------------" >&2 ;;
            INFO)
                echo -e "${CLR_INFO}[INFO] ${message}${CLR_RESET}" >&2 ;;
            SUCCESS)
                echo -e "${CLR_SUCCESS}[SUCCESS] ${message}${CLR_RESET}" >&2 ;;
            WARNING)
                echo -e "${CLR_WARNING}[WARNING] ${message}${CLR_RESET}" >&2 ;;
            ERROR)
                echo -e "${CLR_ERR}[ERROR] ${message}${CLR_RESET}" >&2 ;;
            CMD)
                echo "   > Command: ${message}" >&2 ;;
            *)
                echo -e "${message}" >&2 ;;
        esac
    fi
    return $RET_OK
}

# ------------------------------------------------------------------------------
# 5. run - コマンド実行ラッパー（通常呼び出し・命令置換の両対応）
# ------------------------------------------------------------------------------
# 【使い方】
#   run CMD [ARGS...]           # 通常呼び出し
#   VAR=$(run CMD [ARGS...])    # 命令置換（出力を変数に受け取る）
#
# 【引数】
#   CMD     : 実行するコマンド
#   ARGS... : コマンドに渡す引数
#
# 【戻り値】
#   RET_OK        (0) : 成功
#   RET_NO_CHANGE (2) : 変更なし（NothingToDeploy / No local changes to deploy）
#   RET_NG        (1) : 失敗
#
# 【命令置換での自動判定】
#   stdout が端末でない場合（命令置換 $(...) 内）は出力を自動的に返します。
#   通常呼び出し時は出力を返しません。この切り替えは自動で行われます。
#   命令置換内で 2>/dev/null を付けると、CMD ログ行（> Command: ...）の
#   画面表示を抑制できます。ログファイルへの記録は通常通り行われます。
#   例: VAR=$(run git symbolic-ref --short HEAD 2>/dev/null)
#
# 【SILENT_EXEC の挙動】
#   SILENT_EXEC=1 : コマンド出力をログファイルのみに記録（画面には表示しない）
#   SILENT_EXEC=0 : コマンド出力を画面とログファイルの両方に表示
#
# 【ログファイルへの出力】
#   コマンド出力に含まれる ANSI エスケープコードおよび絵文字を除去してから記録します。
#   各行には "[timestamp] [OUT]" のプレフィックスを付与します（空行は除く）。
#
# 【成功判定のルール】
#   終了コードが 0 であれば成功とします。
#   Salesforce CLI は処理成功でも終了コードが非ゼロになる場合があるため、
#   出力に成功キーワード（"Successfully" 等）が含まれる場合も RET_OK とします。
#
# 【使用例】
#   run bash "./sf-install.sh"                      || die "失敗"
#   run mkdir -p "release/${BRANCH_NAME}"           || return $RET_NG
#   run sf org login web --set-default --alias "$A" || die "失敗"
#   printf '{"target-org": "%s"}\n' "$A" | run tee .sf/config.json
#   BRANCH=$(run git symbolic-ref --short HEAD 2>/dev/null)
#   JSON=$(run sf org display --json 2>/dev/null || echo "")
# ------------------------------------------------------------------------------
run() {
    local cmd=("$@")
    local tmp_out="./cmd_out_$$_${RANDOM}.tmp"
    local status

    log "CMD" "${cmd[*]}"
    "${cmd[@]}" > "$tmp_out" 2>&1
    status=$?

    # SILENT_EXEC=0 の場合は画面にも表示（stderr 経由なので命令置換に影響しない）
    if [[ "${SILENT_EXEC:-}" != "1" ]]; then
        cat "$tmp_out" >&2
    fi

    # 命令置換 $(...) 内の場合（stdout が端末でない）は出力を返す
    if [[ ! -t 1 ]]; then
        cat "$tmp_out"
    fi

    local is_success=$RET_NG
    # A. 変更なし（NothingToDeploy）の検知
    if grep -qE "NothingToDeploy|No local changes to deploy" "$tmp_out"; then
        log "INFO" "デプロイ対象の変更がないためスキップされました。"
        is_success=$RET_NO_CHANGE
    # B. 成功判定（終了コード優先、Salesforce CLI の非ゼロ成功に備えて出力も確認）
    elif [[ $status -eq 0 ]] || grep -qE "Success|successfully|Succeeded|Deployed|Successfully|status\": 0" "$tmp_out"; then
        is_success=$RET_OK
    fi

    local log_ts
    log_ts=$(date +'%Y-%m-%d %H:%M:%S')
    # ANSI エスケープコード・絵文字を除去してから記録
    # LC_ALL=C により . が任意の1バイトにマッチする（日本語は \xe3〜\xe9 始まりのため除去対象外）
    #   \x1b\[...[a-zA-Z] : ANSI エスケープコード
    #   \xf0...            : 4バイトUTF-8絵文字 (U+10000 以降: 🔥✨ 等)
    #   \xe2..             : 3バイトUTF-8絵文字 (U+2000-U+2FFF: ✅❌⚠️ 等)
    #   \xef\xb8\x8f       : 異体字セレクタ U+FE0F
    LC_ALL=C sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\xf0...//g; s/\xe2..//g; s/\xef\xb8\x8f//g' "$tmp_out" | \
        sed "/./s/^/[${log_ts}] [OUT] /" >> "$LOG_FILE"
    rm -f "$tmp_out"
    return $is_success
}

# ------------------------------------------------------------------------------
# 6. Git フック共通定数
# ------------------------------------------------------------------------------
# sf-hook.sh が生成するラッパーファイルの識別マーカー。
# sf-unhook.sh はこのマーカーで「sf-tools が管理するフックか」を判定してから削除する。
readonly SF_HOOK_MARKER="# Generated by sf-tools: wrapper for pre-push hook"

# ------------------------------------------------------------------------------
# 7. die - エラーログを出力して終了
# ------------------------------------------------------------------------------
# 【使い方】
#   die MESSAGE [EXIT_CODE]
#
# 【引数】
#   MESSAGE   : エラーメッセージ（ログレベル ERROR で出力される）
#   EXIT_CODE : 終了コード。省略時は RET_NG (1)。
#
# 【使用例】
#   check_force_dir || die "force-* ディレクトリ内で実行してください。"
#   run sf org login web ... || die "ログインに失敗しました。"
# ------------------------------------------------------------------------------
die() {
    log "ERROR" "$1"
    exit "${2:-$RET_NG}"
}

# ------------------------------------------------------------------------------
# 8. ユーティリティ関数
# ------------------------------------------------------------------------------

# get_target_org - 接続先組織エイリアスを解決して echo する
# ------------------------------------------------------------------------------
# 【使い方】
#   TARGET=$(get_target_org [ALIAS]) || die "組織を特定できません。"
#
# 【解決の優先順位】
#   1. 引数 ALIAS（明示指定）
#   2. 環境変数 SF_TARGET_ORG（GitHub Actions の secrets 等）
#   3. ローカル接続情報（sf org display の出力）
#
# 【戻り値】
#   RET_OK (0) : エイリアスを echo して正常終了
#   RET_NG (1) : どこからも特定できなかった場合
#
# 【使用例】
#   TARGET_ORG=$(get_target_org "$OPT_TARGET") || die "接続先を特定できません。"
#   TARGET_ORG=$(get_target_org)               || die "接続先を特定できません。"
# ------------------------------------------------------------------------------
get_target_org() {
    local target="$1"
    [[ -z "$target" ]] && target="$SF_TARGET_ORG"
    if [[ -z "$target" ]]; then
        local current_alias
        current_alias=$(run sf org display --json 2>/dev/null | grep '"alias"' | head -n 1 | cut -d '"' -f 4 | tr -d '\r')
        [[ -n "$current_alias" && "$current_alias" != "null" ]] && target="$current_alias"
    fi
    [[ -z "$target" ]] && return $RET_NG
    echo "$target"
    return $RET_OK
}

# check_force_dir - カレントディレクトリが force-* であるか確認する
# ------------------------------------------------------------------------------
# 【使い方】
#   check_force_dir || die "force-* ディレクトリ内で実行してください。"
#
# 【戻り値】
#   RET_OK (0) : カレントディレクトリ名が force- で始まる
#   RET_NG (1) : それ以外
# ------------------------------------------------------------------------------
check_force_dir() {
    [[ "$(basename "$PWD")" =~ ^force- ]] && return $RET_OK
    return $RET_NG
}
