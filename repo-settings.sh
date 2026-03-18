#!/usr/bin/env bash
# ==============================================================================
# repo-settings.sh — GitHub リポジトリ設定の再現スクリプト
# ==============================================================================
# このスクリプトは force-tama リポジトリの設定を再現します。
# 新しいリポジトリに同じ設定を適用する場合に使用してください。
#
# 【前提条件】
#   - gh コマンドがインストールされていること（GitHub CLI）
#   - gh auth login で認証済みであること（repo + workflow + read:org スコープ必要）
#   - 対象リポジトリのオーナー/Admin 権限を持つアカウントで認証すること
#
# 【使い方】
#   bash scripts/repo-settings.sh <owner/repo>
#   例: bash scripts/repo-settings.sh tamashimon-create/force-tama
# ==============================================================================

set -euo pipefail

REPO="${1:-tamashimon-create/force-tama}"

echo "=================================================="
echo " リポジトリ設定の適用: ${REPO}"
echo "=================================================="

# ------------------------------------------------------------------------------
# 1. リポジトリ基本設定
# ------------------------------------------------------------------------------
echo ""
echo "[1/4] リポジトリ基本設定を適用中..."

gh repo edit "${REPO}" \
  --default-branch main \
  --enable-issues \
  --enable-projects \
  --enable-wiki \
  --disable-discussions \
  --enable-merge-commit \
  --enable-squash-merge \
  --enable-rebase-merge \
  --no-delete-branch-on-merge

echo "  ✓ 基本設定を適用しました"
echo "    - デフォルトブランチ: main"
echo "    - Issues: 有効"
echo "    - Projects: 有効"
echo "    - Wiki: 有効"
echo "    - Discussions: 無効"
echo "    - マージコミット: 有効"
echo "    - スカッシュマージ: 有効"
echo "    - リベースマージ: 有効"
echo "    - PR マージ後ブランチ自動削除: 無効"

# ------------------------------------------------------------------------------
# 2. Ruleset: protect-main
# ------------------------------------------------------------------------------
echo ""
echo "[2/4] Ruleset: protect-main を作成中..."

# 既存の protect-main を削除（存在する場合）
EXISTING_MAIN_ID=$(gh api "repos/${REPO}/rulesets" --jq '.[] | select(.name=="protect-main") | .id' 2>/dev/null || echo "")
if [ -n "${EXISTING_MAIN_ID}" ]; then
  gh api --method DELETE "repos/${REPO}/rulesets/${EXISTING_MAIN_ID}" > /dev/null
  echo "  既存の protect-main (id: ${EXISTING_MAIN_ID}) を削除しました"
fi

gh api --method POST "repos/${REPO}/rulesets" \
  --input - << 'EOF'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "デプロイ検証", "integration_id": 15368 },
          { "context": "マージ順序を検証", "integration_id": 15368 }
        ]
      }
    }
  ]
}
EOF

echo "  ✓ protect-main を作成しました"
echo "    - 対象ブランチ: main"
echo "    - 削除禁止: 有効"
echo "    - 強制プッシュ禁止: 有効"
echo "    - Required status checks: デプロイ検証, マージ順序を検証"
echo "    - Bypass: Repository admin (always)"

# ------------------------------------------------------------------------------
# 3. Ruleset: protect-staging
# ------------------------------------------------------------------------------
echo ""
echo "[3/4] Ruleset: protect-staging を作成中..."

# 既存の protect-staging を削除（存在する場合）
EXISTING_STAGING_ID=$(gh api "repos/${REPO}/rulesets" --jq '.[] | select(.name=="protect-staging") | .id' 2>/dev/null || echo "")
if [ -n "${EXISTING_STAGING_ID}" ]; then
  gh api --method DELETE "repos/${REPO}/rulesets/${EXISTING_STAGING_ID}" > /dev/null
  echo "  既存の protect-staging (id: ${EXISTING_STAGING_ID}) を削除しました"
fi

gh api --method POST "repos/${REPO}/rulesets" \
  --input - << 'EOF'
{
  "name": "protect-staging",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/staging"],
      "exclude": []
    }
  },
  "bypass_actors": [
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "always"
    }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "デプロイ検証", "integration_id": 15368 },
          { "context": "マージ順序を検証", "integration_id": 15368 }
        ]
      }
    }
  ]
}
EOF

echo "  ✓ protect-staging を作成しました"
echo "    - 対象ブランチ: staging"
echo "    - 削除禁止: 有効"
echo "    - 強制プッシュ禁止: 有効"
echo "    - Required status checks: デプロイ検証, マージ順序を検証"
echo "    - Bypass: Repository admin (always)"

# ------------------------------------------------------------------------------
# 4. Actions Secrets の登録案内
# ------------------------------------------------------------------------------
echo ""
echo "[4/4] Actions Secrets の登録案内"
echo "  以下のシークレットを手動で登録してください："
echo "  （値は機密情報のため自動設定できません）"
echo ""
echo "  リポジトリ → Settings → Secrets and variables → Actions"
echo ""
echo "  必要なシークレット:"
echo "    GH_PAT              — GitHub Personal Access Token"
echo "                          スコープ: repo, workflow, read:org"
echo "                          用途: sf-propagate.yml の staging/develop への直接 push"
echo "    SFDX_AUTH_URL_DEV   — Salesforce Dev 組織の認証 URL"
echo "    SFDX_AUTH_URL_PROD  — Salesforce Prod 組織の認証 URL"
echo "    SFDX_AUTH_URL_STG   — Salesforce Staging 組織の認証 URL"
echo "    SF_TOOLS_REPO       — sf-tools リポジトリの URL"
echo "    SLACK_BOT_TOKEN     — Slack Bot トークン"
echo "    SLACK_CHANNEL_ID    — Slack 通知先チャンネル ID"

echo ""
echo "=================================================="
echo " 完了！"
echo "=================================================="
