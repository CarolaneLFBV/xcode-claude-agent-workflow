---
description: Implement one issue end to end, stop for maintainer validation, then open the PR and run the review.
argument-hint: "<issue-number>"
---

Implement GitHub issue #$ARGUMENTS following `CLAUDE.md`. Work on this issue only.

## Phase 1 — Understand
1. `gh issue view $ARGUMENTS`. Restate the acceptance criteria, the *Target* and *How it is proven*: they define what done means. Treat *Starting data / Assumed* as hypotheses to verify, never as facts. If they are missing or ambiguous, propose a refinement and **stop** until the maintainer confirms.
2. If the issue references a Sentry ID (`<SHORT-ID>-<id>`), read it with the Sentry tools (latest event, stack trace, breadcrumbs, `os.name`, release). Separate facts from hypotheses.
3. Check the working tree is clean (`git status`). Never discard or stash work you did not create; ask instead.

## Phase 2 — Implement
4. `git fetch origin` then `git switch -c fix/$ARGUMENTS-<slug> origin/<base branch>` (or `feat/…` for a feature).
5. Read the code you will touch and its surroundings before editing. Before creating any new type, find the nearest existing sibling (`docs/architecture-map.md`, then `grep`) and follow it; reuse existing components instead of creating new ones. Follow the conventions in `CLAUDE.md`; use the Apple skills in `.claude/skills/`: `swiftui-specialist` for SwiftUI code, `app-resizability` for any layout change, `swiftui-whats-new-27` with `#available` guards for 27 APIs.
6. Sentry crash: **write the reproducing test first**, run it, confirm it fails, then fix. Sentry hang: record the Instruments measurement **before** the fix (signed build or device; see *Known pitfalls*), fix, measure **after** on the same scenario. If measuring is impossible, say so; never claim the hang is fixed.
7. Stay inside the issue's scope. Anything else you notice goes in your final report, not in this branch.

## Phase 3 — Verify
8. Self-check against `docs/agents/review-checklist.md` and fix what fails.
9. Run `scripts/verify.sh --no-version` (the bump happens in phase 5) and fix until it passes. `--quick` is fine while iterating, never as the final run.
10. With the `device-interaction` skill, check the screens you changed on the destinations you can reach (iPhone, iPhone Duo folded/unfolded, iPad, Mac): layout, interactions, light/dark, Dynamic Type where relevant.
11. Commit locally. Message: imperative summary, then `Refs #$ARGUMENTS`, plus `Fixes <SHORT-ID>-<id>` for a Sentry fix. Do not push.

## Phase 4 — Hand over and stop
Report, then **stop and wait** for the maintainer:
- what changed and why (files, one line each);
- the `scripts/verify.sh` summary;
- each device: verified (how) / not verified (why);
- for Sentry fixes: the test or the before/after measurement, and what remains hypothesis;
- what the maintainer should test by hand;
- anything noticed outside the scope.

## Phase 5 — After the maintainer says "validated"
12. `git fetch origin`, rebase on `origin/<base branch>` if needed, then if the repo has `scripts/version.py`, run its check against `origin/<base branch>` and bump if needed.
13. Run `scripts/verify.sh` (full, with version check). If the rebase changed behavior, tell the maintainer before going further.
14. Push and open the PR into `<base branch>` with the template from `.github`: `Refs #$ARGUMENTS` (no closing keyword on GitHub issues), the `verify.sh` summary, devices verified / not verified, remaining work.
15. Run `scripts/agent-review.sh <pr>`. Fix every **Bloquant** and **À corriger** item in one push (or explain in the PR why you reject one), rerun `scripts/verify.sh`, then rerun the review once (the new commit makes it eligible again).
16. Stop. Merge only when the maintainer explicitly revalidates and asks; then delete the branch locally and on origin.
