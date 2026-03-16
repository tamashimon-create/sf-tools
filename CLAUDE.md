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
├── sf-start.sh            # メインスクリプト（接続→VS Code 起動→バックグラウンドで環境構築）
├── sf-install.sh          # sf-tools 最新化・ラッパー生成・マージドライバー登録（sf-start.sh から自動呼び出し）
├── sf-release.sh          # デプロイ/検証スクリプト（manifest 自動生成→sf deploy）
├── sf-deploy.sh           # 強制デプロイラッパー（--release --force 固定で sf-release.sh を呼び出す）
├── sf-metasync.sh         # Salesforce メタデータを組織から取得して Git へ自動同期
├── sf-hook.sh             # pre-push フックをプロジェクトにインストール
├── sf-unhook.sh           # pre-push フックを削除
├── sf-restart.sh          # 接続先組織を切り替える（FORCE_RELOGIN=1 で sf-start.sh 呼出）
├── sf-upgrade.sh          # npm / Salesforce CLI / Git をアップデート（sf-install.sh からバックグラウンドで呼び出し）
└── tests/                 # テストスイート（test_helper.sh + 各スクリプトのテストファイル）
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
VS Code を素早く起動することを優先し、重い処理はバックグラウンドで実行する。

**同期処理（VS Code 起動まで）:**
1. `sf org display` で接続確認 → 未接続なら `sf org login web` でログイン
2. `.sf/config.json` / `.sfdx/sfdx-config.json` を更新
3. `code .` で VS Code 起動

**バックグラウンド処理（VS Code 起動後に並行実行）:**
4. `~/sf-tools/sf-install.sh` で sf-tools を最新化
5. `sf-hook.sh` で pre-push フックを有効化
6. 現在のブランチに対応する `release/<branch>/` ディレクトリを作成・`branch_name.txt` を更新

`FORCE_RELOGIN=1` 環境変数で接続済みスキップをバイパス可能。

### sf-release.sh
デプロイ対象リスト → `package.xml` 自動生成 → `sf project deploy start`

**オプション:**
- `--release` / `-r` : 本番リリース（デフォルトは dry-run）
- `--no-open` / `-n` : ブラウザを開かない
- `--force` / `-f` : `--ignore-conflicts`
- `--target` / `-t` : 組織エイリアスを明示指定

**デプロイ対象ファイル:**
- `release/<branch>/deploy-target.txt` : 追加/更新対象（`[files]` / `[members]` 2セクション構成）
- `release/<branch>/remove-target.txt` : 削除対象のパス一覧
- `[files]` セクション: ファイルパスで指定 → `--source-dir` 引数に変換
- `[members]` セクション: `メタデータ種別名:メンバー名` 形式 → `--metadata` 引数に変換（カスタムラベル・プロファイル等の部分デプロイ用）
- 行頭 `#` はコメント、空行は無視される

### sf-metasync.sh
Salesforce **本番組織**の最新メタデータを取得し、**main ブランチ**へ自動反映する。

**実行制約（いずれかに該当する場合はエラー終了）:**
- `main` ブランチ以外で実行した場合
- Sandbox 組織に接続中の場合（`sf org display --json` の `isSandbox` フィールドで判定）
- main ブランチにローカルの未コミット変更がある場合（Salesforce 組織の内容を正とするため）

**処理フロー:**
1. ローカル変更なし確認 → `git fetch` / `git pull --rebase` でリモートの最新状態を取り込む
2. SGD（`sf sgd source delta`）で前回同期からの差分を解析 → `$DELTA_DIR/package/package.xml` 生成
3. SGD の package.xml があれば差分取得、さらに主要メタデータタイプを一括 retrieve
4. `git add -A` → 変更がある場合のみ commit & push → 下流ブランチ（staging → development）へ伝播

**対象メタデータタイプ（再取得）:**
`ApexClass` / `ApexPage` / `LightningComponentBundle` / `CustomObject` / `CustomField` / `Layout` / `FlexiPage` / `Flow` / `PermissionSet` / `CustomLabels`

**戻り値の扱い:**
- 変更あり → `SUCCESS` ログ・リポジトリ更新・下流ブランチへ伝播
- 変更なし → `RET_NO_CHANGE` で正常終了
- エラー → `die` で即停止

### sf-install.sh
`sf-start.sh` のバックグラウンド処理から呼び出される。通常は直接実行しない。

**処理フロー（毎回実行）:**
1. `git pull` で `~/sf-tools` を最新化
2. プロジェクト側のラッパースクリプト（`sf-start.sh` / `sf-restart.sh`）を生成（未存在時のみ）
3. Git マージドライバー（`ours`）をグローバル設定に登録
4. `package.json` があれば `npm install` を実行（依存関係を即時反映するため毎回）

**バックグラウンドでのツール更新（24時間スロットル）:**
5. 前回更新から 24 時間以上経過している場合のみ `sf-upgrade.sh` をバックグラウンド起動

**`_get_mtime()` ヘルパー:**
- macOS (`stat -f "%m"`) と Linux/Git Bash (`stat -c "%Y"`) の両方に対応したファイル更新時刻取得

