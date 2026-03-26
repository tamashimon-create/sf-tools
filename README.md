# sf-tools — Salesforce 開発自動化ツールキット

> **本ドキュメントの範囲:** sf-tools の機能概要・使い方・スクリプト一覧。実装の詳細（フロー・ファイルパス等）はコードのヘッダーコメントを正とします。

Salesforce 開発で毎回発生する環境構築、デプロイ、事前チェック、メタデータ同期をまとめて自動化するシェルスクリプト集です。  
`~/sf-tools` に配置し、各 Salesforce プロジェクト (`force-*` ディレクトリ) から呼び出して使います。

---

## 1. できること

- `sf-start.sh` で開発環境セットアップを一括実行
- `sf-job.sh` でジョブブランチの作成・環境立ち上げを一括実行
- `sf-init.sh` で新規 Salesforce プロジェクトを初期セットアップ
- `sf-branch.sh` でブランチ構成を対話式に設定
- `sf-next.sh` で次に出すべき PR 先ブランチを確認
- `sf-release.sh` で dry-run / 本番デプロイを実行
- `sf-deploy.sh` で強制デプロイを簡易実行
- `sf-hook.sh` / `sf-unhook.sh` で pre-push フックを管理
- `sf-prepush.sh` で push 前に main 同期チェックを実行
- `sf-metasync.sh` で組織の最新メタデータを Git へ自動同期
- `sf-check.sh` でデプロイ対象ファイルの構文を検証
- `sf-restart.sh` で接続先組織を切り替え
- `sf-install.sh` / `sf-upgrade.sh` でツール群を最新化

---

## 2. 前提条件

以下のコマンドが使えること。

| ツール | 確認コマンド | 用途 |
|---|---|---|
| Git | `git --version` | Git Bash / フック / バージョン管理 |
| Salesforce CLI | `sf --version` | 組織接続、デプロイ、retrieve |
| Visual Studio Code | `code --version` | エディタ起動 |

補足:
- Windows では Git Bash での実行を前提とします
- `sf-init.sh` を除くすべてのスクリプトは `force-*` ディレクトリ内から実行してください
- `sf-init.sh` のみ `force-*` の**外**（親ディレクトリ）から実行します

---

## 3. インストール

### 3.1 sf-tools の配置

```bash
git clone <sf-tools のリポジトリ URL> ~/sf-tools
```

### 3.2 PATH の設定（推奨）

`~/.bashrc` に以下を追加すると、どこからでもスクリプト名だけで呼び出せます。

```bash
# sf-tools
export PATH="$HOME/sf-tools/bin:$PATH"

# .sh なしで呼べるエイリアス（任意）
alias sf-start='sf-start.sh'
alias sf-push='sf-push.sh'
alias sf-next='sf-next.sh'
alias sf-job='sf-job.sh'
alias sf-init='sf-init.sh'
alias sf-restart='sf-restart.sh'
alias sfl='sf-launcher.sh'
alias sflf='sf-launcher.sh --fzf'
```

追加後に `source ~/.bashrc` で反映します。

### 3.3 基本の使い方

Salesforce プロジェクト側で `sf-start.sh` を実行します。

```bash
cd force-xxxxx
sf-start.sh        # PATH 設定済みの場合
# または
bash ~/sf-tools/bin/sf-start.sh
```

これで次の処理が自動実行されます。

- 接続先組織の確認
- 必要時のみログイン
- VS Code 起動
- `sf-tools` の更新
- pre-push フックのインストール
- `release/<branch>/` の準備

---

## 4. Salesforce プロジェクトの作成

### 4.1 sf-init.sh で自動セットアップ

`~/home/{owner}/{company}/` ディレクトリで実行します。

```bash
sf-init.sh
```

以下を自動実行します。

1. 環境チェック（ツール・GitHub CLI 認証）
2. プロジェクト情報の確認（フォルダ構成から自動導出）
3. GitHub リポジトリ作成・clone
4. ワークフロー・設定ファイル生成
5. ブランチ構成（develop / staging / main）
6. Salesforce 認証 URL の設定
7. PAT_TOKEN の設定
8. Slack 連携の設定
9. 初回コミット＆プッシュ
10. GitHub リポジトリ設定・Ruleset 適用

