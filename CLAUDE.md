# sf-tools — Claude Code 向けプロジェクトガイド

## Language Settings
- すべての対話、解説、要約は**日本語**で行ってください。
- ターミナルの出力やエラー内容の解説も日本語で説明してください。
- コードコメントやドキュメント作成も、特に指示がない限り日本語（日本語環境用）でお願いします。

## プロジェクト概要

Salesforce 開発の環境構築・日々の作業を自動化するシェルスクリプト集。
`~/sf-tools/` に設置し、各 Salesforce プロジェクト（`force-*` ディレクトリ）から呼び出して使う。

## リポジトリ構成

```
sf-tools/
├── lib/
│   └── common.sh          # 全スクリプト共通ライブラリ（ログ・コマンド実行・エラー停止）
├── hooks/
│   └── pre-push           # git push 時に sf-release.sh を dry-run で呼び出す実体フック
├── templates/
│   ├── deploy-template.txt  # deploy-target.txt の雛形
│   └── remove-template.txt  # remove-target.txt の雛形
├── sf-start.sh            # メインスクリプト（環境構築→接続→VS Code 起動）
├── sf-install.sh          # sf-tools 最新化・ラッパー生成・ツール更新（sf-start.sh から自動呼び出し）
├── sf-release.sh          # デプロイ/検証スクリプト（manifest 自動生成→sf deploy）
├── sf-deploy.sh           # 強制デプロイラッパー（--release --force 固定で sf-release.sh を呼び出す）
├── sf-metasync.sh         # Salesforce メタデータを組織から取得して Git へ自動同期
├── sf-hook.sh             # pre-push フックをプロジェクトにインストール
├── sf-unhook.sh           # pre-push フックを削除
├── sf-restart.sh          # 接続先組織を切り替える（FORCE_RELOGIN=1 で sf-start.sh 呼出）
└── sf-upgrade.sh          # Git / Salesforce CLI を手動でアップデート
```

## 共通ライブラリ (lib/common.sh)

全スクリプトは `source "$SCRIPT_DIR/lib/common.sh"` の前に以下を `readonly` で宣言する。

| 変数 | 意味 |
|---|---|
| `SCRIPT_NAME` | スクリプト名（拡張子なし） |
| `LOG_FILE` | `./logs/${SCRIPT_NAME}.log` |
| `LOG_MODE` | `NEW` = 実行ごとにログリセット / `APPEND` = 追記 |
| `SILENT_EXEC` | `1` = コマンド stdout はログのみ、`0` = 画面にも表示 |

### 主要関数

| 関数 | シグネチャ | 説明 |
|---|---|---|
| `log` | `log LEVEL MESSAGE [DEST]` | 画面(色付き)＆ログファイルへ出力 |
| `run` | `run CMD [ARGS...]` | コマンド実行・成功判定・ログ記録。命令置換 `$(run ...)` でも使用可 |
| `die` | `die MESSAGE [EXIT_CODE]` | ERROR ログを出して即終了 |
| `get_target_org` | `get_target_org [ALIAS]` | 接続先エイリアスを解決して echo |
| `check_force_dir` | `check_force_dir` | `force-*` ディレクトリ内かチェック |

#### log のレベル

`HEADER` / `INFO` / `SUCCESS` / `WARNING` / `ERROR` / `CMD`

#### run の戻り値

| 定数 | 値 | 意味 |
|---|---|---|
| `RET_OK` | 0 | 成功 |
| `RET_NG` | 1 | 失敗 |
| `RET_NO_CHANGE` | 2 | 変更なし（NothingToDeploy）|

## スクリプト別の処理概要

### sf-start.sh
1. `~/sf-tools/sf-install.sh` で sf-tools を最新化
2. `sf-hook.sh` で pre-push フックを有効化
3. 現在のブランチに対応する `release/<branch>/` ディレクトリを作成
4. `sf org display` で接続確認 → 未接続なら `sf org login web` でログイン
5. `.sf/config.json` / `.sfdx/sfdx-config.json` を更新
6. `code .` で VS Code 起動

