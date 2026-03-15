#!/bin/bash

# ==============================================================================
# sf-release.sh - デプロイ/検証スクリプト
# ==============================================================================
# deploy-target.txt / remove-target.txt からマニフェスト(XML)を自動生成し、
# Salesforce 組織へのリリース（または検証）を実行します。
#
# 【オプション】
#   デフォルト          : 最も安全な「検証モード (Dry-Run)」で実行します。
#   -r, --release       : 実際に組織への本番リリースを実行します。
#   -n, --no-open       : ブラウザを開かずに実行します（CI/CD 等）。
#   -f, --force         : コンフリクト検知を無効化して強制上書きします。
#   -t, --target ALIAS  : 接続先組織のエイリアスを明示的に指定します。
#   -j, --json          : sf コマンドの出力を JSON 形式で表示します。
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 共通ライブラリの必須設定
# ------------------------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0" .sh)
readonly LOG_FILE="./logs/${SCRIPT_NAME}.log"
readonly LOG_MODE="NEW"
readonly SILENT_EXEC=0

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
check_force_dir || die "このスクリプトは 'force-*' ディレクトリ内で実行してください。"

log "HEADER" "リリース・検証処理を開始します (${SCRIPT_NAME}.sh)"

trap 'rm -f ./cmd_out_*.tmp 2>/dev/null' EXIT

# ------------------------------------------------------------------------------
# 4. 実行時引数の解析
# ------------------------------------------------------------------------------
# 初期状態は「最も安全な設定（検証のみ、ブラウザ開く）」に固定
IS_VALIDATE_MODE=1
OPEN_BROWSER=1
IGNORE_CONFLICTS=0
TARGET_ORG=""
JSON_OUTPUT=0

JSON_FLAG=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --validate|--dry-run) IS_VALIDATE_MODE=1 ;;
        --release|-r)         IS_VALIDATE_MODE=0 ;;
        --no-open|-n)         OPEN_BROWSER=0 ;;
        --force|-f)           IGNORE_CONFLICTS=1 ;;
        --target|-t)          TARGET_ORG="$2"; shift ;;
        --json|-j)            JSON_OUTPUT=1; JSON_FLAG=("--json") ;;
        --*)
            die "不明なオプションです: $1"
            ;;
        *)
            die "不明な引数です: $1"
            ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# 5. 接続先組織 (TARGET_ORG) の動的判定
# ------------------------------------------------------------------------------
# 優先順位: 1. -t 引数 > 2. 環境変数 SF_TARGET_ORG > 3. ローカル接続情報（get_target_org が解決）
TARGET_ORG=$(get_target_org "$TARGET_ORG") || die "接続先の組織エイリアスを特定できません。"
log "INFO" "接続先組織: ${TARGET_ORG}"

# ------------------------------------------------------------------------------
# 6. パス定義
# ------------------------------------------------------------------------------
BRANCH_NAME_FILE="release/branch_name.txt"
if [[ -f "$BRANCH_NAME_FILE" ]]; then
    BRANCH_NAME=$(tr -d '\r\n' < "$BRANCH_NAME_FILE")
else
    die "ブランチ情報ファイルが見つかりません (${BRANCH_NAME_FILE})。"
fi

readonly RELEASE_BASE="release"
readonly RELEASE_DIR="${RELEASE_BASE}/${BRANCH_NAME}"
readonly TEMPLATE_DEPLOY="$HOME/sf-tools/templates/deploy-template.txt"
readonly TEMPLATE_REMOVE="$HOME/sf-tools/templates/remove-template.txt"
readonly DEPLOY_LIST="${RELEASE_DIR}/deploy-target.txt"
readonly REMOVE_LIST="${RELEASE_DIR}/remove-target.txt"
readonly DEPLOY_XML="${RELEASE_DIR}/package.xml"
readonly REMOVE_XML="${RELEASE_DIR}/destructiveChanges.xml"

log "INFO" "リリース処理開始 (Target: ${TARGET_ORG}, Branch: ${BRANCH_NAME})"

# ------------------------------------------------------------------------------
# 7. フェーズ定義
# ------------------------------------------------------------------------------

# 【CHECK】対象リストの準備（ディレクトリおよび雛形の自動生成）
phase_check_target() {
    local created=0
    run mkdir -p "$RELEASE_DIR"

    for target in "$DEPLOY_LIST" "$REMOVE_LIST"; do
        if [[ ! -f "$target" ]]; then
            local template="$TEMPLATE_DEPLOY"
            [[ "$target" == "$REMOVE_LIST" ]] && template="$TEMPLATE_REMOVE"
            if [[ -f "$template" ]]; then
                run cp "$template" "$target"
                created=1
            fi
        fi
    done

    # 新規作成された場合はユーザーに記入を促すため停止
    [[ "$created" -eq 1 ]] && die "リストを作成しました。中身を記入して再実行してください。"
    return $RET_OK
}

