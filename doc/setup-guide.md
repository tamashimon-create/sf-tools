# force-* プロジェクト 新規セットアップガイド

新しい Salesforce プロジェクト（force-xxx）を GitHub に作成し、sf-tools と連携させるまでの手順。

---

## 前提条件

> **⚠️ Windows ユーザーへ:** 本ガイドのすべての操作は **Git Bash** で行ってください。コマンドプロンプトや PowerShell は非対応です。

### ローカル環境

- Git（Git Bash 含む）
- GitHub CLI（`gh` コマンド）— `gh auth login` で認証済みであること
- Node.js / npm
- Salesforce CLI（`sf` コマンド）
- Visual Studio Code（`code` コマンドが PATH に含まれること）
  - Salesforce Extension Pack (Expanded) のインストールを推奨
### Salesforce 環境

- 開発用の Sandbox（Developer / Developer Pro）が作成済みであること
- 接続先の Sandbox 名を把握していること

### GitHub アカウント

- リポジトリ作成権限があること

---

## Step 1: sf-tools をクローン

```bash
git clone https://github.com/tama-create/sf-tools.git ~/sf-tools
```

PATH に追加して、どこからでも `sf-start.sh` 等を実行できるようにする:

```bash
# ~/.bashrc または ~/.bash_profile に追加
export PATH="$HOME/sf-tools:$PATH"
```

設定を反映:

```bash
source ~/.bashrc
```

---

## Step 2: Salesforce プロジェクトを作成

```bash
sf project generate --name force-xxx --template standard
cd force-xxx
```

※ 既存プロジェクトの流用ではなく、必ず新規作成すること。

---

## Step 3: GitHub リポジトリを作成

```bash
# 現在のディレクトリを GitHub リポジトリとして作成（プライベート推奨）
git init
gh repo create <org-or-user>/force-xxx --private --source=. --push
```

---

## Step 4: sf-start.sh で初期セットアップ

```bash
sf-start.sh
```

初回実行時は接続先を聞かれるので、開発用 Sandbox の名称を入力する。ブラウザが開くのでログインすること。以降は自動接続される。

初回実行時に以下が自動的に行われる:

- Salesforce 組織への接続＆VS Code 起動
- GitHub Actions ワークフロー（`wf-*.yml`）の生成
- 設定ファイル（`branches.txt` / `metadata.txt`）の生成
- Git フック・マージドライバーの設定

---

## Step 5: ブランチ構成を選択

```bash
sf-branch.sh
```

プロジェクトに合ったブランチ構成を選択すると、必要なブランチが GitHub に自動作成される。

---

## Step 6: metadata.txt を編集

sf-metasync で同期するメタデータタイプを設定:

VS Code またはテキストエディタで `sf-tools/config/metadata.txt` を開く。

不要なメタデータタイプをコメントアウトして、同期対象を絞る。

---

## Step 7: GitHub Secrets を設定

リポジトリの Settings → Secrets and variables → Actions に以下を登録:

### 必須

| Secret | 用途 | 取得方法 |
| :--- | :--- | :--- |
| `SFDX_AUTH_URL_PROD` | 本番組織の認証 URL | `sf org display --verbose --json` → `sfdxAuthUrl` |
| `PAT_TOKEN` | ブランチ保護バイパス用 PAT | GitHub → Settings → Developer Settings → Fine-grained tokens |

### 環境に応じて追加

| Secret | 用途 | 必要な構成 |
| :--- | :--- | :--- |
| `SFDX_AUTH_URL_STG` | ステージング組織の認証 URL | 2階層以上 |
| `SFDX_AUTH_URL_DEV` | 開発組織の認証 URL | 3階層 |

### Slack 通知を使う場合

| Secret | 用途 |
| :--- | :--- |
| `SLACK_BOT_TOKEN` | Slack Bot トークン |
| `SLACK_CHANNEL_ID` | 通知先チャンネル ID |

### PAT_TOKEN の作成手順

1. GitHub → Settings → Developer Settings → Fine-grained tokens
2. Token name: `sf-metasync`（任意）
3. Repository access: 「Only select repositories」→ 対象の force-xxx を選択
4. Permissions: **Contents → Read and write**
5. 「Generate token」→ トークンをコピー
6. 登録:
   ```bash
   gh secret set PAT_TOKEN -R <org-or-user>/force-xxx
   # プロンプトでトークンを貼り付けて Enter
   ```

### 認証 URL の取得方法

```bash
# 対象組織に接続した状態で実行
sf org display --verbose --json | grep sfdxAuthUrl

# 登録
gh secret set SFDX_AUTH_URL_PROD -R <org-or-user>/force-xxx
```

---

## Step 8: リポジトリの Ruleset を設定

`repo-settings.sh` で自動設定するか、手動で設定:

```bash
# 自動設定（推奨）
bash ~/sf-tools/repo-settings.sh
```

**手動で設定する場合（Settings → Rules → Rulesets）:**

### protect-main（main ブランチ）

- 対象: `main`
- ルール:
  - 削除禁止
  - 強制プッシュ禁止
  - Required status checks（以下を設定）:
    - `call / マージ順序を検証（プロモーション順序チェック）`
    - `call / Salesforce 検証（本番反映なし・確認のみ）`
- Bypass actors: Repository admin

### protect-staging（staging ブランチ）※2階層以上の場合

- 対象: `staging`
- ルール: protect-main と同様

---

## Step 9: 初回コミット＆プッシュ

sf-start.sh が生成したファイルをコミット:

```bash
git add -A
git commit -m "chore: sf-tools 初期セットアップ"
git push origin main
```

---

## Step 10: 動作確認

### sf-metasync の確認

GitHub → Actions → 「Salesforce メタデータ自動同期」→ 「Run workflow」で手動実行。
正常に完了すれば本番組織のメタデータが main に同期される。

### PR ワークフローの確認

テスト用のブランチを作成して PR を出す:

```bash
git checkout -b feature/test-setup
git commit --allow-empty -m "test: ワークフロー動作確認"
git push -u origin feature/test-setup
gh pr create --base develop --fill
```

以下が自動実行されることを確認:
- ✅ wf-validate（デプロイ検証）
- ✅ wf-sequence（マージ順序チェック）

---

## ワークフロー一覧（自動生成済み）

| ファイル | トリガー | 目的 |
| :--- | :--- | :--- |
| `wf-validate.yml` | PR 作成・更新時 | dry-run 検証 → PR にコメント |
| `wf-sequence.yml` | main/staging への PR 時 | マージ順序チェック |
| `wf-release.yml` | PR マージ後 | 対応組織へリリース → Slack 通知 |
| `wf-propagate.yml` | main への PR マージ後 | staging / develop へ伝播 |
| `wf-metasync.yml` | 平日毎時（JST 9:00〜19:00） | 本番メタデータを main へ同期 |

---

## ディレクトリ構成（セットアップ後）

```
force-xxx/
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

## トラブルシューティング

### sf-metasync が「push declined due to repository rule violations」で失敗

PAT_TOKEN が未設定、または権限不足。Step 7 の PAT_TOKEN 設定を確認。

### wf-validate / wf-sequence が動かない

ワークフローファイルが `.github/workflows/` にあるか確認。
`sf-start.sh` を再実行すれば未存在のワークフローは自動コピーされる。

### CRLF の警告が出る

Windows 環境での改行コードの違い。動作に影響はない。
`git checkout -- <file>` でリセット可能。

### pre-push フックがプッシュをブロックする

main ブランチへの直接プッシュは禁止。PR 経由でマージすること。
テスト等でバイパスが必要な場合は `git push --no-verify`。
