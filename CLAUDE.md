# sf-tools — Claude Code 向けプロジェクトガイド

> 本書は **Claude Code / Codex などのコード生成 AI 向け** の作業ルール・実装規約・判断基準をまとめた内部ドキュメントです。

---

## 1. 最重要ルール

### 1.1 絶対禁止

- コミット・プッシュは、明示的な指示があるまで絶対に実行しないこと
- `force-*` 側の `main` へのマージは、明示的な指示なしで行わないこと
- 思い込みで実行しないこと。必ずコード・文脈・既存仕様を確認してから実行すること
- **ファイル変更は、ユーザーが「GO」を出してから始めること。変更前に方針・内容を提示して確認を取ること**
- ユーザーの指示は疑うこと。確定的な指示でも、まずコードや文脈を調べて本当に正しいか確認してから実行すること

### 1.2 作業フロー（必ず守ること）

| フェーズ | やること |
|---|---|
| 変更前 | 方針・内容を提示 → GO を待つ |
| 変更中 | `run` ラッパー必須・日本語コメント・UTF-8/LF 維持 |
| 変更後 | `bash tests/run_tests.sh` で全件 PASS → mm を依頼 |

> **mm の前にテスト全件 PASS は必須。PASS 確認なしの mm 依頼は禁止。**

### 1.3 MMOK 実行手順

「MMOK」と明示された場合のみ、コミット・プッシュ・main マージを一括実行すること。

```bash
gh auth switch --user tama-create   # 実行前に切り替え
# ... コミット・プッシュ・マージ ...
gh auth switch --user tamashimon    # 完了後は必ず元に戻す
```

### 1.4 メモリ・ドキュメント管理

- 「記憶して」と言われた場合は、`memory/` と `CLAUDE.md` の両方に保存すること
- 「ドキュメントを最新化して」と言われた場合は、リポジトリ内のすべての `*.md` をアップデートすること
- `*.md` ファイルには必ず項目番号を付けること（大項目 `1`、中項目 `1.1`、小項目 `1.1.1`）
- 対話・解説・要約はすべて日本語で行うこと
- **`CLAUDE.md` を更新したときは、その都度ブラッシュアップすること。** 増築（追記）を繰り返すと重複・番号ズレが生じるため、更新のたびに構成・重複・番号を見直すこと

---

## 2. コーディング規約

### 2.1 run ラッパー

コマンド実行には必ず `run` ラッパーを使うこと。

**例外（直接実行してよいケース）:**

| パターン | 理由 |
|---|---|
| `command -v cmd` | 存在確認 |
| `if cmd; then` | 条件チェック |
| `VAR=$(cmd)` | 変数代入 |
| `cmd &` | バックグラウンド起動 |
| `cmd \|\| true` | 意図的エラー無視 |

> 例外を使う場合はその行にコメントで理由を記載すること。新規スクリプト作成・変更時は `run` 漏れがないか必ずレビューすること。

### 2.2 その他の規約

- すべてのテキストファイルは UTF-8 / LF で統一すること
  - **新規ファイル作成後は必ず LF 変換すること**（Write ツールは CRLF を生成するため）
  - 変換コマンド: `wsl sed -i 's/\r//' <file>`
- Bash / Windows / Mac / Linux 共通で動作すること
- `jq` など追加依存は原則追加しないこと（`awk` / `sed` / `grep` など標準コマンドを使う）
- エラー時は `die` で即終了すること
- 一時ファイルは `trap ... EXIT` で確実にクリーンアップすること
- ログレベルは `INFO` / `SUCCESS` / `WARNING` / `ERROR` を使い分けること

### 2.3 冒頭コメント（最重要：仕様の正本）

**各シェルスクリプト冒頭のコメントは仕様の正本。スクリプトを変更した場合は冒頭コメントも必ず連動して更新すること。**

統一フォーマット:

