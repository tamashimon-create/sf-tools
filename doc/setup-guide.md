# 🚀 force-* プロジェクト 新規セットアップガイド

新しい Salesforce プロジェクト（force-xxx）を GitHub に作成し、sf-tools と連携させるまでの手順。

---

## 📋 前提条件

> **⚠️ Windows ユーザーへ:** 本ガイドのすべての操作は **Git Bash** で行ってください。コマンドプロンプトや PowerShell は非対応です。

### 🖥️ ローカル環境

- Git（Git Bash 含む） — ソースコード管理
- GitHub CLI（`gh` コマンド） — GitHub 操作の自動化
- Node.js / npm — ビルドツール・依存管理
- Salesforce CLI（`sf` コマンド） — Salesforce 組織との接続・デプロイ
- Visual Studio Code — コードエディタ
  - Salesforce Extension Pack (Expanded) を事前にインストールしておくこと
- Slack — ワークフローの通知先

### ☁️ Salesforce 環境

- 開発用の Sandbox（Developer / Developer Pro）が作成済みであること
- 接続先の Sandbox 名を把握していること

### 🐙 GitHub アカウント

- リポジトリ作成権限があること

---

## 🔍 Step 0: 環境の動作確認

セットアップを始める前に、必要なツールが正しくインストールされているか確認する:

```bash
git --version        # Git
gh --version         # GitHub CLI
node --version       # Node.js
npm --version        # npm
sf --version         # Salesforce CLI
code --version       # Visual Studio Code
```

✅ すべてバージョンが表示されれば OK。❌ エラーが出る場合は、該当ツールのインストールをやり直すこと。

GitHub CLI の認証確認:

```bash
gh auth status
```

✅ 「Logged in to github.com」と表示されれば OK。未認証の場合は `gh auth login` を実行する。

---

## 📦 Step 1: sf-tools をクローン

```bash
git clone https://github.com/tama-create/sf-tools.git ~/sf-tools
```

PATH に追加して、どこからでも `sf-start.sh` 等を実行できるようにする:

```bash
echo 'export PATH="$HOME/sf-tools:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 🐙 Step 2: プロジェクトを作成

テンプレートから GitHub リポジトリを作成し、ローカルにクローンする:

```bash
# <ユーザー名> は自分の GitHub ユーザー名または組織名に置き換える
gh repo create <ユーザー名>/force-xxx --template tama-create/force-template --private --clone
cd force-xxx
```

> ⚠️ `sf project generate` は使わないこと。プロジェクト構成・ドットファイルはすべてテンプレートに含まれている。

---

## 🛠️ Step 3: sf-start.sh で初期セットアップ

```bash
sf-start.sh
```

初回実行時は接続先を聞かれるので、開発用 Sandbox の名称を入力する。🌐 ブラウザが開くのでログインすること。以降は自動接続される。

初回実行時に以下が自動的に行われる:

- 🔗 Salesforce 組織への接続＆VS Code 起動
- 📄 GitHub Actions ワークフロー（`wf-*.yml`）の生成
- ⚙️ 設定ファイル（`branches.txt` / `metadata.txt`）の生成
- 🪝 Git フック・マージドライバーの設定

---

## 🌿 Step 4: ブランチ構成を選択

```bash
sf-branch.sh
```

実行すると、以下の構成から選択できる:

- **[1] main / staging / develop** — 開発→検証→本番の3段階リリース
- **[2] main / staging** — 検証→本番の2段階
- **[3] main** — 小規模プロジェクト・単独開発向け

選択すると、必要なブランチが GitHub に自動作成される。

---

## 🔐 Step 5: GitHub Secrets を設定

以下の Secret を `gh secret set` コマンドで登録する。
いずれもプロンプトが表示されるので、値を貼り付けて Enter で確定する。

### 🔑 認証 URL の取得と登録

各 Salesforce 組織にログインして認証 URL を取得し、Secret に登録する。
組織ごとに「ログイン → URL 取得 → Secret 登録」を繰り返す:

```bash
# --- 本番組織（必須）---
# 本番は login.salesforce.com（デフォルト）なので --instance-url 不要
sf org login web --alias prod
sf org display --verbose --json --target-org prod | grep sfdxAuthUrl
gh secret set SFDX_AUTH_URL_PROD -R <ユーザー名>/force-xxx

# --- ステージング組織（2階層以上の場合）---
sf org login web --alias staging --instance-url https://test.salesforce.com
sf org display --verbose --json --target-org staging | grep sfdxAuthUrl
gh secret set SFDX_AUTH_URL_STG -R <ユーザー名>/force-xxx

