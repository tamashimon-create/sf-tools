# Salesforce Git 運用・CI/CD 基本戦略＆設計思想

## 1. 目的

Salesforce メタデータの「パッチ形式」の特性を最大限に活かし、Git と各組織（Production / Staging / Dev）の整合性を保つ。

**設計上の 3 つの柱:**

1. **本番が正（Source of Truth）** — 本番組織の変更を SGD で高速検知し、人間を介さず全環境へ即座に波及させる「自己修復型同期」
2. **スター型プロモート** — feature ブランチから各環境へ個別に PR を送る。環境ブランチ間の直接マージは禁止
3. **Reusable Workflow** — CI/CD ロジックを sf-tools リポジトリに集約し、各プロジェクト（force-*）は薄い caller だけを持つ

---

## 2. 環境構成とブランチ戦略

| 層 | 環境（Org） | ブランチ | エイリアス | 役割 |
| :--- | :--- | :--- | :--- | :--- |
| **本番層** | Production | `main` | `prod` | **正（Source of Truth）**。本番の最新状態。 |
| **検証層** | Staging / UAT | `staging` | `staging` | 結合テスト・顧客確認用。 |
| **開発層** | Development / QA | `develop` | `develop` | 初期検証用。開発のベースライン。 |
| **作業層** | 各 Sandbox | `feature/*` | — | 作業項目ごとのソースの源泉。 |

---

## 3. リリース戦略（スター型プロモート）

### 3.1 配布ルール

すべてのリリースは `feature/*` ブランチを起点とし、各ターゲットブランチへ **個別に PR** を作成してデプロイする。

```
feature/xxx ──→ develop   （開発組織へリリース）
feature/xxx ──→ staging   （ステージング組織へリリース）
feature/xxx ──→ main      （本番組織へリリース）
```

デプロイ対象は `sf-tools/release/<branch>/deploy-target.txt` に記載したコンポーネントのみ。

**設計理由:** 環境ブランチ間でマージすると、意図しない変更が混入するリスクがある。必ず feature ブランチを経由させることで、各環境に「何がデプロイされたか」を明確に追跡できる。

### 3.2 マージ順序チェック（推奨順序）

プロモーションの推奨順序は `develop → staging → main` の順。
GitHub Actions（sf-sequence）が順序を自動チェックし、未確認の場合は **警告を出すが PR はブロックしない**（緊急リリースを妨げないため）。

| チェック対象 | 確認内容 |
| :--- | :--- |
| staging への PR | feature が develop にマージ済みか |
| main への PR | feature が develop かつ staging にマージ済みか |

### 3.3 マージ禁止制限（システムによる強制ブロック）

**環境ブランチ間の直接 PR** は sf-sequence で検知しエラーでブロックする。

- develop → staging
- develop → main
- staging → main

### 3.4 ローカルでの main 同期（pre-push フック）

`git push` 前に、リモートの最新 `main`（自動更新された本番の状態）を取り込んでいるかチェック。
未取り込みの場合は main からのマージを自動実行して最新化する。

sf-start.sh 実行時に pre-push フックを自動インストール。

---

## 4. CI/CD ワークフロー全体像

### 4.1 Reusable Workflow パターン

CI/CD ロジックは **sf-tools リポジトリに再利用可能ワークフロー（`*-reusable.yml`）として集約** し、各 Salesforce プロジェクト（force-*）は薄い caller（`workflow_call` で呼び出すだけ）を持つ。

```
sf-tools リポジトリ（ロジック本体）          force-* リポジトリ（caller のみ）
.github/workflows/                          .github/workflows/
├── sf-validate-reusable.yml    ◄────────── sf-validate.yml
├── sf-sequence-reusable.yml    ◄────────── sf-sequence.yml
├── sf-release-reusable.yml     ◄────────── sf-release.yml
├── sf-propagate-reusable.yml   ◄────────── sf-propagate.yml
└── sf-metasync-reusable.yml    ◄────────── sf-metasync.yml
```

**設計理由:** ワークフローの修正が sf-tools 側だけで済む。caller は `@main` を参照するため、sf-tools の main にマージした時点で全プロジェクトに即反映される。

### 4.2 ワークフロー一覧とトリガー

