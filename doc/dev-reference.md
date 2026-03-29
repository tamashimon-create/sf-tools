# sf-tools 開発リファレンス

> **本書の位置づけ:** CLAUDE.md のルール・判断基準を補完する詳細リファレンス。
> コーディング中に「どう書くか」を調べるときに参照すること。

---

## 1. クロスプラットフォーム詳細

### 1.1 Bash バージョン要件

- **Bash 4.3 以上を必須とする**（`local -n` nameref 等を使用するため）
- `lib/common.sh` 冒頭で `BASH_VERSINFO` をチェックし、4.3 未満は起動不可としてアップグレードを促す
- 互換ハックで古い環境に対応するよりも、**環境アップグレードを促すことを優先する**（コードの質・メンテナンス性を守るため）
- macOS デフォルト Bash は 3.2 のため、`brew install bash` を案内すること

### 1.2 OS 検出の統一ルール

| 目的 | 使う方法 | 理由 |
|---|---|---|
| GitBash 検出 | `[[ "$OSTYPE" == "msys"* \|\| "$OSTYPE" == "mingw"* ]]` | Bash 組み込み・サブプロセス不要 |
| macOS 検出 | `[[ "$OSTYPE" == "darwin"* ]]` | 同上 |
| WSL 検出 | `grep -qi microsoft /proc/version 2>/dev/null` | `/proc` 非存在環境は `2>/dev/null` で抑制 |
| macOS/Linux 分岐が必要な場合のみ | `uname -s` | `stat` 書式差異など限定的に使用 |

> `uname -s` はサブプロセスを起動するため遅い。OS 検出は原則 `$OSTYPE` に統一すること。

### 1.3 新規スクリプト追加・大きな変更後のチェック

対応必須環境: **GitBash（Windows）/ WSL / macOS / Linux** の4環境で動作することを意識してレビューすること。

- プラットフォーム固有コマンド（`powershell.exe` / `open` / `xdg-open` 等）は `command -v` で存在確認してから使うこと
- `/proc/version` / `/proc/` 配下のファイルは macOS / GitBash に存在しないため `2>/dev/null` を付けること

---

## 2. テスト詳細

### 2.1 主要テスト対象

| ファイル | 対象スクリプト |
|---|---|
| `test_common.sh` | lib/common.sh |
| `test_sf-unhook.sh` | sf-unhook.sh |
| `test_sf-hook.sh` | sf-hook.sh |
| `test_sf-init.sh` | sf-init.sh |
| `test_sf-upgrade.sh` | sf-upgrade.sh |
| `test_sf-install.sh` | sf-install.sh |
| `test_sf-start.sh` | sf-start.sh |
| `test_sf-restart.sh` | sf-restart.sh |
| `test_sf-metasync.sh` | sf-metasync.sh |
| `test_sf-release.sh` | sf-release.sh |
| `test_sf-deploy.sh` | sf-deploy.sh |
| `test_sf-dryrun.sh` | sf-dryrun.sh |
| `test_sf-job.sh` | sf-job.sh |
| `test_sf-next.sh` | sf-next.sh |
| `test_sf-branch.sh` | sf-branch.sh |
| `test_sf-check.sh` | sf-check.sh |
| `test_sf-prepush.sh` | hooks/pre-push |
| `test_sf-push.sh` | sf-push.sh |
| `test_sf-update-secret.sh` | sf-update-secret.sh |

### 2.2 `test_helper.sh` の前提

セットアップ関数:

| 関数 | 用途 |
|---|---|
| `setup_force_dir` | `force-*` の一時ディレクトリを作成 |
| `setup_regular_dir` | 通常ディレクトリを作成 |
| `setup_mock_bin` | モックコマンド用ディレクトリを作成（**呼び出し後に必ず `export MOCK_CALL_LOG="$mb/calls.log"` を実行すること**） |
| `setup_release_dir TD [BRANCH]` | `release/<branch>/` を作成 |
| `setup_mock_home` | `~/sf-tools` をコピーした一時 HOME を作成 |
| `teardown ARG...` | 指定ディレクトリを削除 |

