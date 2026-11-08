---
description: Run scripts/verify.sh (lint, version check, script tests, Xcode tests) and diagnose any failure.
argument-hint: "[--quick] [--no-macos] [--no-version]"
allowed-tools: Bash(scripts/verify.sh:*), Bash(tail:*), Bash(grep:*), Read
---

1. Run `scripts/verify.sh $ARGUMENTS` from the repository root. It takes several minutes; do not interrupt it.
2. Show the Markdown summary table exactly as printed.
3. If every row passes, stop there.
4. For each failed row, open its log in the `Logs:` folder printed at the end (one `.log` per check). Read only the relevant part (`grep -n "error:"`, failing test names, last lines).
5. For each failure, report: the check, the root cause in one or two sentences, the file and line when there is one, and whether it comes from the code or from the environment (missing simulator runtime, missing gitignored config file, signing, outdated base branch).
6. Do not fix anything unless asked. Never edit `scripts/verify.sh` to make a check pass.
7. Never kill processes, quit apps or shut down simulators: the maintainer may be using them. If something blocks a run, report it.
