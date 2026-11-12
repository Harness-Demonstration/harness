#!/usr/bin/env bash
# Creates or updates the default-branch ruleset of a repository from rulesets/default-branch.json.
#   scripts/apply-ruleset.sh [--code-scanning] <owner/repo> [required check ...]
# Each required check is a CI job name, for example build or consumer-contracts. Only GitHub Actions
# (app id 15368) can report them, so a status posted by anything else does not count.
# --code-scanning adds the rule that blocks a merge while CodeQL reports a high or critical security alert,
# an error-level alert, or has not finished. Use it only where CodeQL default setup is on: without CodeQL the
# rule blocks every merge.
# Safe to run again: an existing ruleset with the same name is replaced.
set -euo pipefail
code_scanning=false
if [ "${1:-}" = --code-scanning ]; then code_scanning=true; shift; fi
repo="${1:?usage: $0 [--code-scanning] <owner/repo> [required check ...]}"
shift
harness="$(cd "$(dirname "$0")/.." && pwd)"
checks=$(printf '%s\n' "$@" | jq -R 'select(length > 0) | {context: ., integration_id: 15368}' | jq -s .)
body=$(jq --argjson checks "$checks" '
  .rules |= map(if .type == "required_status_checks" then .parameters.required_status_checks = $checks else . end)
  | if ($checks | length) == 0 then .rules |= map(select(.type != "required_status_checks")) else . end
  | if $scan then .rules += [{type: "code_scanning", parameters: {code_scanning_tools: [
      {tool: "CodeQL", security_alerts_threshold: "high_or_higher", alerts_threshold: "errors"}]}}] else . end' \
  --argjson scan "$code_scanning" "$harness/rulesets/default-branch.json")
name=$(jq -r .name <<<"$body")
id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
if [ -n "$id" ]; then
  gh api -X PUT "repos/$repo/rulesets/$id" --input - <<<"$body" >/dev/null
  echo "$repo: ruleset $name updated (id $id)"
else
  id=$(gh api -X POST "repos/$repo/rulesets" --input - <<<"$body" --jq .id)
  echo "$repo: ruleset $name created (id $id)"
fi
gh api "repos/$repo/rules/branches/$(gh api "repos/$repo" --jq .default_branch)" \
  --jq '"active rules: " + ([.[].type] | join(", "))'