```bash
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

---

## 3. テスト規約

### 3.1 実行方法

```bash
bash tests/run_tests.sh                        # 全テスト実行
bash tests/run_tests.sh test_sf-metasync.sh   # 単体実行
bash ~/sf-tools/tests/integration/test-sequence-check.sh  # 統合テスト
```

### 3.2 デグレ防止チェックリスト

- **新規 `sf-*.sh` を追加した場合**：対応する `test_sf-*.sh` を作成し、`tests/run_tests.sh` の `TEST_FILES` に追加すること
- **`ask_yn` を含むスクリプトのテスト**：`echo "n" |` または `run_script_with_no()` で stdin を供給すること（ブロック防止）
- **既存ロジックを変更する場合**：変更前後の動作差分をコメントまたはコミットメッセージに明記すること
- **git 操作を含む新規スクリプトを作成する場合**：`CLAUDE.md` の「スクリプト別の処理概要」に実行フローを先に記載してから実装すること

### 3.3 主要テスト対象

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
| `test_sf-init.sh` | sf-init.sh |

### 3.4 `test_helper.sh` の前提

セットアップ関数:
- `setup_force_dir`: `force-*` の一時ディレクトリを作成
- `setup_regular_dir`: 通常ディレクトリを作成
- `setup_mock_bin`: モックコマンド用ディレクトリを作成（**呼び出し後に必ず `export MOCK_CALL_LOG="$mb/calls.log"` を実行すること**）
- `setup_release_dir TD [BRANCH]`: `release/<branch>/` を作成
- `setup_mock_home`: `~/sf-tools` をコピーした一時 HOME を作成
- `teardown ARG...`: 指定ディレクトリを削除

モック生成関数: `create_mock_git` / `create_mock_sf` / `create_mock_npm` / `create_mock_code` / `create_all_mocks`

---

## 4. プロジェクト概要

Salesforce 開発の環境構築と日々の作業を自動化するシェルスクリプト集。
`~/sf-tools/` に設置し、各 Salesforce プロジェクト (`force-*` ディレクトリ) から呼び出して使う。

### 4.1 このリポジトリ固有の前提

- `~/sf-tools/` に設置して使う
- 実行場所は各 Salesforce プロジェクト (`force-*`) 側
- `sf-hook.sh` は `hooks/pre-push` をコピーする設計
- husky が設定されている場合は `core.hooksPath` を削除する設計

### 4.2 ディレクトリ構成

> スクリプト一覧と詳細ツリーは `README.md` のセクション 10 を参照。

| パス | 役割 |
|---|---|
| `bin/sf-*.sh` | 各種自動化スクリプト本体 |
| `lib/common.sh` | 全スクリプト共通ライブラリ。`log` / `run` / `die` を提供 |
| `phases/init/init-common.sh` | sf-init.sh 専用ヘルパー（`open_browser` / `press_enter` / `register_sf_secret` 等）|
| `phases/init/` | sf-init.sh のサブスクリプト（Phase 01〜08）|
| `hooks/pre-push` | git push フックの実体。`sf-hook.sh` がプロジェクト側へコピーする |
| `templates/` | 各プロジェクトへ配布する雛形（ワークフロー・設定ファイル・release テンプレート）|
| `tests/` | モックベースの単体テスト一式 |
| `tests/integration/` | 実プロジェクト（force-test）を使う統合テスト |

**サブスクリプトのフォルダ構成ルール:**
メインスクリプトからフェーズ単位で呼ばれるサブスクリプトは **`phases/<script名>/`** に配置すること。

- `lib/` はライブラリ専用（再利用可能な関数群）
- `phases/` はフェーズスクリプト専用（1回限りの処理ステップ）
- フォルダ名はメインスクリプトの `sf-` を除いた名前（`init`, `deploy`, `metasync` 等）

### 4.3 ブランチ運用

| ブランチ | SF エイリアス | 用途 |
|---|---|---|
| `main` | `prod` | 本番組織 |
| `staging` | `staging` | ステージング組織 |
| `develop` | `develop` | 検証組織 |

- PR フローは `feature/*` → `develop` / `staging` / `main`

### 4.4 force-* ローカル環境ディレクトリ

`C:\home\dev` 配下に Salesforce プロジェクトのローカル作業ブランチが分かれている。

| ディレクトリ | 作業ブランチ | 用途 |
|---|---|---|
| `C:\home\dev\main\force-test` | `test` | 開発作業用 |
| `C:\home\dev\test\force-test` | `main` | main ブランチ確認用 |
| `C:\home\dev\staging\force-test` | `staging` | staging ブランチ確認用 |

- 開発は基本的に `C:\home\dev\main\force-test` で行うこと
- 検証のために一時的にブランチを切り替えることは許可されるが、作業完了後は元のブランチに戻すこと

---

## 5. 共通ライブラリ (`lib/common.sh`)

全スクリプトは `source "$SCRIPT_DIR/lib/common.sh"` の前に以下を `readonly` で定義すること。

| 変数 | 役割 |
|---|---|
| `SCRIPT_NAME` | スクリプト名（拡張子なし） |
| `LOG_FILE` | ログファイルのパス |
| `LOG_MODE` | `NEW` = 上書き / `APPEND` = 追記 |
| `SILENT_EXEC` | `--verbose` / `-v` 指定時のみ 0、それ以外は 1 |

### 5.1 主な関数

| 関数 | シグネチャ | 用途 |
|---|---|---|
| `log` | `log LEVEL MESSAGE [DEST]` | 画面・ログファイルに出力 |
| `run` | `run CMD [ARGS...]` | コマンド実行、ログ出力、戻り値判定 |
| `die` | `die MESSAGE [EXIT_CODE]` | エラー終了 |
| `get_target_org` | `get_target_org [ALIAS]` | 対象組織エイリアスを解決して出力 |
| `check_force_dir` | `check_force_dir` | `force-*` ディレクトリか検証 |

### 5.2 `log` のレベル

`HEADER` / `INFO` / `SUCCESS` / `WARNING` / `ERROR` / `CMD`

### 5.3 `run` の戻り値

| 定数 | 値 | 意味 |
|---|---|---|
| `RET_OK` | 0 | 成功 |
| `RET_NG` | 1 | 失敗 |
| `RET_NO_CHANGE` | 2 | `NothingToDeploy` など変更なし |

---

## 6. スクリプト別の処理概要

### 6.1 sf-start.sh

- 接続先組織を確認し、必要なら `sf org login web`
- `.sf/config.json` / `.sfdx/sfdx-config.json` を更新
- `code .` で VS Code を起動
- バックグラウンドで `sf-install.sh` を実行（フック・リリースDir準備・ツール更新はすべて sf-install.sh が担当）

`FORCE_RELOGIN=1` を付けると再ログインを強制できる。

### 6.2 sf-release.sh

- `deploy-target.txt` / `remove-target.txt` をもとに `package.xml` を生成
- `sf project deploy start` で検証または本番実行

主なオプション: `--release` / `--no-open` / `--force` / `--target`

### 6.3 sf-metasync.sh

- 本番組織でのみ実行可（Sandbox に接続中の場合はエラー終了）
- main ブランチを最新化して差分を抽出
- `sf sgd source delta` で変更差分を算出
- 差分対象メタデータを retrieve
- 変更があれば commit / push / PR 作成まで進める

### 6.4 sf-install.sh

処理順（順序変更禁止）:
1. `~/sf-tools` を `git pull` で更新
2. `config/*.txt` を不足時のみ補充
3. `sf-hook.sh` で Git Hook をインストール
4. `release/<branch>/` と `branch_name.txt` を準備
5. `package.json` がある場合は `npm install`
6. 24 時間以上経過していれば `sf-upgrade.sh` をバックグラウンド起動

### 6.5 sf-next.sh

現在の feature ブランチが各ターゲットブランチにどの状態かを判定し、次に PR を出すべきブランチを案内する。

判定ロジック（優先順）:
1. `gh pr list --state merged` で直接 PR のマージ済みを確認 → `merged`
2. `git merge-base --is-ancestor` で間接伝播（上位ブランチ経由）を確認 → `synced`
3. `gh pr list --state open` で PR 発行中を確認 → `pr_open`
4. いずれも該当なし → `none`（NEXT_TARGET に設定）

ステータスと表示:
- `merged` → `✓ マージ済み`
- `synced` → `✓ マージ済み（ブランチ同期）`（デプロイ WF 未実行）
- `out_of_order` → `⚠ マージ済み（順序外）`（前に synced/pr_open/none があった merged）
- `pr_open` → `→ PR発行中`
- `none` かつ NEXT_TARGET → `▶ 次のPR先`
- `none` → `✗`

### 6.6 sf-deploy.sh

- `sf-release.sh --release --force` のラッパー
- `force-*` 以外では実行禁止
- `main` / `staging` / `develop` ブランチでは実行禁止

### 6.7 sf-upgrade.sh

- npm / Salesforce CLI / Git を更新
- `sf-install.sh` から 24 時間間隔でバックグラウンド起動される

### 6.8 sf-push.sh

カレントディレクトリ配下だけをコミット＆プッシュする。実行フロー（順序は変更禁止）:

1. origin/main を fetch して現在ブランチにマージ（main ブランチ自身はスキップ）
   - コンフリクト発生時は `merge --abort` してエラー中止
2. カレント配下だけを `git add --all`
3. 変更なしなら WARNING で正常終了
4. `sf-check.sh` でターゲットファイルを検証（エラーなら中止）
5. VS Code を別ウィンドウで開いてコミットメッセージを入力
6. メッセージ未入力なら何もせず正常終了
7. `git commit` → `git push`

### 6.9 sf-update-secret.sh

GitHub Secrets の SFDX_AUTH_URL_* を再登録する。実行フロー（順序は変更禁止）:

1. `force-*` ディレクトリかチェック
2. git remote から対象リポジトリ（OWNER/REPO）を自動取得
3. `sf org display --verbose --json --target-org tama` で sfdxAuthUrl を取得
   - 取得失敗（未接続）→ 「先に sf-start.sh を実行してください」でエラー中止
4. 更新する Secret 一覧・組織情報を表示して確認（y/n）
5. `gh secret set` で3つの Secret を更新（`SFDX_AUTH_URL_PROD` / `STG` / `DEV`）
6. SUCCESS

### 6.10 sf-hook.sh / sf-unhook.sh

- `sf-hook.sh`: `.git/hooks/pre-push` と `.git/hooks/pre-commit` を上書き生成し、`~/sf-tools/hooks/` からコピーする
- `sf-unhook.sh`: `.git/hooks/pre-push` を削除する

### 6.11 sf-init.sh

新規 Salesforce プロジェクトの初期セットアップ。`phases/init/` 配下のフェーズスクリプトを順次実行する。

実行フロー:
1. 環境チェック（ツール確認・GitHub CLI 認証確認）
2. プロジェクト情報の確認（フォルダ構成から自動導出）→ `.sf-init.env` に書き出し
3. リポジトリ作成（gh repo create + git clone）
4. ファイル生成（sf-install.sh）
5. ブランチ構成（sf-branch.sh）
6. Salesforce 認証 URL の設定（JWT 移行時はここだけ差し替え）
7. PAT_TOKEN の設定
8. Slack 連携の設定
9. 初回コミット＆プッシュ
10. GitHub リポジトリ設定・Ruleset の適用

オプション:
- `--resume N`: Phase N から再開（エラー後の再試行）
- `--only N`: Phase N のみ実行（デバッグ用）

---

## 7. ドキュメント連動ルール

スクリプトの実装詳細を変更した場合は以下も確認・更新すること:

| 変更内容 | 確認先 |
|---|---|
| `sf-init.sh` のフロー・入力項目 | `doc/setup-guide.md` セクション3 |
| ファイルパス・ディレクトリ構造 | `doc/setup-guide.md` セクション6、`README.md` セクション4.3・10 |
| PAT の種類・取得方法 | `doc/setup-guide.md` セクション3.1、`doc/sf-cicd-strategy.md` セクション7.1・8 |
| WF ファイル名・ジョブ名 | `doc/setup-guide.md` セクション5、`doc/sf-cicd-strategy.md` セクション4.2 |
| `templates/.github/workflows/` の `name:` | `doc/setup-guide.md` のワークフロー一覧 |
| `templates/.github/workflows/` の内容 | `phases/init/08_repo_rules.sh` の `required_status_checks.context` との整合 |

> ドキュメントの詳細（フロー・パス等）はコードを確認してから記載すること。推測で書かないこと。
