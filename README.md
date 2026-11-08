# Xcode × Claude Code agent workflow

Templates for an iOS / macOS project maintained with Claude Code, Apple's Xcode agent skills and Sentry, where **the agent never decides its own work is done**: tests, measurements and production data do.

Full write-up: [Your coding agent shouldn't grade its own homework](https://carolanelefebvre.com/articles/claude-code-xcode-agent-workflow?utm_source=github&utm_medium=referral&utm_campaign=agent-workflow) · Previous article: [Apple's agent skills](https://carolanelefebvre.com/articles/apple-s-agent-skills-a-little-extra-expertise-for-your-coding-assistant?utm_source=github&utm_medium=referral&utm_campaign=agent-workflow)

## The loop

```
Sentry ──/triage──▶ GitHub issue ──/implement──▶ branch + fix (Apple skills)
                                                    │
                                   scripts/verify.sh (executed tests, lint)
                                                    │
                     maintainer validates ──▶ PR ──▶ scripts/agent-review.sh (read-only reviewer)
                                                    │
                  merge ──▶ release ──▶ "Fixes <SHORT-ID>-<n>" resolves the Sentry issue
```

## What's inside

| File | Role |
| --- | --- |
| `CLAUDE.md` | Rules, maintenance mission, Sentry rules, work loops, definition of done, pitfalls |
| `.claude/agents/reviewer.md` | Read-only reviewer: compares with existing code, never redesigns |
| `.claude/agents/sentry-triage.md` | Ranks Sentry issues, excludes App Review events, drafts issues |
| `.claude/commands/implement.md` | `/implement <issue>`: understand → implement → verify → stop → PR |
| `.claude/commands/triage.md` | `/triage [period]`: report, then create only the issues you select |
| `.claude/commands/verify.md` | `/verify`: runs `verify.sh` and explains failures |
| `.mcp.json` | Sentry MCP server, scoped to one project |
| `scripts/verify.sh` | Lint + executed tests on the newest iOS simulator, the deployment target and macOS; Markdown summary for PRs |
| `scripts/agent-review.sh` | Runs the reviewer on a PR in a temporary worktree and posts one comment |
| `ci_scripts/ci_post_xcodebuild.sh` | Xcode Cloud: dSYM upload + commits associated with the Sentry release |
| `.github/ISSUE_TEMPLATE/user-story.md` | User story with starting data, target and proof |
| `docs/agents/review-checklist.md` | Shared grid for developer and reviewer |

## Setup

1. Copy the files to the root of your repo. Keep scripts executable: `git update-index --chmod=+x scripts/*.sh ci_scripts/*.sh`.
2. Replace every `<placeholder>` (`grep -rn '<' CLAUDE.md .mcp.json .claude docs`), and set `SCHEME`, `MIN_IOS`, `HAS_MACOS` at the top of `scripts/verify.sh`.
3. Export Apple's skills (Xcode 27+), with an absolute path: `xcrun agent skills export --output-dir "$PWD/.claude/skills"`.
4. Start Claude Code at the repo root, approve the `sentry` server, then `/mcp` → Authenticate.
5. Run `/verify` once. Expect it to find something.
6. Optional: Xcode Cloud workflow variables `SENTRY_AUTH_TOKEN` (secret), `SENTRY_URL`, `SENTRY_ORG`, `SENTRY_PROJECT`.

Start small: `verify.sh` alone is already useful.

## Requirements

Claude Code on a Pro or Max subscription (no API key needed), Xcode 27+, `gh`, SwiftLint, and Sentry for the triage and release parts.

## Notes

- The reviewer uses the same model family as the developer: its review is advisory. `verify.sh` and your device checks are the gate.
- Subagent `skills:` preload does not apply when launched with `claude --agent`; the reviewer reads `SKILL.md` itself.
- Xcode's built-in Claude agent keeps its own configuration: it reads the project `CLAUDE.md`, but not `.mcp.json`.

MIT licence.