モック生成関数（`create_all_mocks` で一括生成）:

| 関数 | モック対象 |
|---|---|
| `create_mock_git` | git |
| `create_mock_sf` | sf（Salesforce CLI） |
| `create_mock_npm` | npm |
| `create_mock_code` | code（VS Code） |
| `create_mock_gh` | gh（GitHub CLI） |
| `create_mock_node` | node |
| `create_mock_browser` | powershell.exe / xdg-open / open / wslview / start |

> `create_mock_browser` は WSL 環境でブラウザが実際に起動することを防ぐために必須。新規スクリプトがブラウザ・GUI 系コマンドを追加した場合はこのモックに追記すること。

---

## 3. 共通ライブラリ (`lib/common.sh`) 詳細

全スクリプトは `source "$SCRIPT_DIR/lib/common.sh"` の前に以下を `readonly` で定義すること。

| 変数 | 役割 |
|---|---|
| `SCRIPT_NAME` | スクリプト名（拡張子なし） |
| `LOG_FILE` | ログファイルのパス |
| `LOG_MODE` | `NEW` = 上書き / `APPEND` = 追記 |
| `SILENT_EXEC` | `--verbose` / `-v` 指定時のみ 0、それ以外は 1（source 後に自動設定） |

### 3.1 主な関数

| 関数 | シグネチャ | 用途 |
|---|---|---|
| `log` | `log LEVEL MESSAGE [DEST]` | 画面・ログファイルに出力 |
| `run` | `run CMD [ARGS...]` | コマンド実行、ログ出力、戻り値判定 |
| `die` | `die MESSAGE [EXIT_CODE]` | エラーログを出力して終了 |
| `get_target_org` | `get_target_org [ALIAS]` | 対象組織エイリアスを解決して出力 |
| `check_force_dir` | `check_force_dir` | `force-*` ディレクトリか検証 |
| `check_home_dir` | `check_home_dir` | `~/home/{owner}/{company}/` の階層を検証し `GITHUB_OWNER` / `COMPANY_NAME` をセット |
| `check_authorized_user` | `check_authorized_user` | 実行許可ユーザーか確認（マスター固定 + 外部ファイル） |
| `open_browser` | `open_browser URL` | OS 判定してブラウザを開く（WSL/GitBash/macOS/Linux 対応） |
| `read_input` | `read_input VAR [PROMPT]` | readline 対応テキスト入力（矢印キー・BS 有効） |
| `read_key` | `read_key VAR [PROMPT] [VALID]` | 1文字即時入力（Enter 不要・空 Enter 無視・EOF 対応） |
| `press_enter` | `press_enter [MSG]` | Enter 待ち（q で中断） |
| `read_or_quit` | `read_or_quit VAR PROMPT` | テキスト入力（空 Enter 無視・q で中断・EOF 対応） |
| `ask_yn` | `ask_yn "質問"` | Y/N/q 確認（1文字即時入力・q は `die`） |

### 3.2 `log` のレベル

`HEADER` / `INFO` / `SUCCESS` / `WARNING` / `ERROR` / `CMD`

### 3.3 `run` の戻り値

| 定数 | 値 | 意味 |
|---|---|---|
| `RET_OK` | 0 | 成功 |
| `RET_NG` | 1 | 失敗（`logs/error.log` にも記録） |
| `RET_NO_CHANGE` | 2 | `NothingToDeploy` など変更なし |

---

## 4. スクリプト別処理概要

### 4.1 sf-start.sh

- 接続先組織を確認し、必要なら `sf org login web`（WSL では wslview シムを一時生成してブラウザ起動）
- `.sf/config.json` / `.sfdx/sfdx-config.json` を更新
- `code .` で VS Code を起動
- バックグラウンドで `sf-install.sh` を実行（フック・リリースDir準備・ツール更新はすべて sf-install.sh が担当）
- 完了後に `sf-launcher.sh` を起動（`SF_LAUNCHER_ACTIVE=1` で二重起動を防止）

