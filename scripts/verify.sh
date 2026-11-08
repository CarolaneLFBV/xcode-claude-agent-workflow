#!/bin/sh
# scripts/verify.sh — local verification before handing work back or opening a PR.
# Runs: SwiftLint, optional version check and script tests, Xcode tests on the newest iOS simulator, the
# deployment-target iOS version (reported as not run if its runtime is missing) and macOS.
# Configure SCHEME / MIN_IOS / HAS_MACOS below or with AGENT_* environment variables.
# Prints a Markdown summary to paste in the PR body. Exit code != 0 if anything fails.
#
# Usage: scripts/verify.sh [--quick] [--no-macos] [--no-version]
#   --quick       tests on latest iOS only (inner loop; not enough for a PR)
#   --no-macos    skip macOS tests (only when no shared code is touched)
#   --no-version  skip the version check (before the first bump)

set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
export PYTHONDONTWRITEBYTECODE=1   # no __pycache__ left in ci_scripts/ or scripts/

# ---- Configure for your project ----------------------------------------------------------------
SCHEME="${AGENT_SCHEME:-MyApp}"          # your Xcode scheme
MIN_IOS="${AGENT_MIN_IOS:-26}"           # deployment target major version
HAS_MACOS="${AGENT_HAS_MACOS:-1}"        # 0 if the scheme has no macOS destination
BASE_BRANCH="${AGENT_BASE_BRANCH:-main}" # branch your PRs target
# ---------------------------------------------------------------------------------------------------

QUICK=0; MACOS=$HAS_MACOS; VERSION=1
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    --no-macos) MACOS=0 ;;
    --no-version) VERSION=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

OUT=$(mktemp -d "${TMPDIR:-/tmp}/agent-verify.XXXXXX")
SUMMARY="$OUT/summary.md"
FAILED=0

row() { printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "$SUMMARY"; }

{
  echo "### scripts/verify.sh"
  echo
  echo "Commit \`$(git rev-parse --short HEAD)\` on \`$(git branch --show-current)\` — $(date -u +%Y-%m-%dT%H:%MZ), $(xcodebuild -version | head -1)"
  echo
  echo "| Check | Result | Details |"
  echo "| --- | --- | --- |"
} > "$SUMMARY"

# 1. SwiftLint
if swiftlint lint --quiet > "$OUT/swiftlint.log" 2>&1; then
  row "SwiftLint" "✅" "$(grep -c 'warning:' "$OUT/swiftlint.log" | tr -d ' ') warning(s)"
else
  row "SwiftLint" "❌" "$(grep -c 'error:' "$OUT/swiftlint.log" | tr -d ' ') error(s)"; FAILED=1
fi

# 2. Version check (optional: only if your repo has scripts/version.py)
if [ ! -f scripts/version.py ]; then
  row "Version check" "⏭️" "no scripts/version.py"
elif [ "$VERSION" -eq 1 ]; then
  git fetch --quiet origin "$BASE_BRANCH"
  if python3 scripts/version.py check --base "origin/$BASE_BRANCH" > "$OUT/version.log" 2>&1; then
    row "Version check" "✅" "newer than origin/$BASE_BRANCH"
  else
    row "Version check" "❌" "see version.py output"; FAILED=1
  fi
else
  row "Version check" "⏭️" "skipped (--no-version)"
fi

# 3. Script tests (optional: Python tests named scripts/test_*.py)
if ! ls scripts/test_*.py >/dev/null 2>&1; then
  row "Script tests" "⏭️" "no scripts/test_*.py"
elif python3 -m unittest discover -s scripts -p 'test_*.py' > "$OUT/scripts.log" 2>&1; then
  row "Script tests" "✅" "$(grep -E '^Ran [0-9]+ test' "$OUT/scripts.log" | head -1)"
else
  row "Script tests" "❌" "$(tail -1 "$OUT/scripts.log")"; FAILED=1
fi

# 4. Xcode tests
# Simulators are picked from what is installed (newest iPhone runtime, and an iOS $MIN_IOS.x runtime for the
# deployment target). Override with AGENT_SIM_LATEST / AGENT_SIM_MIN (simulator UDID).
pick_simulator() { # $1 = "latest" or a major version (e.g. 26) -> prints "UDID|label", or nothing
  xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, re, sys
want = sys.argv[1]
devices = json.load(sys.stdin).get("devices", {})
best = None
for runtime, items in devices.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    if want != "latest" and version[0] != int(want):
        continue
    for d in items:
        if not d.get("name", "").startswith("iPhone"):
            continue
        pro = "Pro" in d["name"]
        key = (version, pro) if want == "latest" else ((-version[0], -version[1]), pro)
        if best is None or key > best[0]:
            best = (key, d["udid"], "%s (iOS %d.%d)" % (d["name"], version[0], version[1]))
if best:
    print(best[1] + "|" + best[2])
' "$1"
}

run_tests() { # $1 label, $2 destination
  name=$(printf '%s' "$1" | tr ' /' '__')
  bundle="$OUT/$name.xcresult"
  start=$(date +%s)
  if xcodebuild test -scheme "$SCHEME" -destination "$2" -resultBundlePath "$bundle" -quiet > "$OUT/$name.log" 2>&1; then
    status="✅"
  else
    status="❌"; FAILED=1
  fi
  secs=$(( $(date +%s) - start ))
  counts=$(xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("%s passed, %s failed, %s skipped" % (d.get("passedTests", 0), d.get("failedTests", 0), d.get("skippedTests", 0)))
except Exception:
    print("no result bundle (build or destination error, see log)")
')
  row "Tests $1" "$status" "$counts, ${secs}s"
}

LATEST="${AGENT_SIM_LATEST:-}"; LATEST_LABEL="override"
if [ -z "$LATEST" ]; then SIM=$(pick_simulator latest); LATEST="${SIM%%|*}"; LATEST_LABEL="${SIM#*|}"; fi
if [ -n "$LATEST" ]; then
  run_tests "iOS latest — $LATEST_LABEL" "platform=iOS Simulator,id=$LATEST"
else
  row "Tests iOS latest" "❌" "no iPhone simulator installed"; FAILED=1
fi
if [ "$QUICK" -eq 0 ]; then
  MIN="${AGENT_SIM_MIN:-}"; MIN_LABEL="override"
  if [ -z "$MIN" ]; then SIM=$(pick_simulator "$MIN_IOS"); MIN="${SIM%%|*}"; MIN_LABEL="${SIM#*|}"; fi
  if [ -n "$MIN" ]; then
    run_tests "iOS $MIN_IOS — $MIN_LABEL" "platform=iOS Simulator,id=$MIN"
  else
    row "Tests iOS $MIN_IOS (deployment target)" "⚠️" "not run: no iOS $MIN_IOS runtime (xcodebuild -downloadPlatform iOS -buildVersion $MIN_IOS.0)"
  fi
  if [ "$MACOS" -eq 1 ]; then run_tests "macOS" "platform=macOS"; else row "Tests macOS" "⏭️" "skipped (--no-macos)"; fi
else
  row "Tests iOS $MIN_IOS / macOS" "⏭️" "skipped (--quick, not valid for a PR)"
fi

echo >> "$SUMMARY"
echo "Logs: \`$OUT\`" >> "$SUMMARY"
cat "$SUMMARY"
exit "$FAILED"
