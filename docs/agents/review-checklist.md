# Shared review checklist

The developer agent self-checks against this list before opening a PR; the reviewer uses it as its grid. Rules come from `CLAUDE.md`; on conflict, it wins. Add your own sections (design system, localisation, file structure).

Severity: **Blocking** (bug, data loss, crash, broken workflow rule, architecture violation, fix claimed without proof) · **To fix** (rule deviation to correct in this PR) · **Suggestion** (optional, never blocks).

## 1. Correctness
- [ ] The change does what the issue's acceptance criteria ask, and nothing unrelated.
- [ ] No regression in empty, populated and filtered states.
- [ ] APIs newer than the deployment target are behind `#available` with a working fallback.
- [ ] Platform-specific code is isolated (`#if os(…)`) and consistent across platforms.
- [ ] Layout adapts to size changes (resizable windows, iPhone Duo folded/unfolded): size classes and container size.

## 2. Consistency with the existing code
- [ ] No new architecture, layer, dependency or state-management pattern; the change follows the nearest existing sibling.
- [ ] No duplicate: every new component, modifier, helper or use case was checked against existing ones.
- [ ] Navigation uses the app's existing navigation pattern.
- [ ] Readable by a human without the PR: clear names, no clever indirection, comments explain *why*.
- [ ] If modules, screens, routes or shared components change, `docs/architecture-map.md` is updated.

## 3. Localisation and accessibility
- [ ] User-facing strings are localised.
- [ ] Accessibility labels on icon-only controls; Dynamic Type and light/dark considered.

## 4. Evidence
- [ ] `scripts/verify.sh` summary is in the PR body (tests **executed**, not only compiled).
- [ ] Devices verified / not verified are listed.

## 5. Maintenance fixes (Sentry)
- [ ] The issue links the Sentry short ID; the fix commit contains `Fixes <SHORT-ID>-<n>`.
- [ ] Crash fix: a regression test failed before the fix and passes after.
- [ ] Hang fix: Instruments before/after on the same scenario, or an explicit statement that none was possible.
- [ ] Measured facts and hypotheses are separated.
