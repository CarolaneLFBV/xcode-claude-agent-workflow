---
description: Triage production crashes and hangs from Sentry, then create the issues the maintainer selects.
argument-hint: "[période, ex. 7d | 30d | 90d]"
---

1. Delegate to the `sentry-triage` subagent for the period `$ARGUMENTS` (default `30d`). Do not query Sentry yourself.
2. Show its ranked table and draft issues to the maintainer, unchanged except for formatting. Do not add conclusions it did not reach.
3. Before proposing a new issue, search existing GitHub issues (`gh issue list --search "<SHORT-ID>-<id>" --state all`) and mark duplicates.
4. **Stop and ask** which drafts to create. Create nothing until the maintainer selects.
5. For each selected draft, create one issue with the user-story template (`.github/ISSUE_TEMPLATE/user-story.md`), the Sentry short ID in the title (`[<SHORT-ID>-<id>] …`) and the Sentry link in the body. Report the created issue numbers.
6. Suggest the order to run `/implement <issue>`. Do not start implementing.
