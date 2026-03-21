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
- GitHub CLI で認証済みであること（`gh auth login` で事前にログインしておく）

---

## 📦 Step 1: sf-tools をクローン

```bash
git clone https://github.com/tama-create/sf-tools.git ~/sf-tools
```

PATH に追加して、どこからでも実行できるようにする:

```bash
echo 'export PATH="$HOME/sf-tools:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 🛠️ Step 2: sf-init.sh でセットアップを自動実行

```bash
~/sf-tools/sf-init.sh
```

対話形式で必要な情報を入力するだけで、以下がすべて自動で行われる:

| フェーズ | 内容 |
| :--- | :--- |
| 環境チェック | 必要なツールの確認・GitHub CLI 認証確認 |
| リポジトリ作成 | テンプレートから GitHub リポジトリを作成・クローン |
| Salesforce 接続 | 開発用 Sandbox にブラウザでログイン |
| ファイル生成 | ワークフロー・設定ファイル・Git フックを自動生成 |
| ブランチ構成 | main / staging / develop などの構成を選択・作成 |
| Secrets 登録 | SFDX_AUTH_URL / PAT_TOKEN / Slack トークンを登録 |
| 初回コミット | セットアップ内容をまとめてコミット＆プッシュ |
| Ruleset 設定 | ブランチ保護ルールを自動設定 |

### 入力が必要な項目

実行中に以下を順番に入力・操作する:

1. **GitHub ユーザー名または組織名**（例: `tamashimon`）
2. **プロジェクト名**（`force-` の後の部分、例: `admin` → `force-admin`）
3. **クローン先ディレクトリ**（デフォルト: カレントディレクトリ）
4. **ブランチ構成の選択**（3 / 2 / 1 階層）
5. **各 Salesforce 組織へのブラウザログイン**（本番・ステージング・開発）
6. **GitHub Fine-grained PAT の発行**（ブラウザで操作・トークンを貼り付け）
7. **Slack Bot Token の取得**（ブラウザで操作・トークンを貼り付け）
8. **Slack チャンネル ID の入力**（`C` で始まる文字列）

---

## ✅ Step 3: 動作確認

### 🔄 sf-metasync の確認

GitHub → Actions → 「Salesforce メタデータ自動同期」→ 「Run workflow」で手動実行。
✅ 正常に完了すれば本番組織のメタデータが main に同期される。

### 📝 PR ワークフローの確認

テスト用のブランチを作成して PR を出す:

```bash
cd <クローン先>/force-xxx
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

### ❌ sf-init.sh が途中でエラー終了した

ログファイルを確認する:

```bash
cat ~/sf-tools/logs/sf-init.log
```

エラー内容を確認して対処後、再実行する。すでに作成されたリポジトリは手動で削除してからやり直すこと。

### ❌ sf-metasync が「push declined due to repository rule violations」で失敗

PAT_TOKEN が未設定、または権限不足。Step 2 の PAT_TOKEN 登録を確認。

### ❌ wf-validate / wf-sequence が動かない

ワークフローファイルが `.github/workflows/` にあるか確認。
`sf-start.sh` を再実行すれば未存在のワークフローは自動コピーされる。

### ⚠️ CRLF の警告が出る

Windows 環境での改行コードの違い。動作に影響はない。
`git checkout -- <file>` でリセット可能。

### ⚠️ pre-push フックがプッシュをブロックする

main ブランチへの直接プッシュは禁止。PR 経由でマージすること。
テスト等でバイパスが必要な場合は `git push --no-verify`。