> リポジトリ名は必ず `force-` で始めてください。

### 4.2 sf-tools 導入後に追加される主なもの

```text
force-xxxxx/
├── .github/workflows/    ← CI/CD ワークフロー一式
├── .vscode/
└── sf-tools/
    ├── config/           ← metadata.txt / branches.txt
    └── release/
        ├── branch_name.txt
        └── <branch>/
            ├── deploy-target.txt
            └── remove-target.txt
```

---

## 5. 日常の開発フロー

### 5.1 開発ブランチを作る

```bash
git checkout -b feature/my-feature
```

### 5.2 開発環境を立ち上げる

```bash
bash ~/sf-tools/bin/sf-start.sh
```

### 5.3 デプロイ対象を記述する

`release/<branch>/deploy-target.txt` と `remove-target.txt` を更新します。

### 5.4 dry-run で検証する

```bash
bash ~/sf-tools/bin/sf-release.sh
```

### 5.5 必要なら本番デプロイする

```bash
bash ~/sf-tools/bin/sf-release.sh --release
```

### 5.6 push 前の自動チェックを通す

pre-push フックが有効なら、`git push` 時に main 同期チェックが自動実行されます。

---

## 6. スクリプト一覧

| スクリプト | 用途 | 主な利用タイミング |
|---|---|---|
| `sf-start.sh` | 開発環境の一括セットアップ | 開発開始時 |
| `sf-job.sh` | ジョブブランチの作成・環境立ち上げ | 作業開始時 |
| `sf-init.sh` | 新規プロジェクトの初期セットアップ | 新規案件開始時 |
| `sf-branch.sh` | ブランチ構成の設定と作成 | 初期構成時 |
| `sf-next.sh` | 次に出す PR 先ブランチの案内 | PR 作成前 |
| `sf-install.sh` | sf-tools 更新、フック、release 準備 | `sf-start.sh` から自動実行 |
| `sf-release.sh` | dry-run / 本番デプロイ | 日常の検証・リリース |
| `sf-deploy.sh` | 強制デプロイ | 特殊ケース |
| `sf-check.sh` | deploy-target / remove-target の構文確認 | リリース前 |
| `sf-metasync.sh` | 組織 → Git の自動同期 | GitHub Actions / 手動 |
| `sf-restart.sh` | 接続先組織の切り替え | Sandbox 切替時 |
| `sf-hook.sh` | pre-push フック有効化 | フック導入時 |
| `sf-unhook.sh` | pre-push フック削除 | フック停止時 |
| `sf-prepush.sh` | main 同期チェック | pre-push から自動実行 |
| `sf-upgrade.sh` | npm / sf / Git 更新 | ツール更新時 |

---

## 7. スクリプト詳細

### 7.1 `sf-start.sh`

```bash
bash ~/sf-tools/bin/sf-start.sh
```

役割:
- 組織接続確認
- 必要時のみログイン
- `.sf/config.json` / `.sfdx/sfdx-config.json` 更新
- `code .` 実行
- `sf-install.sh` のバックグラウンド実行

### 7.2 `sf-init.sh`

```bash
bash ~/sf-tools/bin/sf-init.sh
```

新規 `force-*` プロジェクトの作成をまとめて行うセットアップスクリプトです。

主な処理:
- GitHub リポジトリ作成とクローン
- `sf-install.sh` による初期ファイル生成
- `sf-branch.sh` によるブランチ構成設定
- GitHub Secrets の登録支援
- 初回コミット、push、Ruleset 設定

補足:
- `force-*` ディレクトリの外で実行します
- Salesforce ログイン、PAT 作成、Slack 設定など一部は対話操作が必要です

### 7.3 `sf-branch.sh`

```bash
bash ~/sf-tools/bin/sf-branch.sh
```

`main / staging / develop` などのブランチ構成を選ぶと、`sf-tools/config/branches.txt` を更新し、必要なブランチを GitHub に作成します。

