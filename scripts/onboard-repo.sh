#!/usr/bin/env bash
# Prepares a repository for the agent loop. Safe to run again.
#   scripts/onboard-repo.sh <owner/repo> <human-reviewer-login> "<verify command>"
# 1. Creates or updates the labels in labels.tsv.
# 2. Creates the agent-loop environment and allows the main branch only.
# 3. Writes .github/workflows/agent-loop.yml into a local clone when run from one (optional, see below).
# It never touches AGENT_LOOP_TOKEN: the person who owns the token sets it (command printed at the end).
set -euo pipefail
repo="${1:?usage: $0 <owner/repo> <human-reviewer-login> \"<verify command>\"}"
reviewer="${2:?give the GitHub login that reviews agent pull requests}"
verify="${3:-}"
harness="$(cd "$(dirname "$0")/.." && pwd)"

while IFS=$'\t' read -r name color description; do
  gh label create "$name" --repo "$repo" --color "$color" --description "$description" --force
done < "$harness/labels.tsv"

gh api -X PUT "repos/$repo/environments/agent-loop" \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true' >/dev/null
if ! gh api "repos/$repo/environments/agent-loop/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main; then
  gh api -X POST "repos/$repo/environments/agent-loop/deployment-branch-policies" -f name=main -f type=branch >/dev/null
fi
echo "agent-loop environment: main branch only"

# With a fourth argument (path to a local clone), write the caller workflow there for a pull request.
if [ -n "${4:-}" ]; then
  mkdir -p "$4/.github/workflows"
  sed -e "s|HUMAN_REVIEWER_LOGIN|$reviewer|" -e "s|VERIFY_COMMAND|${verify:-''}|" \
    "$harness/templates/agent-loop-caller.yml" > "$4/.github/workflows/agent-loop.yml"
  echo "wrote $4/.github/workflows/agent-loop.yml"
fi

if gh secret list --env agent-loop --repo "$repo" | grep -q '^AGENT_LOOP_TOKEN'; then
  echo "AGENT_LOOP_TOKEN is set"
else
  echo "AGENT_LOOP_TOKEN is missing. The token owner runs:"
  echo "  gh secret set AGENT_LOOP_TOKEN --env agent-loop --repo $repo"
fi

echo "Last step, after the caller workflow and .github/CODEOWNERS are merged:"
echo "  scripts/apply-ruleset.sh $repo <CI job> ...   (for example: build docs)"
