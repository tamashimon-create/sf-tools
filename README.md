# sf-tools

Salesforce 開発における環境構築や日々の作業を自動化するシェルスクリプト集です。
`sf-start.sh` コマンド一つで、開発の準備がすべて整います。

## 1. 概要

- **ワンコマンド・スタートアップ**: `sf-start.sh` を実行するだけで、環境チェック・Salesforce 組織への接続・VS Code の起動までを自動で行います。
- **Git フックによる品質担保**: `git push` の前に Salesforce 組織へのデプロイ検証を自動実行する `pre-push` フックを簡単に導入できます。
- **柔軟なリリース管理**: ブランチごとのテキストファイルにパスを記述するだけで、マニフェストの自動生成からデプロイ・検証まで一括実行します。
- **メタデータの自動同期**: `sf-metasync.sh` で Salesforce 組織の最新メタデータを自動取得して Git へ反映します。

## 2. 使い方

### 初回セットアップ

1. **リポジトリのクローン**
   `sf-tools` をホームディレクトリに配置します。
   ```bash
   git clone <sf-tools のリポジトリ URL> ~/sf-tools
   ```

2. **プロジェクトへの導入**
   開発する Salesforce プロジェクトのルートディレクトリに `sf-install.sh` を配置し実行します。
   `sf-install.sh` は sf-tools 本体の取得とプロジェクトへの設定適用を担います。

### 日常的な開発フロー

```bash
# Salesforce プロジェクトのルートで実行
bash sf-start.sh
```

1. sf-tools の自動更新と Git フックの有効化
2. 現在のブランチに対応するリリース管理ディレクトリの作成
3. Salesforce 組織への接続確認（未接続の場合はブラウザログイン）
4. VS Code 設定の同期と起動

接続する組織を切り替える場合は `sf-restart.sh` を使います。

## 3. スクリプト一覧

| スクリプト | 概要 |
|:---|:---|
| `sf-start.sh` | **メインスクリプト。** 環境セットアップから VS Code 起動までを一括実行します。 |
| `sf-release.sh` | **リリース/検証スクリプト。** デプロイ対象リストからマニフェストを自動生成し、組織へデプロイまたは検証を実行します。 |
| `sf-metasync.sh` | **メタデータ同期スクリプト。** 組織の最新メタデータを取得し、Git リポジトリへ自動コミット・プッシュします。 |
| `sf-hook.sh` | Git の `pre-push` フックを現在のプロジェクトにインストールします。 |
| `sf-unhook.sh` | `pre-push` フックを無効化（削除）します。 |
| `sf-restart.sh` | 接続先の Salesforce 組織を切り替えます。 |
| `hooks/pre-push` | `git push` 時に `sf-release.sh` の検証モードを自動実行するフック本体です。 |

## 4. ワークフロー詳細

### `sf-start.sh` の処理フロー

| ステップ | 処理内容 |
|:---:|:---|
| **1** | `sf-install.sh` を実行して sf-tools を最新化し、`pre-push` フックを有効化します。 |
| **2** | 現在のブランチに対応するリリース管理ディレクトリ (`release/<branch>/`) を作成し、テンプレートを配置します。 |
| **3** | `sf org display` で接続状態を確認します。未接続または `FORCE_RELOGIN=1` の場合はブラウザでログインします。 |
| **4** | 接続した組織のエイリアスを `.sf/config.json` / `.sfdx/sfdx-config.json` に書き込みます。 |
| **5** | `code .` で VS Code を起動します。 |

### `sf-release.sh` のオプション

```bash
bash sf-release.sh [オプション]
```

| オプション | 説明 |
|:---|:---|
| *(なし)* | 検証モード（Dry-Run）で実行（デフォルト） |
| `-r`, `--release` | 本番リリースを実行します |
| `-n`, `--no-open` | ブラウザを開かずに実行します（CI/CD 向け） |
| `-f`, `--force` | コンフリクト検知を無効化して強制上書きします |
| `-j`, `--json` | sf コマンドの出力を JSON 形式にします |
| `-t ALIAS`, `--target ALIAS` | 接続先組織のエイリアスを明示指定します |

**デプロイ対象ファイル**（ブランチごとに管理）:
- `release/<branch>/deploy-target.txt` — 追加・更新するコンポーネントのパス一覧
- `release/<branch>/remove-target.txt` — 削除するコンポーネントのパス一覧

コメント行（`#`）・空行は無視されます。

### `pre-push` フックによる品質保証

1. 開発者が `git push` を実行します。
2. Git が自動で `.git/hooks/pre-push` を起動します。
3. `sf-release.sh` が**検証モード（Dry-Run）**で実行されます。
4. 検証が成功すれば push が続行され、失敗すれば push が中断されます。

フックの導入・解除:
```bash
bash ~/sf-tools/sf-hook.sh    # 導入
bash ~/sf-tools/sf-unhook.sh  # 解除
```

### `sf-metasync.sh` の処理フロー

| ステップ | 処理内容 |
|:---:|:---|
| **1** | `git pull --rebase` でリモートの最新状態を取り込みます（未コミット変更は stash で退避）。 |
| **2** | SGD（`sf sgd source delta`）で前回同期からの差分を解析します。 |
| **3** | 差分ファイルと主要メタデータタイプを組織から取得します。 |
| **4** | 変更がある場合のみ自動コミット・プッシュします。 |

## 5. 前提条件

- Git（Windows 環境では Git Bash を推奨）
- Salesforce CLI（`sf` コマンド）
- Visual Studio Code（`code` コマンドが PATH に含まれること）
- 実行は必ず `force-*` ディレクトリ内から行うこと

## 6. リポジトリ構成

```
sf-tools/
├── lib/
│   └── common.sh          # 全スクリプト共通ライブラリ（ログ・コマンド実行・エラー停止）
├── hooks/
│   └── pre-push           # git push 時に sf-release.sh を呼び出すフック本体
├── templates/
│   ├── deploy-template.txt  # deploy-target.txt の雛形
│   └── remove-template.txt  # remove-target.txt の雛形
├── sf-start.sh
├── sf-release.sh
├── sf-metasync.sh
├── sf-hook.sh
├── sf-unhook.sh
└── sf-restart.sh
```

## 7. 設計思想

- **シンプルさ**: 開発者は `sf-start.sh` を実行するだけでよく、複雑な手順を覚える必要はありません。
- **透明性**: 実行される処理はステップごとにコンソールへ表示され、何が行われているかが明確です。
- **堅牢性**: 各処理でエラーが発生した場合は後続の処理を安全に停止し、エラーメッセージを表示します。
- **環境非依存**: `jq` などの追加ツールに依存せず、Git Bash 標準のコマンド（`awk`・`sed`・`grep` 等）のみで動作します。