補足:
- 対話式で 3 段階、2 段階、`main` のみ、から選びます
- 既存ブランチはスキップされます
- `force-*` ディレクトリ内で実行します

### 7.4 `sf-next.sh`

```bash
bash ~/sf-tools/bin/sf-next.sh
```

現在の feature ブランチが `develop` / `staging` / `main` のどこまでマージ済みかを確認し、次に出すべき PR 先ブランチを案内します。

#### 7.4.1 表示ステータス一覧

| 記号 | ステータス | 説明 |
|---|---|---|
| `✓` | マージ済み | 直接 PR をマージ済み（デプロイ WF 実行済み） |
| `✓` | マージ済み（ブランチ同期） | 直接 PR はないが上位ブランチ経由でコード伝播済み。**デプロイ WF は未実行** |
| `⚠` | マージ済み（順序外） | 前のブランチの直接 PR が完了する前にマージ済み。**前のブランチのデプロイは未実行** |
| `→` | PR発行中 | PR を発行済み（マージ待ち） |
| `▶` | 次のPR先 | 次に PR を出すべきブランチ |
| `✗` | 未着手 | まだ PR を出していない |

#### 7.4.2 判定方法

1. `gh pr list --state merged` で現在ブランチ → 対象ブランチへの**直接 PR** を確認 → `マージ済み`
2. `git merge-base --is-ancestor` で間接伝播（上位ブランチ経由）を確認 → `マージ済み（ブランチ同期）`
3. `gh pr list --state open` で PR 発行中を確認 → `PR発行中`
4. いずれも該当なし → `次のPR先` / `未着手`

#### 7.4.3 順序外マージの制約

`develop → staging → main` の順番を守らずにマージした場合、スキップしたブランチへのデプロイは**永久にできません**。

- 上位ブランチ（例: main）にマージすると、コードが下位ブランチ（例: staging）に伝播する
- 伝播後は「差分なし」となり、feature → staging の直接 PR が作成できなくなる
- GitHub Actions のデプロイ WF は直接 PR のマージイベントで起動するため、伝播では WF が動かない

**スキップしたブランチにデプロイしたい場合は、新しいブランチを切って改めて順序通りに PR を出し直す必要があります。**

#### 7.4.4 補足

- 保護ブランチ（`main` / `staging` / `develop`）上では実行できません
- 案内先ブランチの PR 作成画面をブラウザで開くことができます

### 7.5 `sf-release.sh`

```bash
bash ~/sf-tools/bin/sf-release.sh [オプション]
```

主なオプション:

| オプション | 内容 |
|---|---|
| `--release`, `-r` | 本番デプロイ |
| `--no-open`, `-n` | ブラウザを開かない |
| `--force`, `-f` | `--ignore-conflicts` を付与 |
| `--target`, `-t` | 対象組織エイリアス指定 |

デフォルトは dry-run です。

補足:
- `--json`, `-j` で `sf` コマンド出力を JSON 形式で表示できます
- `--verbose`, `-v` でコマンド出力をコンソールにも表示できます

### 7.6 `sf-deploy.sh`

```bash
bash ~/sf-tools/bin/sf-deploy.sh [オプション]
```

`sf-release.sh --release --force` を簡単に呼ぶラッパーです。

追加で使えるオプション:
- `--no-open`, `-n`
- `--target`, `-t`
- `--verbose`, `-v`

### 7.7 `sf-install.sh`

```bash
bash ~/sf-tools/bin/sf-install.sh
```

`sf-tools` 自体の更新と、プロジェクト側の初期ファイル整備を行います。通常は `sf-start.sh` から自動実行されます。

主な処理（順序）:
1. `~/sf-tools` の最新化
2. 設定ファイル雛形の生成
3. pre-push フックのインストール
4. `release/<branch>/` の準備
5. `npm install`（package.json がある場合）
6. 必要に応じた `sf-upgrade.sh` のバックグラウンド実行（24 時間間隔）

### 7.8 `sf-check.sh`

```bash
bash ~/sf-tools/bin/sf-check.sh [deploy-target.txt] [remove-target.txt]
```

