# sf-tools — Claude Code 向けプロジェクトガイド

> 本書は **Claude Code / Codex などのコード生成 AI 向け** の作業ルール・実装規約・判断基準をまとめた内部ドキュメントです。


## 最重要ルール

### 1. 絶対禁止
- コミット・プッシュは、明示的な指示があるまで実行しないこと
- 「MMOK」と明示された場合のみ、コミット・プッシュ・main マージを一括実行してよい
- 思い込みで実行しないこと。必ずコード・文脈・既存仕様を確認してから実行すること
- `force-*` 側の `main` へのマージは、明示的な指示なしで行わないこと
- **ファイル変更は、ユーザーが「GO」を出してから始めること。変更前に方針・内容を提示して確認を取ること**

### 2. 実行前に必ず確認すること
- 現在の作業ディレクトリ
- 対象ブランチ
- 変更対象ファイル
- 関連テストの有無
- `lib/common.sh` の既存規約

### 3. 変更時の必須ルール
- すべて日本語で対応すること
- コマンド実行は `run` ラッパーを使うこと
  - 例外: `command -v`（存在確認）、`if cmd`（条件チェック）、`VAR=$(cmd)`（変数代入）、バックグラウンド起動（`cmd &`）、意図的エラー無視（`cmd || true`）
  - 例外を使う場合はその行にコメントで理由を記載すること
  - 新規スクリプト作成・変更時は `run` 漏れがないか必ずレビューすること
- Bash で動く実装を維持すること
- 既存仕様を理解してから変更すること
- テストも連動して修正すること

### 4. 変更後に必ずやること
- 関連テストを実行すること
- モック・PATH・設定変更の影響を確認すること
- `.github/workflows/` を変えた場合は Required Status Checks との整合を確認すること
- UTF-8 / LF を維持すること

### 6. デグレ防止チェックリスト
- **既存ロジックを変更する場合**：変更前後の動作差分を必ずコメントまたはコミットメッセージに明記すること
- **「修正」コミットを行う場合**：テスト実行結果（PASS/FAIL 件数）をコミットメッセージに含めること
- **新規 `sf-*.sh` を追加した場合**：対応する `test_sf-*.sh` を作成し、`tests/run_tests.sh` の `TEST_FILES` に追加すること
- **`ask_yn` を含むスクリプトのテスト**：`echo "n" |` または `run_script_with_no()` で stdin を供給すること（ブロック防止）
- **テストスイート全実行**：`bash tests/run_tests.sh` で未登録テストの WARNING が出ないことを確認すること

### 5. このリポジトリ固有の前提
- `~/sf-tools/` に設置して使う
- 実行場所は各 Salesforce プロジェクト (`force-*`) 側
- `sf-hook.sh` は `hooks/pre-push` をコピーする設計
- husky が設定されている場合は `core.hooksPath` を削除する設計

## Compact Instructions
- 対話・解説・要約はすべて日本語で行うこと
- コミット・プッシュは明示的な指示があるまで絶対に実行しないこと
- 「MMOK」と入力された場合のみ、コミット・プッシュ・main マージを一括実行すること。実行前に `gh auth switch --user tama-create` で切り替え、完了後は必ず `gh auth switch --user tamashimon` で元に戻すこと
- コード変更時はテストも必ず連動して修正すること
- 現在進行中のタスク・未解決の問題の状態を保持すること
- `*.md` ファイルには必ず項目番号を付けること。大項目 `1`、中項目 `1.1`、小項目 `1.1.1` の形式
- ユーザーの指示は疑うこと。確定的な指示でも、まずコードや文脈を調べて本当に正しいか確認してから実行すること
- 「記憶して」と言われた場合は、メモリファイル (`memory/`) と `CLAUDE.md` の両方に保存すること
- 「ドキュメントを最新化して」と言われた場合は、リポジトリ内のすべての `*.md` ファイルをアップデートすること

## プロジェクト概要

Salesforce 開発の環境構築と日々の作業を自動化するシェルスクリプト集。  
`~/sf-tools/` に設置し、各 Salesforce プロジェクト (`force-*` ディレクトリ) から呼び出して使う。

## リポジトリ構成

> スクリプト一覧と詳細ツリーは `README.md` のセクション 10 を参照。

Claude が作業上で意識すべき主なディレクトリ・ファイル:

