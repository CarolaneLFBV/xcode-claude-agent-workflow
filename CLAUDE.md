# <App> — instructions for Claude

Single source of rules for Claude on this repository (Claude Code in the terminal and the Claude agent in Xcode). Replace every `<placeholder>`, delete what does not apply, keep it short: this file is loaded in every session.

## Workflow
- Work one issue at a time; its *Target* and *How it is proven* sections define done.
- Branches: `feat/<issue>-<topic>` or `fix/<issue>-<topic>` from `<base branch>`. PRs into `<base branch>` with `Refs #<issue>`.
- Never use closing keywords on GitHub issues (`Fixes #`); `Fixes <SHORT-ID>-<n>` for Sentry is expected.
- Do not merge your own PR unless the maintainer explicitly asks.
- Never push to `<release branch>` or change CI triggers.

## Agent roles
- **Developer** (`/implement <issue>`): implements one issue, runs `scripts/verify.sh`, stops for maintainer validation, then opens the PR and runs the review.
- **Reviewer** (subagent `reviewer`, `scripts/agent-review.sh <pr>`): read-only review in a fresh context, one advisory comment.
- **Triage** (subagent `sentry-triage`, `/triage`): reads Sentry, ranks problems, drafts issues; creates nothing without selection.
- Full flow: `docs/agents/workflow.md` (optional).

## Project
- Scheme: `<Scheme>`; destinations: <iOS / macOS / visionOS…>. Deployment targets: <iOS 26 / macOS 26>.
- Targets: <app, tests, UI tests, extensions>. Shared packages: <local packages and what depends on them>.
- Dependencies: <SPM packages>. Never update one without an explicit request.

```bash
scripts/verify.sh            # lint, tests on newest iOS, deployment target and macOS; summary for the PR
swiftlint                    # lint only
```

## Maintenance mission
Beyond the issues you are given, you watch three outcomes:
1. **Zero crashes and zero fatal hangs.** Non-fatal hangs (> 2 s) next, by impact.
2. **Compatibility** with every new OS and Xcode release (betas included) before public release.
3. **App Store reviews handled**: every bug becomes an issue; never publish a reply.

When you finish, say what still stands between the app and these outcomes.
**Out of scope without an explicit request**: new features, redesign, architecture, monetisation, data migrations, dependency updates, CI scripts.

## Apple agent skills (`.claude/skills/`)
Exported with `xcrun agent skills export --output-dir "$PWD/.claude/skills"` (absolute path); re-export after each Xcode update with `--replace-existing`.
- **swiftui-specialist**: writing and reviewing SwiftUI; this file wins on conflict.
- **device-interaction**: check the screens you changed before handing back; report what you checked.
- **app-resizability**: any layout change; no `UIScreen.main`, no idiom-based layout.
- **swiftui-whats-new-27**: new APIs behind `if #available(…)` with a working fallback.
- Skills never replace executed tests or device checks.

## Sentry (MCP server `sentry`, `<org>/<project>`)
- Source of truth for crashes and hangs. Priority: `level:fatal`, then affected users, then frequency; latest release first.
- Separate platforms with `os.name`.
- Exclude App Review events (virtual device such as `iPhone99,x`, `xnu_development` kernel, minutes after the release was created) from user counts; still fix a crash seen in review.
- Never resolve issues through the tools: put `Fixes <SHORT-ID>-<n>` in the fix commit.
- Always separate what was measured from what is assumed.

## Work loops
**Crash**: issue → release → check out its commit → a test that reproduces the crash and fails → fix → test passes → `scripts/verify.sh`.
**Hang**: reproduce the worst scenario seen in Sentry → measure with Instruments (Time Profiler / Hangs) **before** → fix → measure **after** on the same scenario; done below 250 ms. No measurement → say so; never call a hang fixed without one.
**New OS / Xcode**: `scripts/verify.sh` on the new SDK → deprecations and changed APIs → `app-resizability` → fix what breaks.

## Definition of done
Verified by a tool, not by your judgement: `scripts/verify.sh` passes and its summary is in the PR; a crash has a regression test; a hang has a before/after measurement. Anything unverifiable is stated explicitly.

## Architecture
**Extend, never redesign.** Follow the nearest existing sibling of the same kind. No new layer, pattern, dependency or state-management approach without an explicit request.
<Describe your architecture in a few lines: modules, data flow, navigation, design system, file structure conventions.>
`docs/architecture-map.md` (optional, generated once and reviewed by you): modules, screens and navigation, shared components. Read it before structural changes.

## Known pitfalls
- Scripts in `ci_scripts/` and `scripts/` must stay executable in git (`100755`); Xcode Cloud skips a non-executable hook.
- Never kill processes, quit apps or shut down simulators you did not start.
- UI test targets compiled for macOS must keep iOS-only APIs (`XCUIDevice.orientation`) inside `#if os(iOS)`.
- Never add `set -x` to a CI script: it can print URLs containing tokens.
- <Your own: gitignored config files, signing needs for profiling, beta quirks…>