`deploy-target.txt` / `remove-target.txt` の構文をチェックします。通常は `sf-release.sh` や `sf-prepush.sh` から自動実行されます。

補足:
- 引数省略時は現在ブランチの `release/<branch>/` 配下を自動解決します
- 終了コードは `0` が正常、`1` が構文エラーです

### 7.9 `sf-metasync.sh`

```bash
bash ~/sf-tools/bin/sf-metasync.sh
```

役割:
- 組織の最新メタデータを取得
- Git へ反映
- 変更がある場合のみ commit / push

主に GitHub Actions からの定期実行を想定しています。

### 7.10 `sf-restart.sh`

```bash
bash ~/sf-tools/bin/sf-restart.sh
```

接続先組織を切り替えたいときに使います。

### 7.11 `sf-hook.sh` / `sf-unhook.sh`

```bash
bash ~/sf-tools/bin/sf-hook.sh
bash ~/sf-tools/bin/sf-unhook.sh
```

役割:
- `sf-hook.sh`: `.git/hooks/pre-push` にフックをインストール
- `sf-unhook.sh`: `.git/hooks/pre-push` を削除

### 7.12 `sf-prepush.sh`

`git push` 前に自動で実行されるチェックスクリプトです。

主な処理:
- `main` への直接 push を禁止
- 自分のブランチのリモート差分を先に同期
- `main` の未取り込み更新を確認し、必要なら自動 rebase
- `sf-check.sh` でターゲットファイル構文を検証

### 7.13 `sf-upgrade.sh`

```bash
bash ~/sf-tools/bin/sf-upgrade.sh
```

npm / Salesforce CLI / Git を更新します。

### 7.14 `sf-job.sh`

```bash
sf-job.sh
```

ジョブブランチの作成・クローン・`sf-start.sh` 起動を一括で行うランチャーです。`~/home/{owner}/{company}/` 階層で実行します。

主な処理:
- ジョブ番号を入力してブランチ名（`feature/{番号}`）を生成
- `git worktree` または `git clone` で作業ディレクトリを作成
- `sf-start.sh` を自動起動

補足:
- `~/home/{owner}/{company}/` 配下で実行してください
- `force-*` ディレクトリの内側では実行できません

---

## 8. デプロイ対象ファイルの書き方

`release/<branch>/` の下に 2 ファイルを置きます。

- `deploy-target.txt`
- `remove-target.txt`

### 8.1 `deploy-target.txt`

```text
[files]
# ファイルパスで指定
force-app/main/default/classes/MyController.cls
force-app/main/default/lwc/myComponent

[members]
# メタデータ種別:メンバー名
# CustomLabel:MyLabel
# Profile:Admin
```

ルール:
- `[files]` と `[members]` の 2 セクション構成
- 行頭 `#` はコメント
- 空行は無視

### 8.2 `remove-target.txt`

```text
# 削除対象のパスを列挙
force-app/main/default/classes/OldClass.cls
```

---

## 9. ログの確認

- `sf-init.sh` のログは `~/sf-tools/logs/sf-init.log`（sf-tools 側）
- それ以外のスクリプトのログは、実行した `force-*` ディレクトリ内に `sf-tools/logs/<スクリプト名>.log` として出力されます

---

## 10. リポジトリ構成

```text
sf-tools/
├── lib/
│   └── common.sh
├── hooks/
│   └── pre-push
├── templates/
│   ├── config/
│   ├── release/
│   └── .github/workflows/
├── doc/
├── tests/
├── sf-init.sh
├── sf-start.sh
├── sf-install.sh
├── sf-branch.sh
├── sf-next.sh
├── sf-release.sh
├── sf-deploy.sh
├── sf-check.sh
├── sf-metasync.sh
├── sf-restart.sh
├── sf-hook.sh
├── sf-prepush.sh
├── sf-unhook.sh
└── sf-upgrade.sh
```

---

## 11. 設計方針

- シンプルなコマンドで毎日の作業を自動化する
- 失敗時はログで原因を追いやすくする
- 追加依存を減らし、Git Bash 前提で動く構成を維持する
- まず dry-run を基本にし、必要時のみ本番実行する
