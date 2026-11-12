# harness

Shared parts of the agent harness for the repositories in Harness-Demonstration.

| Part | Path | What it does |
|---|---|---|
| Agent loop | `.github/workflows/agent-loop.yml`, `scripts/agent-loop.sh` | Reusable workflow: assigns `agent-ready` issues to the Copilot cloud agent, waits for CI, requests a Copilot review, starts fix rounds and hands the pull request to a human. Flow and rules: [docs/agent-loop.md](docs/agent-loop.md). |
| Onboarding | `scripts/onboard-repo.sh`, `labels.tsv`, `templates/agent-loop-caller.yml` | Creates the labels and the `agent-loop` environment (main branch only) in a repository and writes its caller workflow. |
| Issue templates | the organisation's `.github` repository | Agent task, Agent task (strong model) and Human task, used by every repository without templates of its own. |

## Add a repository

1. `scripts/onboard-repo.sh Harness-Demonstration/<repo> <reviewer-login> "<verify command>" <path to a local clone>`
2. The token owner sets the secret: `gh secret set AGENT_LOOP_TOKEN --env agent-loop --repo Harness-Demonstration/<repo>`. The token is a fine-grained token of the human reviewer (see docs/agent-loop.md).
3. Enable the Copilot cloud agent for the repository, and open a pull request with the written `.github/workflows/agent-loop.yml`.
4. Check the wiring without spending Copilot credits: after the merge, run the workflow by hand with the number of any pull request that Copilot did not open. The log says `PR #<n> is not an open Copilot pull request`.

## Versions

Callers use `@main` while the lab is small. A team would tag releases (`v1`) and let callers pin the tag; the workflow checks out the script from its own commit, so workflow and script always match.
