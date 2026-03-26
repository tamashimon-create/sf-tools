#!/bin/bash
# ==============================================================================
# sf-init.sh - 新規 Salesforce プロジェクトの初期セットアップ
# ==============================================================================
# 新しい force-xxx プロジェクトを GitHub に作成し、sf-tools と連携させるまでの
# 一連のセットアップを自動化する。
#
# 【前提フォルダ構成】
#   ~/home/
#   └── {github-owner}/   ← GitHub ユーザー名（フォルダ名から自動取得）
#       └── {company}/    ← プロジェクト名として使用（例: yamada → force-yamada）
#           └── init/     ← このフォルダをカレントにして実行すること
#
# 【処理フロー】
#   Phase 1: 環境チェック（ツール確認・GitHub CLI 認証確認）
#   Phase 2: プロジェクト情報の確認（フォルダ構成からOWNERとプロジェクト名を自動導出）
#   Phase 3: リポジトリ作成（gh repo create + git clone）
#   Phase 4: ファイル生成（sf-install.sh / sf-hook.sh）
#   Phase 5: ブランチ構成（sf-branch.sh）
#   Phase 6: Salesforce 認証 URL の設定（JWT 移行時はここだけ差し替え）
#   Phase 7: PAT_TOKEN の設定
#   Phase 8: Slack 連携の設定
#   Phase 9: 初回コミット＆プッシュ
#   Phase 10: GitHub リポジトリ設定・Ruleset の適用
#
# 【手動操作が必要なステップ】
#   - Salesforce 組織へのブラウザログイン
#   - GitHub Classic PAT トークンの作成（repo + workflow スコープ）
#   - Slack App の作成・Bot Token の取得
#   - 通知先 Slack チャンネルで Bot を招待（/invite @sf-notify-<プロジェクト名>）
#
# 【使い方】
#   mkdir -p ~/home/{github-owner}/{company}/init
#   cd ~/home/{github-owner}/{company}/init
#   ~/sf-tools/sf-init.sh [--resume N] [--only N]
#
# 【オプション】
#   --resume N : Phase N から再開（エラー後の再試行に使用）
#   --only N   : Phase N のみ実行（デバッグ・単体テストに使用）
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
# sf-init.sh はプロジェクト外から実行するため、ログは sf-tools 配下に記録する
mkdir -p "$HOME/sf-tools/logs" 2>/dev/null || true
readonly LOG_FILE="$HOME/sf-tools/logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"  # 司令塔が起動のたびにログをリセットする

# ------------------------------------------------------------------------------
# 2. 共通ライブラリの読み込み
# ------------------------------------------------------------------------------
# sf-init.sh はプロジェクト外から実行するため、force-* チェックをバイパスする
export SF_INIT_MODE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -f "$COMMON_LIB" ]]; then
    echo "[FATAL ERROR] Library not found: $COMMON_LIB" >&2
    exit 1
fi
source "$COMMON_LIB"

trap '' INT  # Ctrl+C を無効化（子プロセスにも継承される）

# ------------------------------------------------------------------------------
# 3. 引数解析
# ------------------------------------------------------------------------------
ONLY_PHASE=""
RESUME_PHASE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            ONLY_PHASE="$2"
            shift 2
            ;;
        --resume)
            RESUME_PHASE="$2"
            shift 2
            ;;
        *)
            die "不明なオプションです: $1
使い方:
  ~/sf-tools/sf-init.sh              # Phase 1〜8 を順次実行
  ~/sf-tools/sf-init.sh --resume N   # Phase N から最後まで順次実行
  ~/sf-tools/sf-init.sh --only N     # Phase N のみ実行"
            ;;
    esac
done

# 実行範囲を決定する
if [[ -n "$ONLY_PHASE" ]]; then
    START_PHASE=$ONLY_PHASE
    END_PHASE=$ONLY_PHASE
else
    START_PHASE=$RESUME_PHASE
    END_PHASE=10