`FORCE_RELOGIN=1` を付けると再ログインを強制できる。

### 4.2 sf-release.sh

- ターゲットファイルをもとに `package.xml` を生成
- `sf project deploy start` で検証または本番実行

主なオプション: `--release` / `--no-open` / `--force` / `--target`

### 4.3 sf-metasync.sh

- 本番組織でのみ実行可（Sandbox に接続中の場合はエラー終了）
- main ブランチを最新化して差分を抽出
- `sf sgd source delta` で変更差分を算出
- 差分対象メタデータを retrieve
- 変更があれば commit / push / PR 作成まで進める

### 4.4 sf-install.sh

処理順（順序変更禁止）:
1. `~/sf-tools` を `git pull` で更新
2. `config/*.txt` を不足時のみ補充
3. `sf-hook.sh` で Git Hook をインストール
4. `release/<branch>/` と `branch_name.txt` を準備
5. `package.json` がある場合は `npm install`
6. 24 時間以上経過していれば `sf-upgrade.sh` をバックグラウンド起動

### 4.5 sf-next.sh

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

### 4.6 sf-dryrun.sh

- `sf-release.sh` のラッパー（オプションなし = dry-run がデフォルト）
- ランチャーから呼ばれる dry-run 専用コマンド

### 4.7 sf-launcher.sh

- `sfl` コマンドで起動するメニュー形式ランチャー
- `lib/common.sh` を source しない standalone 設計（ログ不要・カラー定義を独自に持つ）
- VSCode 内では `sf-start` / `sf-restart` をメニューから除外（`$TERM_PROGRAM == "vscode"` で判定）
- `SF_LAUNCHER_ACTIVE=1` をエクスポートして `sf-start.sh` からの二重起動を防止
- `sflf` エイリアスで fzf モードも利用可能

### 4.8 sf-deploy.sh

- `sf-release.sh --release --force` のラッパー
- `force-*` 以外では実行禁止
- `main` / `staging` / `develop` ブランチでは実行禁止

### 4.9 sf-upgrade.sh

- npm / Salesforce CLI / Git を更新
- `sf-install.sh` から 24 時間間隔でバックグラウンド起動される
- Git の更新は GitBash（`$OSTYPE == "msys"*` / `"mingw"*`）のみ実行（他環境はパッケージマネージャーを案内）

### 4.10 sf-push.sh

カレントディレクトリ配下だけをコミット＆プッシュする。実行フロー（順序は変更禁止）:

1. origin/main を fetch して現在ブランチにマージ（main ブランチ自身はスキップ）
   - コンフリクト発生時は `merge --abort` してエラー中止
2. カレント配下だけを `git add --all`
3. 変更なしなら WARNING で正常終了
4. `sf-check.sh` でターゲットファイルを検証（エラーなら中止）
5. VS Code を別ウィンドウで開いてコミットメッセージを入力
6. メッセージ未入力なら何もせず正常終了
7. `git commit` → `git push`

### 4.11 sf-update-secret.sh

GitHub Secrets の JWT 認証情報を再登録する。実行フロー（順序は変更禁止）:

1. `force-*` ディレクトリかチェック
2. git remote から対象リポジトリ（OWNER/REPO）を自動取得
3. 更新する Secret 一覧・組織情報を表示して確認（y/n）
4. `gh secret set` で JWT 関連 Secret を更新
   （`SF_PRIVATE_KEY` / `SF_CONSUMER_KEY_*` / `SF_USERNAME_*` / `SF_INSTANCE_URL_*`）
5. SUCCESS

### 4.12 sf-hook.sh / sf-unhook.sh

- `sf-hook.sh`: `.git/hooks/pre-push` と `.git/hooks/pre-commit` を上書き生成し、`~/sf-tools/hooks/` からコピーする
- `sf-unhook.sh`: `.git/hooks/pre-push` を削除する