| ワークフロー | トリガー | 目的 | ブロック |
| :--- | :--- | :--- | :--- |
| **sf-validate** | PR 作成・更新時 | dry-run 検証 → PR にコメント投稿 | 失敗時ブロック |
| **sf-sequence** | main / staging への PR 時 | マージ順序（プロモーション順序）チェック | 環境ブランチ間のみブロック |
| **sf-release** | PR マージ後（closed + merged） | 対応組織へリリース → Slack 通知 | — |
| **sf-propagate** | main への PR マージ後 | main → staging / develop へ連鎖伝播 | — |
| **sf-metasync** | 平日 9:00〜19:00 JST（毎時） | 本番組織のメタデータを main へ自動同期 | — |

### 4.3 Slack 通知

| イベント | 通知内容 |
| :--- | :--- |
| リリース成功/失敗（sf-release） | リリース先・PR 情報・Actions ログへのリンク |
| マージ順序未確認（sf-sequence） | 未マージのブランチ・PR 情報 |
| 下流伝播コンフリクト（sf-propagate） | コンフリクト発生ブランチ・PR 情報・Actions ログへのリンク |

---

## 5. 各ワークフロー詳細

### 5.1 sf-validate（PR 検証）

PR の作成・更新をトリガーに、sf-release.sh を **検証モード（`--release` なし = dry-run）** で実行する。

**処理フロー:**
1. マージ先ブランチに応じて接続する Salesforce 組織を選択
2. sf-release.sh を検証モードで実行
3. 検証結果を **PR にコメントとして投稿**（成否・ログ付き）
4. 検証失敗時は exit 1 でマージをブロック

**接続先の切り替え:**
| マージ先 | 認証 Secret | 接続組織 |
| :--- | :--- | :--- |
| main | `SFDX_AUTH_URL_PROD` | 本番組織 |
| staging | `SFDX_AUTH_URL_STG` | ステージング組織 |
| develop / その他 | `SFDX_AUTH_URL_DEV` | 開発組織 |

### 5.2 sf-sequence（マージ順序チェック）

main / staging への PR 時にプロモーション順序を検証する。

**動作:**
- マージ元が `develop` / `staging`（環境ブランチ）→ **エラーでブロック**
- 順序未確認（例: staging 未マージで main へ PR）→ **警告 + Slack 通知（ブロックしない）**
- 順序 OK → 正常終了

**設計判断:** 警告のみにすることで、緊急の Hotfix を妨げない。Slack 通知でチームへの可視性は確保する。

### 5.3 sf-release（リリース実行）

PR マージ後に、マージ先ブランチに対応する Salesforce 組織へリリースを実行する。

**処理フロー:**
1. リリース先情報を GitHub Actions Summary に記録
2. マージ先に応じた組織に認証
3. `sf-tools/release/branch_name.txt` を動的生成（ローカルでは sf-start.sh が自動生成）
4. `sf-release.sh --release --no-open --target <alias>` を実行
5. 成否に関わらず **Slack へ結果を通知**

### 5.4 sf-propagate（下流ブランチ伝播）

main への PR マージ後に、staging と develop へ変更を自動伝播する。

```
main → staging   （git merge & push）
main → develop   （git merge & push）
```

**注意:**
- **Git 上の同期のみ** であり、Sandbox 組織への自動デプロイは行わない
- sf-metasync.sh のボット push（GitHub Actions bot による直接 push）では **このワークフローは発火しない**（caller の on: pull_request は PR マージ時のみトリガー）
- sf-metasync.sh による本番同期の下流伝播は sf-metasync.sh 自身が担う

**コンフリクト検知:**
develop / staging で並行開発中の変更と main の変更が同じ箇所に及んだ場合、マージがコンフリクトする可能性がある。コンフリクト発生時はマージを中止し、**Slack に通知**して手動対応を促す。自動解決は行わない（人間が判断すべき状況のため）。

### 5.5 sf-metasync（本番組織の自動同期）

**実行スケジュール:** `cron: "0 0-10 * * 1-5"`（UTC 0:00〜10:00 = JST 9:00〜19:00、平日のみ、毎時 0 分）

**処理フロー:**
1. main ブランチを全履歴付きでチェックアウト（SGD が全履歴を必要とするため）
2. Node.js / Java / Salesforce CLI / SGD をインストール
3. 本番組織に認証（`SFDX_AUTH_URL_PROD`）
4. sf-tools をクローンして sf-metasync.sh を実行
5. SGD で前回同期コミットからの差分 `package.xml` を生成
6. 差分取得 + `sf-tools/config/metadata-list.txt` に定義されたメタデータタイプを一括 retrieve
7. 変更がある場合: git commit → push（main へ直接 push）→ staging / develop へ伝播
8. 変更がない場合: 何もせず正常終了

