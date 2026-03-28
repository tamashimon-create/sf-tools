# WF 配布・更新戦略

> **ステータス: 未実装（将来対応予定）**

---

## 1. 背景

`force-XXXX` 側に設置する WF（`wf-validate.yml` / `wf-release.yml` 等）は CI/CD ロジックを完全内包した**セルフコンテインド WF**であり、
`sf-init` 実行時に `sf-tools/templates/` からコピーして配布する（`force-template` リポジトリは廃止済み）。

実運用開始後に WF を変更・追加・削除する必要が生じた場合、
配布済みの全プロジェクトへ安全に反映する手段が現時点では存在しない。

---

## 2. アーキテクチャ方針

```
sf-tools（テンプレートの正本）
└── templates/.github/workflows/
    ├── wf-validate.yml   ← セルフコンテインド（ロジック内包）
    ├── wf-release.yml    ← 同上
    ├── wf-metasync.yml   ← 同上
    ├── wf-propagate.yml  ← 同上
    └── wf-sequence.yml   ← 同上

force-XXXX（各プロジェクト）
└── .github/workflows/
    ├── wf-validate.yml  ← sf-init 時に templates/ からコピー
    ├── wf-release.yml   ← 同上
    └── ...
```

- WF の正本は `sf-tools/templates/.github/workflows/` に一元管理する
- `sf-init` は `sf-tools/templates/` からコピーして配布する（`force-template` リポジトリは廃止済み）
- 問題になるのは **WF 自体の変更**（secrets の追加削除、job 構造変更など）のみ

---

## 3. 方針（決定済み）

- `sf-install.sh` への WF 自動同期は **実装しない**
  - sf-start → sf-install のバックグラウンド自動実行チェーンに入れると、
    ユーザーの意思に関係なく `.github/workflows/` が書き換わるため不適切
- 専用 CLI `sf-sync-wf.sh` を実装する

---

## 4. `sf-sync-wf.sh` 設計（未実装）

### 4.1 責務

| 対応する | 対応しない |
|---|---|
| `sf-tools/templates/` との差分表示 | 自動コミット |
| ユーザー確認後にコピー | sf-install からの自動実行 |
| `--remove` フラグ付き削除 | バージョン管理 |

### 4.2 処理フロー

```
実行: sf-sync-wf.sh [--remove <filename>]

通常実行:
  1. ~/sf-tools/templates/.github/workflows/ と .github/workflows/ をローカル diff で比較
  2. 差分なし → "最新です" で終了
  3. 差分あり → diff を表示
  4. [Y/N/q] 確認
  5. Y → templates/ の内容をコピー（上書き）
  6. "git diff .github/workflows/ で確認してコミットしてください" で終了

--remove <filename> 指定時:
  1. 対象ファイルを表示
  2. [Y/N/q] 確認（削除は追加確認）
  3. Y → 削除
```

### 4.3 実装時の注意

- `force-*` ディレクトリ以外では実行不可（`check_force_dir`）
- 自動コミット・プッシュは行わない（ユーザーに委ねる）
- 削除は `--remove` フラグ明示時のみ（誤操作防止）

---

## 5. 対応タイミング

caller WF を実際に変更する必要が生じた時点で実装する。
現時点では **`sf-tools/templates/.github/workflows/` の内容を正しく保つ**だけで準備完了。