### sf-deploy.sh
`sf-release.sh` を `--release --force` 固定で呼び出すラッパー。
- `force-*` ディレクトリ外では実行不可
- `main` / `staging` / `development` ブランチでは実行不可（`die` で即停止）
- 追加オプション（`-n`, `-t` など）はそのまま `sf-release.sh` へ転送

### sf-upgrade.sh
npm / Salesforce CLI / Git をアップデートする。`sf-install.sh` から 24 時間スロットルでバックグラウンド起動される。手動実行も可能。

**実行順序（順番に意味がある）:**
1. npm を最新バージョンにアップデート
2. Salesforce CLI (`sf update`) をアップデート
3. Git をアップデート（Windows のみ・最後に実行 ※GUI インストーラーが起動するため）

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

## テスト

`tests/` ディレクトリに各スクリプトのユニットテストがある。モックベースのテストで、実際の Salesforce 組織や Git リモートへの接続なしで実行できる。

**実行方法（C:\Users\tamas\sf-tools から）:**
```bash
bash tests/run_tests.sh           # 全テストを実行
bash tests/run_tests.sh test_sf-metasync.sh  # 特定のテストのみ実行
```

**テストファイル一覧:**
| ファイル | 対象スクリプト |
|---|---|
| `test_sf-unhook.sh` | sf-unhook.sh |
| `test_sf-hook.sh` | sf-hook.sh |
| `test_sf-upgrade.sh` | sf-upgrade.sh |
| `test_sf-install.sh` | sf-install.sh |
| `test_sf-start.sh` | sf-start.sh |
| `test_sf-restart.sh` | sf-restart.sh |
| `test_sf-metasync.sh` | sf-metasync.sh |
| `test_sf-release.sh` | sf-release.sh |
| `test_sf-deploy.sh` | sf-deploy.sh |

**テストの仕組み (`test_helper.sh`):**

セットアップ関数:
- `setup_force_dir` : `force-*` ディレクトリ（`.git/hooks` / `.sf` / `.sfdx` / `logs` 付き）を作成
- `setup_regular_dir` : 通常ディレクトリ（`force-*` でない）を作成
- `setup_mock_bin` : PATH に差し込むモック用ディレクトリを作成。**呼び出し後に必ず `export MOCK_CALL_LOG="$mb/calls.log"` を実行すること**（コマンド置換内での export はサブシェル境界を越えないため）
- `setup_release_dir TD [BRANCH]` : リリースディレクトリ（`release/<branch>/deploy-target.txt` / `remove-target.txt`）を生成
- `setup_mock_home` : `~/sf-tools` 一式をコピーした仮 HOME ディレクトリを作成
- `teardown ARG...` : 可変長引数で受け取った全ディレクトリを一括削除（`rm -rf`）

モック生成関数:
- `create_mock_git` / `create_mock_sf` / `create_mock_npm` / `create_mock_code` : 各コマンドのモック生成
- `create_all_mocks` : 上記4つを一括生成

モック制御環境変数:

| 変数 | 対象 | 説明 |
|---|---|---|
| `MOCK_CALL_LOG` | 全モック | モックが呼び出された引数を記録するログファイルパス |
| `MOCK_GIT_BRANCH` | git | `symbolic-ref` が返すブランチ名（デフォルト: `feature/test`） |
| `MOCK_GIT_DIFF_EXIT` | git | `diff-index` の終了コード（デフォルト: `0`） |
| `MOCK_GIT_DIFF_EXIT_2ND` | git | 2回目以降の `diff-index` に使う終了コード（未設定時は常に `MOCK_GIT_DIFF_EXIT`） |
| `MOCK_GIT_PULL_EXIT` | git | `pull` の終了コード |
| `MOCK_GIT_PUSH_EXIT` | git | `push` の終了コード |
| `MOCK_GIT_REBASE_EXIT` | git | `rebase` の終了コード |
| `MOCK_GIT_MERGE_EXIT` | git | `merge` の終了コード |
| `MOCK_GIT_CHECKOUT_EXIT` | git | `checkout` の終了コード |
| `MOCK_GIT_CHECKOUT_FAIL_BRANCH` | git | このブランチ名で `checkout` したときだけ exit 1 |
| `MOCK_GIT_LS_REMOTE_EXIT` | git | `ls-remote` の終了コード |
| `MOCK_SF_ORG_JSON` | sf | `sf org display` が返す JSON（コンパクト形式で指定、自動で改行展開される） |
| `MOCK_SF_ORG_DISPLAY_EXIT` | sf | `sf org display` の終了コード |
| `MOCK_SF_LOGIN_EXIT` | sf | `sf org login` の終了コード |
| `MOCK_SF_SGD_EXIT` | sf | `sf sgd source delta` の終了コード |
| `MOCK_SF_DEPLOY_EXIT` | sf | `sf project deploy` の終了コード |
| `MOCK_NPM_EXIT` | npm | `npm` コマンドの終了コード |

## ブランチ戦略

- メインブランチ: `main`
- 開発ブランチ: `development`
- PR は `development` → `main`