**対象メタデータタイプ:**
`sf-tools/config/metadata-list.txt` の設定に従う。このファイルは force-*（Salesforce プロジェクト）の管理者が、sf-metasync で同期するメタデータタイプを定義する。1 行 1 タイプ、`#` でコメント、空行は無視。

---

## 6. デプロイ定義ファイル

### 6.1 ファイル配置

```
sf-tools/release/<branch>/
├── deploy-target.txt    # 追加/更新対象
└── remove-target.txt    # 削除対象
```

`sf-tools/release/branch_name.txt` にブランチ名を書き込むことで、どの release ディレクトリを参照するかを sf-release.sh に伝える。

### 6.2 deploy-target.txt の形式

2 セクション構成。行頭 `#` はコメント、空行は無視。

```
[files]
# ファイルパスで指定 → --source-dir 引数に変換
force-app/main/default/classes/MyClass.cls
force-app/main/default/classes/MyClass.cls-meta.xml
force-app/main/default/lwc/myComponent

[members]
# メタデータ種別:メンバー名 → --metadata 引数に変換（部分デプロイ用）
CustomLabel:MyLabel
Profile:Admin
```

### 6.3 デプロイ対象なしの扱い

deploy-target.txt が空（コメントのみ）の場合、sf-release.sh は `RET_NO_CHANGE`（exit code 2）を返し正常終了する。CI でも失敗扱いにはならない。

---

## 7. セットアップ要件

### 7.1 GitHub Secrets（force-* リポジトリに設定）

| Secret | 用途 |
| :--- | :--- |
| `SFDX_AUTH_URL_PROD` | 本番組織の認証 URL |
| `SFDX_AUTH_URL_STG` | ステージング組織の認証 URL |
| `SFDX_AUTH_URL_DEV` | 開発組織の認証 URL |
| `SLACK_BOT_TOKEN` | Slack API の Bot Token |
| `SLACK_CHANNEL_ID` | 通知先 Slack チャンネル ID |

認証 URL の取得方法: `sf org display --verbose --json | grep sfdxAuthUrl`

### 7.2 GitHub リポジトリ設定

- **Settings → Actions → General:** 「Allow GitHub Actions to create and approve pull requests」を有効化
- **Branch Protection:** sf-validate チェックを必須に設定（マージブロック用）
- **ブランチ構成:** main / staging / develop の 3 ブランチが存在すること

### 7.3 ローカル環境

- Git（Git Bash 推奨 on Windows）
- GitHub CLI（`gh` コマンド）
- Node.js / npm（Salesforce CLI のインストール・依存管理に必要）
- Java（SGD の実行に必要）
- Salesforce CLI（`sf` コマンド）
- Visual Studio Code（`code` コマンドが PATH に含まれること）

---

## 8. 設計上のトレードオフと判断

| 判断 | 理由 |
| :--- | :--- |
| 本番同期を PR なしの直接 push にした | 毎時の同期に承認は不要。ボットコミットで手動コミットと区別可能。管理者の負担を最小化。 |
| sf-metasync のボット push で propagate を発火させない | PR マージ時のみトリガー。メタデータ同期の下流伝播は sf-metasync.sh 自身が担う。 |
| マージ順序チェックを警告のみ（ブロックしない）にした | 緊急 Hotfix を妨げないため。Slack 通知で可視性は確保。 |
| 環境ブランチ間の直接マージはブロック | 意図しない変更の混入を防止。feature 経由を強制し、各環境のデプロイ内容を追跡可能にする。 |
| deploy-target.txt が空なら正常終了（RET_NO_CHANGE） | CI でリリース定義だけ先に準備する運用を許容するため。 |
| Reusable Workflow + `@main` 参照 | ワークフロー修正が sf-tools 側だけで済む。全プロジェクトに即反映。 |
| 24 時間スロットルでツール更新 | 毎回 sf-start.sh 実行時にアップデートすると起動が遅くなるため。 |
| 下流伝播のコンフリクトは自動解決しない | 本番と開発で同じ箇所が変更された状況は人間が判断すべき。Slack 通知で検知し手動対応。 |
| 本番の変更を 1 時間以内に全環境へ伝播 | 古いコードベースでの開発によるデグレを防止する。 |
