# 🚀 sf-tools — Salesforce 開発自動化ツールキット

Salesforce 開発の「面倒な作業」をすべて自動化するシェルスクリプト集です。
環境構築・デプロイ・メタデータ同期・品質チェックまで、コマンド一つで完結します。

---

## 📋 目次

1. [できること](#-できること)
2. [前提条件](#-前提条件)
3. [インストール](#-インストール)
4. [Salesforce プロジェクトの作成](#️-salesforce-プロジェクトの作成)
5. [スクリプト一覧](#-スクリプト一覧)
6. [日常の開発フロー](#-日常の開発フロー)
7. [スクリプト詳細](#-スクリプト詳細)
8. [デプロイ対象ファイルの書き方](#-デプロイ対象ファイルの書き方)
9. [ログの確認方法](#-ログの確認方法)
10. [リポジトリ構成](#-リポジトリ構成)
11. [設計思想](#-設計思想)

---

## ✨ できること

| 機能 | 説明 |
|:---|:---|
| ⚡ **ワンコマンド起動** | `sf-start.sh` 一発で接続確認〜VS Code 起動まで完全自動 |
| 🚢 **安全なデプロイ** | テキストにパスを書くだけ。マニフェスト自動生成→デプロイ実行 |
| 🛡️ **push 前の自動検証** | `git push` のたびに Salesforce 組織への検証を自動実行。エラーがあれば push を自動阻止 |
| 🔄 **メタデータ自動同期** | GitHub Actions で定期実行し、組織の最新メタデータを取得してメインブランチを常に最新化 |
| 🔀 **組織の切り替え** | コマンド一つで接続先 Sandbox・組織を切り替え |

---

## 🔧 前提条件

以下がインストール済みであること。

| ツール | 確認コマンド | 用途 |
|:---|:---|:---|
| **Git** | `git --version` | バージョン管理・フック実行 |
| **Salesforce CLI** | `sf --version` | 組織接続・デプロイ実行 |
| **Visual Studio Code** | `code --version` | エディタ起動（PATH に `code` が必要） |

> 💡 **Windows の場合**: Git Bash での実行を推奨します。

> ⚠️ **実行場所**: すべてのスクリプトは `force-*` という名前のディレクトリ内から実行してください。

---

## 📦 インストール

**Step 1**: sf-tools をホームディレクトリへクローン（初回のみ・一度だけ実行）。

```bash
git clone <sf-tools のリポジトリ URL> ~/sf-tools
```

**以降は `force-*` プロジェクトで `sf-start.sh` を実行するだけで OK。**

```bash
cd force-xxxxx
bash sf-start.sh
```

起動のたびに以下が自動で行われます:

```
✅ sf-tools を最新化（git pull）
✅ sf-start.sh / sf-restart.sh をプロジェクトへ再生成
✅ Git / npm / Salesforce CLI をアップデート
✅ Sandbox への接続確認・VS Code 起動
```

---

## 🏗️ Salesforce プロジェクトの作成

### プロジェクト生成コマンド

リポジトリ名は必ず **`force-`** で始めてください（sf-tools が `force-*` ディレクトリを実行条件としています）。

```bash
# Salesforce DX プロジェクトを新規作成
sf project generate --name force-xxxxx

# 例: force-tama という名前で作成する場合
sf project generate --name force-tama
```

### 生成されるディレクトリ構成

```
force-tama/
├── config/
│   └── project-scratch-def.json   # Scratch org の定義ファイル
├── force-app/
│   └── main/
│       └── default/               # メタデータの格納先（Apex・LWC・オブジェクト等）
│           ├── classes/           # Apex クラス
│           ├── lwc/               # Lightning Web Component
│           ├── objects/           # カスタムオブジェクト・項目
│           ├── layouts/           # ページレイアウト
│           ├── flexipages/        # Flexiページ（App Builder）
│           ├── flows/             # フロー
│           └── permissionsets/    # 権限セット
├── scripts/
│   ├── apex/                      # 匿名 Apex スクリプト置き場
│   └── soql/                      # SOQL クエリ置き場
├── .forceignore                   # Salesforce CLI が無視するファイルパターン
├── .gitattributes                 # 行末処理・マージ戦略の設定
├── .gitignore
├── .prettierignore
├── .prettierrc                    # コードフォーマット設定
├── eslint.config.js               # ESLint 設定
├── jest.config.js                 # LWC ユニットテスト設定
├── package.json
└── sfdx-project.json              # Salesforce DX プロジェクト定義（API バージョン等）
```

### sf-tools 導入後の最終構成

sf-tools を導入して開発を進めると、以下のファイル・ディレクトリが追加されます。

```
force-tama/
├── .github/
│   └── workflows/
│       ├── sf-release.yml         # ⭐ GitHub Actions：ブランチへのマージ時に Salesforce 組織へ自動リリース
│       └── sf-sync.yml            # ⭐ GitHub Actions：sf-metasync.sh を定期実行してメインブランチを最新化
├── .vscode/
│   ├── extensions.json            # 推奨拡張機能
│   ├── launch.json                # デバッグ設定
│   └── settings.json              # VS Code プロジェクト設定
├── release/
│   ├── branch_name.txt            # ⭐ リリース対象ブランチ名を記録（release/<ブランチ名>/ のパス解決に使用）
│   ├── development/
│   │   ├── deploy-target.txt      # ⭐ development ブランチのデプロイ対象リスト
│   │   └── remove-target.txt      # ⭐ development ブランチの削除対象リスト
│   └── main/
│       ├── deploy-target.txt      # ⭐ main ブランチのデプロイ対象リスト
│       └── remove-target.txt      # ⭐ main ブランチの削除対象リスト
├── sf-start.sh                    # ⭐ sf-tools/sf-start.sh へのショートカット（.gitignore 済み）
└── sf-restart.sh                  # ⭐ sf-tools/sf-restart.sh へのショートカット（.gitignore 済み）
```

> 📦 **サンプルリポジトリ**: [force-tama](https://github.com/tamashimon-create/force-tama) — 実際に sf-tools を導入した Salesforce プロジェクトの構成例です。

---

## 📜 スクリプト一覧

| スクリプト | 用途 | よく使うタイミング |
|:---|:---|:---|
| 🟢 `sf-start.sh` | 開発環境の一括セットアップ | **毎朝の作業開始時** |
| 🚢 `sf-release.sh` | デプロイ・検証の実行 | コンポーネントをリリースするとき |
| 🔥 `sf-deploy.sh` | 強制デプロイ（`--release --force` 固定） | Sandbox 切替後・強制上書きしたいとき |
| 🔄 `sf-metasync.sh` | 組織→Git のメタデータ自動同期 | **GitHub Actions で定期実行**してメインブランチを常に最新化 |
| 🔀 `sf-restart.sh` | 接続先組織の切り替え | 別の Sandbox・組織へ乗り換えるとき |
| 🪝 `sf-hook.sh` | pre-push フックのインストール | プロジェクト参加時・フックを有効化したいとき |
| ✂️ `sf-unhook.sh` | pre-push フックの削除 | フックを一時的に無効化したいとき |
| ⬆️ `sf-upgrade.sh` | Git / Salesforce CLI のアップデート | ツールを最新版に更新したいとき |
| 🔧 `sf-install.sh` | sf-tools 最新化・ラッパー生成・ツール更新 | **`sf-start.sh` から自動呼び出し**（通常は直接実行不要） |

---

## 🗓️ 日常の開発フロー

### ① 開発ブランチの作成とクローン

```bash
# 1. Salesforce 開発用リポジトリで開発ブランチを作成
git checkout -b feature/my-feature

# 2. 作業ディレクトリへ移動（force-* ディレクトリ）
cd ~/dev/force-myproject
```

---

### ② 開発環境のセットアップ（sf-start.sh）

```bash
# force-* ディレクトリ内で実行
bash sf-start.sh
```

自動で以下をすべて実行してくれます:

```
✅ sf-tools を最新化（git pull）
✅ sf-start.sh / sf-restart.sh をプロジェクトへ再生成
✅ Git / npm / Salesforce CLI をアップデート
✅ pre-push フックを有効化
✅ リリース管理ディレクトリ (release/<ブランチ名>/) を作成
✅ Sandbox への接続確認（未接続ならブラウザでログイン）
✅ VS Code の設定ファイル（接続先 Sandbox）を更新
✅ VS Code を起動 → Sandbox に接続された状態で開発開始！
```

> 💡 **接続済みの場合はログインをスキップ**して即 VS Code が起動します。
> 別の Sandbox に切り替えたい場合は `sf-restart.sh` を使ってください。

---

### ③ コンポーネントをデプロイする

ブランチ構成は案件の Sandbox 数に合わせて選択してください。
push・PR・マージはコマンド・VS Code・TortoiseGit など方法は問いません。

> 💡 **現在の実装構成**: `main` のみ（パターン A）

---

**🟢 パターン A — `main` のみ（Sandbox 1つ・小規模向け）**

```
feature/xxx  →  main
     │            │
  Sandbox       本番組織
```

**Step 1**: `release/feature-xxx/deploy-target.txt` にリリースするコンポーネントのパスを記入。

```
# Apex クラス
force-app/main/default/classes/MyClass.cls
force-app/main/default/classes/MyClass.cls-meta.xml

# Lightning Web Component
force-app/main/default/lwc/myComponent
```

**Step 2**: push → pre-push フックが検証（Dry-Run）を自動実行。

```
[PRE-PUSH] Salesforce 組織への検証(Dry-Run)を自動開始します...
  ↓ 検証成功 → そのまま push 継続 ✅
  ↓ 検証失敗 → push を自動中断 🛑（./logs/sf-release.log に詳細）
```

**Step 3**: `main` へ PR・レビュー・マージ → GitHub Actions が自動で本番組織へリリース。

---

**🔵 パターン B — `development` → `main`（Sandbox 2つ・小〜中規模向け）**

```
feature/xxx  →  development  →  main
     │               │            │
  Sandbox A       Sandbox B     本番組織
```

**Step 1**: `release/feature-xxx/deploy-target.txt` にリリースするコンポーネントのパスを記入。

**Step 2**: push → pre-push フックが検証（Dry-Run）を自動実行。

**Step 3**: `development` へ PR・レビュー・マージ → GitHub Actions が自動で Sandbox B へリリース。動作確認を行う。

**Step 4**: `main` へ PR・レビュー・マージ → GitHub Actions が自動で本番組織へリリース。

---

**🟠 パターン C — `feature` → `development` → `staging` → `main`（Sandbox 3つ以上・チーム開発向け）**

```
feature/xxx  →  development  →  staging  →  main
     │               │              │          │
  Sandbox A       Sandbox B      Sandbox C   本番組織
```

**Step 1**: `development` ブランチから `feature/xxx` を作成。

**Step 2**: `release/feature-xxx/deploy-target.txt` にリリースするコンポーネントのパスを記入。

**Step 3**: push → pre-push フックが検証（Dry-Run）を自動実行。

**Step 4**: `development` へ PR・レビュー・マージ → GitHub Actions が自動で Sandbox B へリリース。動作確認を行う。

**Step 5**: `staging` へ PR・レビュー・マージ → GitHub Actions が自動で Sandbox C へリリース。最終確認を行う。

**Step 6**: `main` へ PR・レビュー・マージ → GitHub Actions が自動で本番組織へリリース。

---

### ④ Sandbox を切り替える

```bash
bash sf-restart.sh
```

現在の接続設定をクリアしてブラウザログインを促します。
接続先エイリアスを入力するだけで切り替え完了です。

---

### ⑤ git push 前の自動検証（フックが有効な場合）

`git push` を実行するだけで自動的に検証が走ります。

```
[PRE-PUSH] Salesforce 組織への検証(Dry-Run)を自動開始します...
  ↓ 検証成功 → そのまま push 継続 ✅
  ↓ 検証失敗 → push を自動中断 🛑（./logs/sf-release.log に詳細）
```

---

## 📖 スクリプト詳細

### 🟢 sf-start.sh — 開発環境の一括セットアップ

```bash
bash sf-start.sh
```

| ステップ | 処理内容 |
|:---:|:---|
| 1️⃣ | `sf-install.sh` を実行して sf-tools を最新化 |
| 2️⃣ | `sf-hook.sh` を実行して pre-push フックを有効化 |
| 3️⃣ | `release/<ブランチ名>/` ディレクトリとリストのテンプレートを作成 |
| 4️⃣ | `sf org display` で接続確認 → 未接続または `FORCE_RELOGIN=1` の場合はブラウザログイン |
| 5️⃣ | `.sf/config.json` / `.sfdx/sfdx-config.json` を接続組織のエイリアスで更新 |
| 6️⃣ | `code .` で VS Code を起動 |

---

### 🚢 sf-release.sh — デプロイ・検証の実行

```bash
bash ~/sf-tools/sf-release.sh [オプション]
```

**オプション一覧:**

| オプション | 説明 | デフォルト |
|:---|:---|:---:|
| *(なし)* | 🔍 **検証モード (Dry-Run)** — 組織に変更を加えない安全な実行 | ✅ |
| `-r` / `--release` | 🚢 **本番リリース** — 組織へ実際にデプロイ | — |
| `-n` / `--no-open` | 🚫 ブラウザを開かない（CI/CD・自動化向け） | — |
| `-f` / `--force` | 💪 コンフリクトを無視して強制デプロイ | — |
| `-j` / `--json` | 📄 sf コマンドの出力を JSON 形式にする | — |
| `-t ALIAS` / `--target ALIAS` | 🎯 接続先組織のエイリアスを明示指定 | — |

**処理フロー:**

```
① deploy-target.txt / remove-target.txt の確認（なければテンプレートを自動生成）
② テキストリストから package.xml / destructiveChanges.xml を自動生成
③ sf project deploy start を実行（--dry-run または本番）
```

> 💡 **ポイント**: `deploy-target.txt` にパスが1件も書かれていない場合は、
> デプロイを実行せず `[WARNING] デプロイ対象がありません` と表示して終了します。

---

### 🔥 sf-deploy.sh — 強制デプロイ

```bash
bash ~/sf-tools/sf-deploy.sh [追加オプション]
```

`sf-release.sh --release --force` を固定で呼び出すショートカットです。

- **`--release`**: 本番リリースモードで実行（Dry-Run しない）
- **`--force`**: `--ignore-conflicts` を付与し、競合を無視して強制デプロイ

**使いどころ:**
- Sandbox を切り替えた直後（ソーストラッキングがリセットされた状態）
- 現在開発中のコンポーネントを強制的にリリースしたいとき

追加オプション（`-n`, `-j`, `-t` など）は `sf-release.sh` へそのまま転送されます。

---

### 🔄 sf-metasync.sh — メタデータ自動同期

**GitHub Actions などのサーバー環境で定期実行することを前提としたスクリプトです。**
Salesforce 組織上で直接行われた設定変更・開発作業を定期的に取得し、
メインブランチを常に組織の最新状態に保ち続けます。

```yaml
# GitHub Actions の設定例（毎日 9:00 JST に自動実行）
on:
  schedule:
    - cron: '0 0 * * *'  # UTC 0:00 = JST 9:00
```

```bash
# 手動実行する場合（force-* ディレクトリ内で）
bash ~/sf-tools/sf-metasync.sh
```

| ステップ | 処理内容 |
|:---:|:---|
| 1️⃣ | 未コミット変更を `git stash` で退避 → `git pull --rebase` でリモートを最新化 |
| 2️⃣ | SGD (`sf sgd source delta`) で前回同期からの差分を解析 → `package.xml` を自動生成 |
| 3️⃣ | 差分ファイルを組織から retrieve（SGD の package.xml 使用） |
| 4️⃣ | 主要メタデータタイプを一括 retrieve して整合性を確保 |
| 5️⃣ | 変更がある場合のみ `git commit` & `git push`、変更なしなら何もしない |

> 💡 **ポイント**: 変更がない場合は commit も push も行わず `SUCCESS` で正常終了します。
> CI のログが不必要に汚れません。

**自動取得されるメタデータタイプ:**

`ApexClass` / `ApexPage` / `LightningComponentBundle` / `CustomObject` / `CustomField` / `Layout` / `FlexiPage` / `Flow` / `PermissionSet` / `CustomLabels`

---

### 🔀 sf-restart.sh — 接続先組織の切り替え

```bash
bash sf-restart.sh
```

現在の接続設定（`.sf/config.json` / `.sfdx/sfdx-config.json`）をクリアし、
`FORCE_RELOGIN=1` フラグを立てて `sf-start.sh` を呼び出します。
新しい組織のエイリアスを入力してブラウザログインするだけで切り替え完了です。

---

### ⬆️ sf-upgrade.sh — 開発ツールのアップデート

```bash
bash ~/sf-tools/sf-upgrade.sh
```

Git と Salesforce CLI を最新バージョンにアップデートします。

| ツール | コマンド |
|:---|:---|
| Git | `git update-git-for-windows` |
| Salesforce CLI | `sf update` |

> 💡 **Node.js** は Windows インストーラーで手動アップデートしてください。

---

### 🪝 sf-hook.sh / ✂️ sf-unhook.sh — Git フック管理

```bash
bash ~/sf-tools/sf-hook.sh    # ✅ フックを有効化
bash ~/sf-tools/sf-unhook.sh  # ❌ フックを無効化
```

**sf-hook.sh の動作:**
- `.git/hooks/pre-push` に `~/sf-tools/hooks/pre-push` を呼び出すラッパーを生成
- ラッパー方式のため、sf-tools 本体を更新するだけで全プロジェクトへ即時反映

**sf-unhook.sh の安全設計:**
- sf-tools が管理するフック（識別マーカー付き）のみ削除
- 手動で設置された別のフックは誤って削除しない

---

## 📝 デプロイ対象ファイルの書き方

`release/<ブランチ名>/` の下に2つのファイルを管理します。

### deploy-target.txt（追加・更新）

```
# ============================================================
# デプロイするコンポーネントのパスを1行1件で記述してください
# # から始まる行はコメントとして無視されます
# ============================================================

# --- Apex クラス ---
force-app/main/default/classes/MyController.cls
force-app/main/default/classes/MyController.cls-meta.xml

# --- Lightning Web Component（ディレクトリごと指定可）---
force-app/main/default/lwc/myComponent

# --- カスタムオブジェクト ---
force-app/main/default/objects/MyObject__c
```

### remove-target.txt（削除）

```
# ============================================================
# 組織から削除するコンポーネントのパスを記述してください
# ============================================================

# force-app/main/default/classes/OldClass.cls
```

> ⚠️ **注意**: `remove-target.txt` に記載したコンポーネントは組織から**完全に削除**されます。
> 記入前によく確認してください。

---

## 🔍 ログの確認方法

各スクリプトはすべての処理をログファイルに記録します。

| スクリプト | ログファイル |
|:---|:---|
| `sf-start.sh` | `./logs/sf-start.log` |
| `sf-install.sh` | `./logs/sf-install.log` |
| `sf-release.sh` | `./logs/sf-release.log` |
| `sf-deploy.sh` | `./logs/sf-deploy.log`（デプロイ本体は `sf-release.log`） |
| `sf-metasync.sh` | `./logs/sf-metasync.log` |
| `sf-restart.sh` | `./logs/sf-restart.log` |
| `sf-upgrade.sh` | `./logs/sf-upgrade.log` |

> 💡 ログは実行ごとにリセットされます（`LOG_MODE=NEW`）。
> エラー発生時はまずこのログを確認してください。

---

## 🗂️ リポジトリ構成

```
sf-tools/
├── lib/
│   └── common.sh              # 全スクリプト共通ライブラリ
│                              #   ログ出力 / コマンド実行ラッパー / エラー停止 等
├── hooks/
│   └── pre-push               # git push 時に sf-release.sh を検証モードで自動実行するフック本体
├── templates/
│   ├── deploy-template.txt    # deploy-target.txt の雛形（初回自動生成時に使用）
│   └── remove-template.txt    # remove-target.txt の雛形（初回自動生成時に使用）
├── sf-start.sh                # 🟢 開発環境の一括セットアップ
├── sf-install.sh              # 🔧 sf-tools 最新化・ラッパー生成・ツール更新（sf-start.sh から自動呼び出し）
├── sf-release.sh              # 🚢 デプロイ・検証の実行
├── sf-deploy.sh               # 🔥 強制デプロイ（--release --force 固定）
├── sf-metasync.sh             # 🔄 Salesforce→Git メタデータ自動同期
├── sf-restart.sh              # 🔀 接続先組織の切り替え
├── sf-hook.sh                 # 🪝 pre-push フックのインストール
├── sf-unhook.sh               # ✂️ pre-push フックの削除
└── sf-upgrade.sh              # ⬆️ Git / Salesforce CLI のアップデート
```

---

## 💡 設計思想

| 方針 | 内容 |
|:---|:---|
| ⚡ **シンプルさ** | 開発者は難しいコマンドを覚える必要なし。`sf-start.sh` を実行するだけ |
| 👁️ **透明性** | 実行した全コマンドと結果がログファイルに記録される |
| 🛡️ **堅牢性** | エラー発生時は後続処理を即停止。中途半端な状態にならない |
| 🌐 **環境非依存** | `jq` などの追加ツール不要。Git Bash 標準コマンドのみで動作（Windows/Mac/Linux 共通） |
| 🔒 **安全優先** | デプロイのデフォルトは Dry-Run。明示的に `--release` を付けない限り組織を変更しない |