`FORCE_RELOGIN=1` 環境変数で接続済みスキップをバイパス可能。

### sf-release.sh
デプロイ対象リスト → `package.xml` 自動生成 → `sf project deploy start`

**オプション:**
- `--release` / `-r` : 本番リリース（デフォルトは dry-run）
- `--no-open` / `-n` : ブラウザを開かない
- `--force` / `-f` : `--ignore-conflicts`
- `--json` / `-j` : JSON 出力
- `--target` / `-t` : 組織エイリアスを明示指定

**デプロイ対象ファイル:**
- `release/<branch>/deploy-target.txt` : 追加/更新対象のパス一覧
- `release/<branch>/remove-target.txt` : 削除対象のパス一覧
- コメント行（`#`）・空行は無視される

### sf-metasync.sh
Salesforce 組織の最新メタデータを取得し、Git リポジトリへ自動反映する。

**処理フロー:**
1. `git fetch` / `git pull --rebase` でリモートの最新状態を取り込む（未コミット変更は stash で退避）
2. SGD（`sf sgd source delta`）で前回同期からの差分を解析 → `$DELTA_DIR/package/package.xml` 生成
3. SGD の package.xml があれば差分取得、さらに主要メタデータタイプを一括 retrieve
4. `git add -A` → 変更がある場合のみ commit & push

**対象メタデータタイプ（再取得）:**
`ApexClass` / `ApexPage` / `LightningComponentBundle` / `CustomObject` / `CustomField` / `Layout` / `FlexiPage` / `Flow` / `PermissionSet` / `CustomLabels`

**戻り値の扱い:**
- 変更あり → `SUCCESS` ログ・リポジトリ更新
- 変更なし → `RET_NO_CHANGE` で正常終了
- エラー → `die` で即停止

### sf-install.sh
`sf-start.sh` から自動呼び出しされる。通常は直接実行しない。

**処理フロー:**
1. `git pull` で `~/sf-tools` を最新化
2. プロジェクト側のラッパースクリプト（`sf-start.sh` / `sf-restart.sh`）を再生成
3. Git（Windows のみ）/ npm / Salesforce CLI をアップデート
4. Git マージドライバー（`ours`）を登録
5. `package.json` があれば `npm install` を実行

### sf-deploy.sh
`sf-release.sh` を `--release --force` 固定で呼び出すラッパー。
- `main` / `staging` / `development` ブランチでは実行不可（`die` で即停止）
- 追加オプション（`-n`, `-j`, `-t` など）はそのまま `sf-release.sh` へ転送

### sf-upgrade.sh
Git と Salesforce CLI を手動でアップデートする。
- Git: `git update-git-for-windows`（Windows のみ）
- Salesforce CLI: `sf update`

### sf-hook.sh / sf-unhook.sh
- `sf-hook.sh` : `.git/hooks/pre-push` を上書き生成（`~/sf-tools/hooks/pre-push` を呼び出すラッパー）
- `sf-unhook.sh` : `.git/hooks/pre-push` を削除

## 実行前提条件

- Git（Git Bash 推奨 on Windows）
- Salesforce CLI（`sf` コマンド）
- Visual Studio Code（`code` コマンドが PATH に含まれること）
- 実行は必ず `force-*` ディレクトリ内から行う

## コーディング規約

- 全スクリプトは Bash。Windows/Mac/Linux 共通で動作すること
- `jq` など追加ツールに依存しない。`awk` / `sed` / `grep` など Git Bash 標準コマンドのみ使用
- コマンド実行には例外なく `run` ラッパーを使用（直接呼び出し禁止）
- エラー時は `die` で即停止（後続処理に流さない）
- 一時ファイルは `trap ... EXIT` で確実にクリーンアップ
- ログレベルの使い分け: 処理開始=`INFO`、正常完了=`SUCCESS`、問題あり=`WARNING`/`ERROR`

## ブランチ戦略

- メインブランチ: `main`
- 開発ブランチ: `development`
- PR は `development` → `main`
