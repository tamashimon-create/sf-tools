# Salesforce プロジェクトテンプレート

Salesforce プロジェクトの雛形（テンプレート）リポジトリです。
[sf-tools](https://github.com/tama-create/sf-tools) と連携し、デプロイ・メタデータ管理・ブランチ運用を CI/CD で自動化します。

> **このリポジトリを直接クローンして開発に使うことはありません。**
> 新規プロジェクトは `sf-tools` の `sf-init.sh` によって自動生成されます。

---

## 1. このテンプレートについて

`sf-init.sh` を実行すると、このテンプレートをベースに新しい `force-xxxxx` リポジトリが作成されます。
作成されたリポジトリには、以下のファイル・設定・CI/CD ワークフローが最初から含まれた状態になります。

開発者はプロジェクト生成後、Salesforce メタデータの開発に専念できます。

---

## 2. 含まれるファイル

### 2.1 Salesforce 設定

| ファイル | 説明 |
| :--- | :--- |
| `sfdx-project.json` | Salesforce DX プロジェクト定義（パスマッピング等） |
| `config/project-scratch-def.json` | スクラッチ組織の定義ファイル |
| `force-app/` | Salesforce メタデータ格納ディレクトリ |
| `.forceignore` | Salesforce CLI の取得・デプロイ除外リスト |

### 2.2 Git / コード品質

| ファイル | 説明 |
| :--- | :--- |
| `.gitattributes` | 改行コード統一（LF 固定）・マージドライバー設定 |
| `.gitignore` | Git 管理対象外ファイルの定義 |
| `.prettierrc` / `.prettierignore` | コードフォーマッター設定（Apex / XML 対応） |
| `eslint.config.js` | JavaScript 静的解析設定（LWC 対応） |

### 2.3 Node.js

| ファイル | 説明 |
| :--- | :--- |
| `package.json` | npm 依存パッケージ定義 |
| `jest.config.js` | Jest テスト設定（LWC 単体テスト） |

### 2.4 CI/CD ワークフロー

| ファイル | 説明 |
| :--- | :--- |
| `wf-metasync.yml` | 本番組織のメタデータを自動取得して main に同期 |
| `wf-propagate.yml` | main へのマージ後、staging / develop へ自動伝播 |
| `wf-release.yml` | PR マージ時に対象組織へ自動デプロイ |
| `wf-sequence.yml` | PR のマージ順序が正しいか自動チェック |
| `wf-validate.yml` | PR 作成・更新時にデプロイ前検証を自動実行 |

ワークフローのロジックは `tama-create/sf-tools` に集約されており、このテンプレート側はトリガーと Secrets の受け渡しのみを担います。

### 2.5 sf-tools 連携スクリプト

| ファイル | 説明 |
| :--- | :--- |
| `sf-start.sh` | sf-tools の `sf-start.sh` を呼び出すラッパー |
| `sf-restart.sh` | sf-tools の `sf-restart.sh` を呼び出すラッパー |

---

## 3. CI/CD で自動化されること

プロジェクト生成後、以下が自動で行われます。

| タイミング | 自動処理 |
| :--- | :--- |
| PR 作成・更新時 | デプロイ前検証（Apex コンパイル・テスト） |
| main / staging への PR 発行時 | マージ順序チェック |
| PR マージ時 | 対象組織へのデプロイ |
| main へのマージ後 | staging / develop への自動伝播 |
| 平日 09:00〜19:00（毎時） | 本番組織のメタデータを main へ自動同期 |

---

## 4. セットアップ

新規プロジェクトの作成手順は [setup-guide.md](https://github.com/tama-create/sf-tools/blob/main/doc/setup-guide.md) を参照してください。

---

## 5. 備考

- **このテンプレートリポジトリ自体は GitHub Actions を無効化しています。**
  実際の Salesforce 組織と接続していないため、ワークフローを実行する必要がないからです。
  生成された `force-xxxxx` プロジェクトでは Actions は有効であり、上記の自動化がすべて動作します。
- ワークフローのロジック変更・バグ修正は `tama-create/sf-tools` 側で行います。このテンプレートの修正は不要です。