fi

# ------------------------------------------------------------------------------
# 4. 環境変数の export（各フェーズスクリプトから参照）
# ------------------------------------------------------------------------------
export SF_TOOLS_DIR="$SCRIPT_DIR"
# .sf-init.env はカレントディレクトリ（init フォルダ）に配置する
export SF_INIT_ENV_FILE="${PWD}/.sf-init.env"

# --resume / --only 時以外は .sf-init.env を初期化する
if [[ "$RESUME_PHASE" -eq 1 && -z "$ONLY_PHASE" ]]; then
    : > "$SF_INIT_ENV_FILE"  # 新規実行時は空ファイルにリセット（: > はシェル組み込み）
fi

# ------------------------------------------------------------------------------
# 5. メイン実行フロー（フェーズループ）
# ------------------------------------------------------------------------------
log "HEADER" "新規 Salesforce プロジェクトの初期セットアップを開始します (${SCRIPT_NAME}.sh)"
log "INFO" "セットアップ中は Ctrl+C が無効です。中断するにはターミナルを閉じてください。"
log "INFO" "実行フェーズ: Phase ${START_PHASE} 〜 Phase ${END_PHASE}"

for phase_num in $(seq "$START_PHASE" "$END_PHASE"); do
    phase_script=$(ls "${SCRIPT_DIR}/phases/init/$(printf '%02d' "$phase_num")"_*.sh 2>/dev/null | head -1)
    if [[ -z "$phase_script" ]]; then
        die "Phase ${phase_num} のスクリプトが見つかりません: ${SCRIPT_DIR}/phases/init/"
    fi
    bash "$phase_script" \
        || die "Phase ${phase_num} が失敗しました。
  再開するには: ~/sf-tools/sf-init.sh --resume ${phase_num}"
done

# ------------------------------------------------------------------------------
# 6. 後処理（全フェーズ完了後）
# ------------------------------------------------------------------------------
# .sf-init.env から REPO_DIR を取得（init フォルダ削除の基準に使用）
[[ -f "$SF_INIT_ENV_FILE" ]] && source "$SF_INIT_ENV_FILE"

echo "-------------------------------------------------------"

# init フォルダごと削除（開発時は別途クローンし直すため）
if [[ -n "$REPO_DIR" ]]; then
    INIT_DIR="$(dirname "$REPO_DIR")"   # init フォルダのパス
    cd "$(dirname "$INIT_DIR")" || true
    if [[ -d "$INIT_DIR" ]]; then
        printf "  ▶ init フォルダ（%s）を削除してよいですか？ [Y/N/q]: " "$INIT_DIR"
        answer=""
        read -r answer
        if [[ "$answer" == "q" || "$answer" == "Q" ]]; then
            log "INFO" "削除をスキップしました。手動で削除してください: ${INIT_DIR}"
        elif [[ "$answer" =~ ^[Yy]$ ]]; then
            run rm -rf "$INIT_DIR"
            # Windows 環境では rm -rf で空フォルダが残る場合があるため cmd でも試みる
            if [[ -d "$INIT_DIR" ]] && command -v cmd > /dev/null 2>&1; then
                win_path=$(cygpath -w "$INIT_DIR" 2>/dev/null || echo "$INIT_DIR")  # VAR=$(cmd) のため run 不要
                cmd //c "rmdir /s /q \"$win_path\"" 2>/dev/null || true  # 失敗しても続行
            fi
            if [[ -d "$INIT_DIR" ]]; then
                log "WARNING" "init フォルダが残っています。手動で削除してください: rm -rf '${INIT_DIR}'"
            else
                log "SUCCESS" "init フォルダを削除しました。"
            fi
        else
            log "INFO" "削除をスキップしました。手動で削除してください: ${INIT_DIR}"
        fi
    fi
fi

log "HEADER" "セットアップが完了しました"

exit $RET_OK
