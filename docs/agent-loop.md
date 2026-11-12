# Agent loop

How work moves from an issue to a merged pull request with as little human time as possible.
Implemented by the reusable workflow `.github/workflows/agent-loop.yml` and `scripts/agent-loop.sh` in this repository. Each service repository calls the workflow from its own `.github/workflows/agent-loop.yml` (see the README).

## Flow
1. **Triage.** A person opens an issue with one of three templates. The templates are the organisation defaults in the `Harness-Demonstration/.github` repository. *Agent task* adds the `agent-ready` label: a well-scoped change with plain acceptance criteria. *Agent task (strong model)* adds `agent-ready` and `model:strong` for harder changes; the labels arrive with the issue, so the model is chosen before Copilot starts. *Human task* adds `needs-human`: production-critical, security-sensitive or still unclear work. Adding `agent-ready` later has the same effect.
2. **Assign.** An `agent-ready` issue is assigned to the Copilot cloud agent with `AGENT_MODEL` (GPT-6.1 Terra), or with `STRONG_MODEL` (Claude Sonnet 5.5) when the issue also has the `model:strong` label. Fix rounds use the same rule, reading the labels of the issue the pull request closes.
3. **Write.** Copilot opens a pull request and works until it requests a review.
4. **CI.** When Copilot has finished, the loop waits for the pull request's CI (up to 15 minutes). If CI fails, it starts a fix round for the failing workflows instead of a review: reviewing code that does not build wastes a review.
5. **Review.** With CI green and no review covering Copilot's latest work, the loop requests a Copilot code review and waits in the same run (up to 10 minutes) until it arrives. It does not rely on the run GitHub starts when the review finishes: that run is started by the reviewer bot and waits for approval. Every review uses `REVIEW_EFFORT` (Lite).
6. **Fix.** If the review has comments, the loop starts a fix round. It writes a marker comment, then starts a Copilot session on the pull request branch through the agent tasks API with the model from step 2 and the review comments in the prompt. A plain `@copilot` comment always runs with the default model, so it is only the fallback when the API refuses. Then step 4 runs again.
7. **Hand over.** The loop marks the pull request ready, adds `ready-for-human` and mentions `HUMAN_REVIEWER` when a review has no comments and CI is green, or when `MAX_FIX_ROUNDS` fix rounds (CI and review fixes together) are used up. `MAX_FIX_ROUNDS` comes from the caller repository's variable `AGENT_MAX_FIX_ROUNDS`, default 1.

The human then checks the diff against the acceptance criteria, approves and merges (the default-branch ruleset requires one approval, a code owner's for paths in `.github/CODEOWNERS`, and a new approval after any later push), or removes `ready-for-human` and asks `@copilot` for changes, which restarts the loop at step 4. The loop never merges.

## Rules
- Each run looks at the pull request's current state and takes at most one step, so duplicate events are harmless.
- GitHub API answers that mean "try again later" (HTTP 429, 5xx, GraphQL `SERVICE_UNAVAILABLE`) are retried up to four times with a growing delay.
- The loop stops for good once `ready-for-human` is on the pull request. Remove the label and run the workflow by hand to restart it.
- The workflow only uses triggers that run its definition from the default branch, never `pull_request_review` or `pull_request`, and never checks out pull request code. A pull request cannot change what runs with `AGENT_LOOP_TOKEN`.
- The reusable workflow names the `agent-loop` environment on each job, and the caller passes `AGENT_LOOP_TOKEN` by name. GitHub needs both: without the caller's line the secret is an empty string and the run shows no error. The value comes from the caller repository's environment, so only jobs on `main` receive it.
- `AGENT_LOOP_TOKEN` is stored only in the `agent-loop` environment, whose deployment branch rule allows `main` alone. Because of that lock, "Require approval for workflow runs" for Copilot can be off.
- `AGENT_LOOP_TOKEN` is a fine-grained token of the human reviewer. Copilot only acts on `@copilot` comments from people with write access, and reviews requested with it count against that person's Copilot plan.

## Cost
Measured on 2026-11-11 (sim-service PR #34) and priced with GitHub's per-token rates: a Claude Sonnet 5.5 writing session about $0.45, a Balanced review about $0.90, a Lite review about $0.25 (GitHub's estimate). Reviews were 60% of the cost. The defaults (GPT-6.1 Terra at half Sonnet's price, Lite reviews, one fix round) target about $0.50 to $0.80 per issue. Copilot Pro includes 1,500 AI credits ($15) a month.

## Sources
- GitHub Docs, "Reuse workflows" and "Contexts": the `github` context of a called workflow is the caller's, a caller must pass an environment secret by name for a called workflow to see it, and `job.workflow_repository` and `job.workflow_sha` name the called workflow's own repository and commit.
- GitHub Docs, "Creating a default community health file": issue templates in the public `.github` repository are used by every repository that has no `.github/ISSUE_TEMPLATE` of its own.
- OpenAI, "Harness engineering": agents review their own changes and "iterate in a loop until all agent reviewers are satisfied"; humans are involved when judgment is required.
- GitHub Docs: assigning issues to Copilot through the API (user token, `agentAssignment.model`), `requestCopilotCodeReview`, and the advice that production-critical, security-sensitive and ambiguous tasks are better done by developers.
- Model choice: Artificial Analysis Intelligence Index (GPT-6.1 Terra 51, Claude Sonnet 5.5 55) and GitHub's Copilot model prices.
- The limit of one fix round is our own choice from the test runs; no source names a number.