### 4.13 sf-init.sh

新規 Salesforce プロジェクトの初期セットアップ。`phases/init/` 配下のフェーズスクリプトを順次実行する。

実行フロー:
1. 環境チェック（ツール確認・GitHub CLI 認証確認）
2. プロジェクト情報の確認（フォルダ構成から自動導出）→ `.sf-init.env` に書き出し
3. リポジトリ作成（gh repo create + git clone）
4. ファイル生成（sf-install.sh）
5. ブランチ構成（sf-branch.sh）
6. PAT_TOKEN の設定
7. Slack 連携の設定
8. 初回コミット＆プッシュ
9. GitHub リポジトリ設定・Ruleset の適用
10. JWT 認証情報の設定（Salesforce GitHub Secrets 登録）

オプション:
- `--resume N`: Phase N から再開（エラー後の再試行）
- `--only N`: Phase N のみ実行（デバッグ用）

---

## 5. ドキュメント連動ルール

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

---

## 6. スクリプト依存関係マップ

変更の波及確認に使うこと。

| 呼び出し元 | 呼び出し先 | 備考 |
|---|---|---|
| `sf-restart.sh` | `sf-start.sh` | 設定クリア後に start を実行 |
| `sf-start.sh` | `sf-install.sh` | バックグラウンド起動 |
| `sf-start.sh` | `sf-launcher.sh` | install 完了後に起動（二重起動防止あり） |
| `sf-install.sh` | `sf-hook.sh` | フックインストール |
| `sf-install.sh` | `sf-upgrade.sh` | 24h 経過時バックグラウンド起動 |
| `sf-dryrun.sh` | `sf-release.sh` | オプションなし（dry-run）で呼ぶ |
| `sf-deploy.sh` | `sf-release.sh` | `--release --force` 付きで呼ぶ |
| `sf-push.sh` | `sf-check.sh` | コミット前にターゲットファイル検証 |
| `sf-init.sh` | `phases/init/02〜10_*.sh` | フェーズ順に実行 |
| `hooks/pre-push` | `sf-release.sh` | push 時に dry-run 実行 |

---

## 7. デバッグコマンド集

### 7.1 テスト

```bash
bash tests/run_tests.sh                           # 全テスト実行（mm 前に必ず実行）
bash tests/run_tests.sh --changed                 # 変更ファイルに対応するテストのみ（開発中）
bash tests/run_tests.sh test_sf-start.sh          # 単体実行
cat logs/run_tests.log | grep '\[FAIL\]'          # 失敗行のみ抽出
cat logs/error.log                                # run 失敗コマンドのログ
```

### 7.2 Salesforce CLI

```bash
sf org list                                       # 接続済み組織一覧
sf org display --target-org tama                  # 組織情報・接続確認
sf config list                                    # デフォルト組織などの設定確認
cat .sf/config.json                               # ローカル設定ファイル確認
```

### 7.3 Git / GitHub

```bash
git log --oneline -10                             # 最近のコミット
gh run list --limit 5                             # CI ワークフロー実行状況
gh pr list                                        # オープン PR 一覧
git diff HEAD~1                                   # 直前コミットとの差分
```

---

## 8. force-* ローカル環境ディレクトリ

ローカルの作業ディレクトリは以下の構造で配置する。
フォルダツリーから GitHub 組織名・企業名・案件名（ブランチ名）を自動導出できる設計になっている。

```
C:\home\<github-owner>\<company>\<branch>\force-<company>/
         ↑              ↑         ↑
         GitHub組織名   企業名    案件名（ブランチ名）
```

| ディレクトリ例 | 作業ブランチ | 用途 |
|---|---|---|
| `C:\home\tama-create\test\system\force-test` | `system` | 開発作業用 |

- 開発は基本的に上記の `system` ブランチ用ディレクトリで行うこと
- 検証のために一時的にブランチを切り替えることは許可されるが、作業完了後は元のブランチに戻すこと
