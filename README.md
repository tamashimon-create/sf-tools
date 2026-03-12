# 🚀 sf-tools — Salesforce 開発自動化ツールキット

Salesforce 開発の「面倒な作業」をすべて自動化するシェルスクリプト集です。
環境構築・デプロイ・メタデータ同期・品質チェックまで、コマンド一つで完結します。

---

## 📋 目次

1. [できること](#-できること)
2. [前提条件](#-前提条件)
3. [インストール](#-インストール)
4. [スクリプト一覧](#-スクリプト一覧)
5. [日常の開発フロー](#-日常の開発フロー)
6. [スクリプト詳細](#-スクリプト詳細)
7. [デプロイ対象ファイルの書き方](#-デプロイ対象ファイルの書き方)
8. [ログの確認方法](#-ログの確認方法)
9. [リポジトリ構成](#-リポジトリ構成)
10. [設計思想](#-設計思想)

---

## ✨ できること

| 機能 | 説明 |
|:---|:---|
| ⚡ **ワンコマンド起動** | `sf-start.sh` 一発で接続確認〜VS Code 起動まで完全自動 |
| 🚢 **安全なデプロイ** | テキストにパスを書くだけ。マニフェスト自動生成→デプロイ実行 |
| 🛡️ **push 前の自動検証** | `git push` のたびに Salesforce 組織への検証を自動実行。エラーがあれば push を自動阻止 |
| 🔄 **メタデータ自動同期** | 組織の最新メタデータを取得して Git へ自動コミット・プッシュ |
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

```bash
# ホームディレクトリへ sf-tools をクローン
git clone <sf-tools のリポジトリ URL> ~/sf-tools
```

各 Salesforce プロジェクト側には `sf-install.sh` を配置します。
`sf-start.sh` 実行時に `sf-install.sh` が自動で sf-tools を最新化してくれます。

---

## 📜 スクリプト一覧

| スクリプト | 用途 | よく使うタイミング |
|:---|:---|:---|
| 🟢 `sf-start.sh` | 開発環境の一括セットアップ | **毎朝の作業開始時** |
| 🚢 `sf-release.sh` | デプロイ・検証の実行 | コンポーネントをリリースするとき |
| 🔥 `sf-deploy.sh` | 強制デプロイ（`--release --force` 固定） | Sandbox 切替後・強制上書きしたいとき |
| 🔄 `sf-metasync.sh` | 組織→Git のメタデータ自動同期 | 定期バッチ・組織に直接変更が入ったとき |
| 🔀 `sf-restart.sh` | 接続先組織の切り替え | 別の Sandbox・組織へ乗り換えるとき |
| 🪝 `sf-hook.sh` | pre-push フックのインストール | プロジェクト参加時・フックを有効化したいとき |
| ✂️ `sf-unhook.sh` | pre-push フックの削除 | フックを一時的に無効化したいとき |

---

## 🗓️ 日常の開発フロー

### ① 毎朝の開始

```bash
# force-* ディレクトリ内で実行
bash sf-start.sh
```

自動で以下をすべて実行してくれます:

```
✅ sf-tools を最新化
✅ pre-push フックを有効化
✅ リリース管理ディレクトリ (release/<ブランチ名>/) を作成
✅ Salesforce 組織に接続済みか確認（未接続ならブラウザでログイン）
✅ VS Code の設定ファイルを更新
✅ VS Code を起動
```

---

### ② コンポーネントをデプロイする

**Step 1**: `release/<ブランチ名>/deploy-target.txt` にパスを記入します。

```
# Apex クラス
force-app/main/default/classes/MyClass.cls
force-app/main/default/classes/MyClass.cls-meta.xml

# Lightning Web Component
force-app/main/default/lwc/myComponent
```

**Step 2**: 検証（Dry-Run）で安全確認。

```bash
bash ~/sf-tools/sf-release.sh
```

**Step 3**: 問題なければ本番リリース。

```bash
bash ~/sf-tools/sf-release.sh --release
```

---

### ③ Sandbox を切り替える

```bash
bash sf-restart.sh
```

現在の接続設定をクリアしてブラウザログインを促します。
接続先エイリアスを入力するだけで切り替え完了です。

---

### ④ git push 前の自動検証（フックが有効な場合）

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

```bash
bash ~/sf-tools/sf-metasync.sh
```

組織に直接加えられた変更（手作業の設定変更など）を Git へ自動反映します。

| ステップ | 処理内容 |
|:---:|:---|
| 1️⃣ | 未コミット変更を `git stash` で退避 → `git pull --rebase` でリモートを最新化 |
| 2️⃣ | SGD (`sf sgd source delta`) で前回同期からの差分を解析 → `package.xml` を自動生成 |
| 3️⃣ | 差分ファイルを組織から retrieve（SGD の package.xml 使用） |
| 4️⃣ | 主要メタデータタイプを一括 retrieve して整合性を確保 |
| 5️⃣ | 変更がある場合のみ `git commit` & `git push` |

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
| `sf-release.sh` / `sf-deploy.sh` | `./logs/sf-release.log` |
| `sf-metasync.sh` | `./logs/sf-metasync.log` |
| `sf-restart.sh` | `./logs/sf-restart.log` |

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
├── sf-release.sh              # 🚢 デプロイ・検証の実行
├── sf-deploy.sh               # 🔥 強制デプロイ（--release --force 固定）
├── sf-metasync.sh             # 🔄 Salesforce→Git メタデータ自動同期
├── sf-restart.sh              # 🔀 接続先組織の切り替え
├── sf-hook.sh                 # 🪝 pre-push フックのインストール
└── sf-unhook.sh               # ✂️ pre-push フックの削除
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