# --- 開発組織（3階層の場合）---
sf org login web --alias develop --instance-url https://test.salesforce.com
sf org display --verbose --json --target-org develop | grep sfdxAuthUrl
gh secret set SFDX_AUTH_URL_DEV -R <ユーザー名>/force-xxx
```

### 🎫 PAT_TOKEN の作成と登録

ワークフローがブランチ保護をバイパスして push するために必要:

1. GitHub → Settings → Developer Settings → Fine-grained tokens
2. Token name: `sf-metasync`（任意）
3. Repository access: 「Only select repositories」→ 対象の force-xxx を選択
4. Permissions: **Contents → Read and write**
5. 「Generate token」→ トークンをコピー
6. 登録:
   ```bash
   gh secret set PAT_TOKEN -R <ユーザー名>/force-xxx
   ```

### 💬 SLACK_BOT_TOKEN の取得と登録

1. [Slack API](https://api.slack.com/apps) にアクセス
2. 「Create New App」→「From scratch」→ App 名とワークスペースを選択
3. 左メニュー「OAuth & Permissions」→ Scopes に `chat:write` を追加
4. 「Install to Workspace」→ 許可する
5. 表示される「Bot User OAuth Token」（`xoxb-` で始まる）をコピー
6. 登録:
   ```bash
   gh secret set SLACK_BOT_TOKEN -R <ユーザー名>/force-xxx
   ```

### 📢 SLACK_CHANNEL_ID の取得と登録

1. Slack で通知先のチャンネルを開く
2. チャンネル名をクリック → 詳細パネルの最下部に「チャンネル ID」が表示される（`C` で始まる文字列）
3. 登録:
   ```bash
   gh secret set SLACK_CHANNEL_ID -R <ユーザー名>/force-xxx
   ```

---

## 🛡️ Step 6: リポジトリの Ruleset を設定

`repo-settings.sh` で自動設定する（推奨）。手動で設定する場合は下記を参照。

```bash
# 自動設定（推奨）
# <ユーザー名>/force-xxx は自分のリポジトリに置き換える
repo-settings.sh <ユーザー名>/force-xxx
```

<details>
<summary>📖 手動で設定する場合（Settings → Rules → Rulesets）</summary>

#### protect-main（main ブランチ）

- 対象: `main`
- ルール:
  - 🚫 削除禁止
  - 🚫 強制プッシュ禁止
  - Required status checks（以下を設定）:
    - `call / マージ順序を検証（プロモーション順序チェック）`
    - `call / Salesforce 検証（本番反映なし・確認のみ）`
- Bypass actors: Repository admin

#### protect-staging（staging ブランチ）※2階層以上の場合

- 対象: `staging`
- ルール: protect-main と同様

</details>

---

## 📤 Step 7: 初回コミット＆プッシュ

Step 3〜4 で生成されたファイルをまとめてコミット:

```bash
# ⚠️ .env や認証情報が含まれていないことを確認
git status

git add -A
git commit -m "chore: sf-tools 初期セットアップ"

# Ruleset 設定済みの場合、status checks 未通過で push が拒否されることがある
# その場合は Step 6 の前にコミット＆プッシュを済ませるか、
# GitHub の Ruleset を一時的に無効化（Disabled）して push する
git push origin main
```

---

## ✅ Step 8: 動作確認

### 🔄 sf-metasync の確認

GitHub → Actions → 「Salesforce メタデータ自動同期」→ 「Run workflow」で手動実行。
✅ 正常に完了すれば本番組織のメタデータが main に同期される。

### 📝 PR ワークフローの確認

テスト用のブランチを作成して PR を出す:

```bash
git checkout -b feature/test-setup
git commit --allow-empty -m "test: ワークフロー動作確認"
git push -u origin feature/test-setup
sf-next.sh
```

`sf-next.sh` がブランチ構成に応じた PR 先を自動判定し、🌐 ブラウザで PR 作成画面を開く。

PR が作成されると以下が自動実行される:
- ✅ wf-validate（デプロイ検証）— すべての PR で実行
- ✅ wf-sequence（マージ順序チェック）— main / staging への PR で実行

---

## 📋 ワークフロー一覧（自動生成済み）

| ファイル | トリガー | 目的 |
| :--- | :--- | :--- |
| `wf-validate.yml` | PR 作成・更新時 | dry-run 検証 → PR にコメント |
| `wf-sequence.yml` | main/staging への PR 時 | マージ順序チェック |
| `wf-release.yml` | PR マージ後 | 対応組織へリリース → Slack 通知 |
| `wf-propagate.yml` | main への PR マージ後 | staging / develop へ伝播 |
| `wf-metasync.yml` | 平日毎時（JST 9:00〜19:00） | 本番メタデータを main へ同期 |

---

## 📁 ディレクトリ構成（セットアップ後）

```
force-xxx/
├── .forceignore                 # Salesforce CLI の無視対象
├── .gitattributes               # 改行コード統一・マージドライバー設定
├── .gitignore                   # Git の無視対象
├── .prettierrc                  # Prettier 設定（Apex/XML 対応）
├── .prettierignore              # Prettier の無視対象
├── .github/
│   └── workflows/
│       ├── wf-metasync.yml
│       ├── wf-propagate.yml
│       ├── wf-release.yml
│       ├── wf-sequence.yml
│       └── wf-validate.yml
├── sf-tools/
│   ├── config/
│   │   ├── branches.txt        # ブランチ階層設定
│   │   └── metadata.txt        # メタデータ同期対象
│   └── release/
│       └── <branch>/
│           ├── branch_name.txt  # 現在のブランチ名
│           ├── deploy-target.txt # デプロイ対象
│           └── remove-target.txt # 削除対象
├── force-app/                   # Salesforce メタデータ
├── sf-start.sh                  # ラッパー（~/sf-tools/sf-start.sh を呼び出す）
└── sf-restart.sh                # ラッパー（~/sf-tools/sf-restart.sh を呼び出す）
```

---

## 🔧 トラブルシューティング

### ❌ sf-metasync が「push declined due to repository rule violations」で失敗

PAT_TOKEN が未設定、または権限不足。Step 5 の PAT_TOKEN 設定を確認。

### ❌ wf-validate / wf-sequence が動かない

ワークフローファイルが `.github/workflows/` にあるか確認。
`sf-start.sh` を再実行すれば未存在のワークフローは自動コピーされる。

### ⚠️ CRLF の警告が出る

Windows 環境での改行コードの違い。動作に影響はない。
`git checkout -- <file>` でリセット可能。

### ⚠️ pre-push フックがプッシュをブロックする

main ブランチへの直接プッシュは禁止。PR 経由でマージすること。
テスト等でバイパスが必要な場合は `git push --no-verify`。