# 【MANIFEST】テキストリストからマニフェストファイル(XML)を自動生成
phase_generate_manifest() {
    run rm -f "$DEPLOY_XML" "$REMOVE_XML"
    local deploy_args=()
    local remove_args=()

    # 補助関数: リストファイルを走査し、コメント・空行を除外して sf コマンド用引数を組み立てる
    # セクション:
    #   [files]   → --source-dir <パス>    ファイルパス指定（デフォルト）
    #   [members] → --metadata <種別:名前>  メンバー名指定
    process_list() {
        local list=$1; shift; local -n ref=$1
        local section="files"
        while IFS= read -r line || [[ -n "$line" ]]; do
            local clean_line
            clean_line=$(echo "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

            # セクション区切りの検出
            if [[ "$clean_line" == "[files]" ]]; then
                section="files"; continue
            elif [[ "$clean_line" == "[members]" ]]; then
                section="members"; continue
            fi

            # コメント・空行をスキップ
            [[ -z "$clean_line" || "$clean_line" == \#* ]] && continue

            # セクションに応じた引数を追加
            if [[ "$section" == "files" ]]; then
                ref+=("--source-dir" "$clean_line")
            else
                ref+=("--metadata" "$clean_line")
            fi
        done < "$list"
        # TortoiseGit でのサイレントエラー対策:
        # while ループ最終行が空行で false になっても関数として成功を返す
        return 0
    }

    process_list "$DEPLOY_LIST" deploy_args || return $RET_NG
    process_list "$REMOVE_LIST" remove_args || return $RET_NG

    # デプロイ対象がゼロの場合は sf CLI に渡す前に早期終了
    if [[ ${#deploy_args[@]} -eq 0 && ${#remove_args[@]} -eq 0 ]]; then
        log "WARNING" "デプロイ対象がありません。${DEPLOY_LIST} または ${REMOVE_LIST} にパスを記入してください。"
        return $RET_NO_CHANGE
    fi

    # 追加/変更用の package.xml 生成
    if [[ ${#deploy_args[@]} -gt 0 ]]; then
        local files_count members_count
        files_count=$(printf '%s\n' "${deploy_args[@]}" | grep -c "^--source-dir$" || true)
        members_count=$(printf '%s\n' "${deploy_args[@]}" | grep -c "^--metadata$" || true)
        log "INFO" "デプロイ対象を検出 (ファイル: ${files_count}件 / メンバー: ${members_count}件)"
        run sf project generate manifest "${deploy_args[@]}" --output-dir "$RELEASE_DIR" --name "package.xml" "${JSON_FLAG[@]}" || return $RET_NG
    else
        # 対象ゼロでも CLI エラーを防ぐために最小構成の XML を作成
        printf '<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>60.0</version></Package>\n' \
            | run tee "$DEPLOY_XML"
    fi

    # 削除用の destructiveChanges.xml 生成（対象がある場合のみ）
    if [[ ${#remove_args[@]} -gt 0 ]]; then
        run sf project generate manifest "${remove_args[@]}" --output-dir "$RELEASE_DIR" --name "destructiveChanges.xml" "${JSON_FLAG[@]}" \
            || return $RET_NG
    fi

    return $RET_OK
}

# 【RELEASE】Salesforce へのデプロイ/検証の実行
phase_release() {
    local deploy_cmd=("sf" "project" "deploy" "start" "--target-org" "$TARGET_ORG" "--manifest" "$DEPLOY_XML" "${JSON_FLAG[@]}")
    [[ -f "$REMOVE_XML" ]]          && deploy_cmd+=("--pre-destructive-changes" "$REMOVE_XML")
    [[ "$IGNORE_CONFLICTS" -eq 1 ]] && deploy_cmd+=("--ignore-conflicts")

    if [[ "$IS_VALIDATE_MODE" -eq 1 ]]; then
        log "INFO" "検証モード (Dry-Run) を開始します"
        deploy_cmd+=("--dry-run")
    else
        log "INFO" "本番環境へのリリースを実行します！"
    fi

    # インタラクティブ実行時はブラウザで進捗画面を自動表示
    if [[ "$OPEN_BROWSER" -eq 1 ]]; then
        log "INFO" "リリース状況画面をブラウザで表示します..."
        run sf org open --target-org "$TARGET_ORG" --path "lightning/setup/DeployStatus/home" "${JSON_FLAG[@]}"
        log "INFO" "ブラウザ描画待機 (5秒)"
        sleep 5
    fi

    run "${deploy_cmd[@]}"
}

# ------------------------------------------------------------------------------
# 8. メインフロー
# ------------------------------------------------------------------------------
phase_check_target      || die "対象リストの準備に失敗しました。"
log "SUCCESS" "対象リストの確認完了"

phase_generate_manifest || die "マニフェスト生成に失敗しました。"
log "SUCCESS" "マニフェスト生成完了"

# RET_NO_CHANGE (2) は正常終了として扱う
phase_release
res=$?

if [[ $res -eq $RET_OK ]]; then
    log "SUCCESS" "デプロイ/検証が完了しました。"
elif [[ $res -eq $RET_NO_CHANGE ]]; then
    log "SUCCESS" "変更がないため処理をスキップしました。"
else
    die "Salesforce へのデプロイ/検証の実行に失敗しました。"
fi

exit $RET_OK