| パス | 役割 |
|---|---|
| `lib/common.sh` | 全スクリプト共通ライブラリ。`log` / `run` / `die` を提供 |
| `hooks/pre-push` | git push フックの実体。`sf-hook.sh` がプロジェクト側へコピーする |
| `templates/` | 各プロジェクトへ配布する雛形（ワークフロー・設定ファイル・release テンプレート）|
| `tests/` | モックベースの単体テスト一式 |
| `tests/integration/` | 実プロジェクト（force-test）を使う統合テスト |

## 共通ライブラリ (`lib/common.sh`)

全スクリプトは `source "$SCRIPT_DIR/lib/common.sh"` の前に以下を `readonly` で定義すること。

| 変数 | 役割 |
|---|---|
| `SCRIPT_NAME` | スクリプト名（拡張子なし） |
| `LOG_FILE` | ログファイルのパス |
| `LOG_MODE` | `NEW` = 上書き / `APPEND` = 追記 |
| `SILENT_EXEC` | `--verbose` / `-v` 指定時のみ 0、それ以外は 1 |

### 主な関数

| 関数 | シグネチャ | 用途 |
|---|---|---|
| `log` | `log LEVEL MESSAGE [DEST]` | 画面・ログファイルに出力 |
| `run` | `run CMD [ARGS...]` | コマンド実行、ログ出力、戻り値判定 |
| `die` | `die MESSAGE [EXIT_CODE]` | エラー終了 |
| `get_target_org` | `get_target_org [ALIAS]` | 対象組織エイリアスを解決して出力 |
| `check_force_dir` | `check_force_dir` | `force-*` ディレクトリか検証 |

### `log` のレベル

`HEADER` / `INFO` / `SUCCESS` / `WARNING` / `ERROR` / `CMD`

### `run` の戻り値

| 定数 | 値 | 意味 |
|---|---|---|
| `RET_OK` | 0 | 成功 |
| `RET_NG` | 1 | 失敗 |
| `RET_NO_CHANGE` | 2 | `NothingToDeploy` など変更なし |

## スクリプト別の処理概要

### sf-start.sh
- 接続先組織を確認し、必要なら `sf org login web`
- `.sf/config.json` / `.sfdx/sfdx-config.json` を更新
- `code .` で VS Code を起動
- バックグラウンドで `sf-install.sh` を実行（フック・リリースDir準備・ツール更新はすべて sf-install.sh が担当）

`FORCE_RELOGIN=1` を付けると再ログインを強制できる。

### sf-release.sh
- `deploy-target.txt` / `remove-target.txt` をもとに `package.xml` を生成
- `sf project deploy start` で検証または本番実行

主なオプション:
- `--release` / `-r`: 本番リリース
- `--no-open` / `-n`: ブラウザを開かない
- `--force` / `-f`: `--ignore-conflicts`
- `--target` / `-t`: 対象組織エイリアス

### sf-metasync.sh
- 本番組織でのみ実行可（Sandbox に接続中の場合はエラー終了）
- main ブランチを最新化して差分を抽出
- `sf sgd source delta` で変更差分を算出
- 差分対象メタデータを retrieve
- 変更があれば commit / push / PR 作成まで進める

対応メタデータ例:
`ApexClass` / `ApexPage` / `LightningComponentBundle` / `CustomObject` / `CustomField` / `Layout` / `FlexiPage` / `Flow` / `PermissionSet` / `CustomLabels`

### sf-install.sh
- `~/sf-tools` を `git pull` で更新
- `.github/workflows/*.yml` をテンプレートから更新
- `config/*.txt` を不足時のみ補充
- `package.json` がある場合は `npm install`
- `sf-hook.sh` で Git Hook をインストール
- `release/<branch>/` と `branch_name.txt` を準備
- 24 時間以上経過していれば `sf-upgrade.sh` をバックグラウンド起動

### sf-deploy.sh
- `sf-release.sh --release --force` のラッパー
- `force-*` 以外では実行禁止
- `main` / `staging` / `develop` ブランチでは実行禁止

### sf-upgrade.sh
- npm / Salesforce CLI / Git を更新
- `sf-install.sh` から 24 時間間隔でバックグラウンド起動される

### sf-hook.sh / sf-unhook.sh
- `sf-hook.sh`: `.git/hooks/pre-push` を上書き生成し、`~/sf-tools/hooks/pre-push` をコピーする
- `sf-unhook.sh`: `.git/hooks/pre-push` を削除する

## 実行環境前提

- Git Bash が使えること
- Salesforce CLI (`sf`) が使えること
- Visual Studio Code (`code`) が PATH に含まれること
- 実行場所は `force-*` ディレクトリ配下であること

## コーディング規約

- すべてのテキストファイルは UTF-8 / LF で統一すること
- Bash / Windows / Mac / Linux 共通で動作すること
- `jq` など追加依存は原則追加しないこと。`awk` / `sed` / `grep` など標準的なコマンドを使うこと
- コマンド実行には例外なく `run` ラッパーを使うこと
- エラー時は `die` で即終了すること
- 一時ファイルは `trap ... EXIT` で確実にクリーンアップすること
- ログレベルは `INFO` / `SUCCESS` / `WARNING` / `ERROR` を使い分けること

## テスト

### モックテスト (`tests/`)

ローカルで実行する通常テスト。実際の Salesforce 組織や Git リモートを使わずに検証する。

```bash
bash tests/run_tests.sh
bash tests/run_tests.sh test_sf-metasync.sh
```

### 統合テスト (`tests/integration/`)

実際の GitHub リポジトリと `force-test` を使う統合テスト。`gh` CLI と管理権限が必要。

```bash
bash ~/sf-tools/tests/integration/test-sequence-check.sh
```

### 主要テスト対象

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

### `test_helper.sh` の前提

セットアップ関数:
- `setup_force_dir`: `force-*` の一時ディレクトリを作成
- `setup_regular_dir`: 通常ディレクトリを作成
- `setup_mock_bin`: モックコマンド用ディレクトリを作成（**呼び出し後に必ず `export MOCK_CALL_LOG="$mb/calls.log"` を実行すること**）
- `setup_release_dir TD [BRANCH]`: `release/<branch>/` を作成
- `setup_mock_home`: `~/sf-tools` をコピーした一時 HOME を作成
- `teardown ARG...`: 指定ディレクトリを削除

モック生成関数:
- `create_mock_git`
- `create_mock_sf`
- `create_mock_npm`
- `create_mock_code`
- `create_all_mocks`

## ブランチ運用

| ブランチ | SF エイリアス | 用途 |
|---|---|---|
| `main` | `prod` | 本番組織 |
| `staging` | `staging` | ステージング組織 |
| `develop` | `develop` | 検証組織 |

- PR フローは `feature/*` → `develop` / `staging` / `main`

## Claude Code への追加指示

- `sf-*.sh` や `lib/common.sh` を変更した場合は、対応する `tests/` のテストも確認・更新すること
- `templates/.github/workflows/` を変えた場合は、`repo-settings.sh` の `required_status_checks.context` と一致しているか確認すること
- `templates/.github/workflows/` の `name:` を変更した場合は、`doc/setup-guide.md` のワークフロー一覧も確認すること
- スクリプトの実装詳細（フロー・ファイルパス・入力項目等）を変更した場合は、以下のドキュメントを確認・更新すること：
  - `sf-init.sh` のフロー・入力項目変更 → `doc/setup-guide.md` セクション3 を確認
  - ファイルパス・ディレクトリ構造変更 → `doc/setup-guide.md` セクション6、`README.md` セクション4.3・10 を確認
  - PAT の種類・取得方法変更 → `doc/setup-guide.md` セクション3.1、`doc/sf-cicd-strategy.md` セクション7.1・8 を確認
  - WF ファイル名・ジョブ名変更 → `doc/setup-guide.md` セクション5、`doc/sf-cicd-strategy.md` セクション4.2 を確認
- ドキュメントの詳細（フロー・パス等）はコードを確認してから記載すること。推測で書かないこと
- 各シェルスクリプト冒頭のコメントは仕様の正本。スクリプトを変更した場合は冒頭コメントも必ず連動して更新すること
- 冒頭コメントは以下の統一フォーマットを守ること:
  ```
  # ==============================================================================
  # sf-xxx.sh - スクリプトの一行説明
  # ==============================================================================
  # 概要説明
  #   1. 処理ステップ1
  #   2. 処理ステップ2
  #
  # 【オプション】
  #   -x, --xxx  : 説明
  # ==============================================================================
  ```

## force-* ローカル環境ディレクトリのルール

`C:\home\dev` 配下に Salesforce プロジェクトのローカル作業ブランチが分かれている。

| ディレクトリ | 作業ブランチ | 用途 |
|---|---|---|
| `C:\home\dev\main\force-test` | `test` | 開発作業用 |
| `C:\home\dev\test\force-test` | `main` | main ブランチ確認用 |
| `C:\home\dev\staging\force-test` | `staging` | staging ブランチ確認用 |

- 開発は基本的に `C:\home\dev\main\force-test` で行うこと
- 検証のために一時的にブランチを切り替えることは許可されるが、作業完了後は元のブランチに戻すこと
