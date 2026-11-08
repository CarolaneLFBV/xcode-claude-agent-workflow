#!/usr/bin/env bash
# Review a PR with Claude (subagent .claude/agents/reviewer.md) against docs/agents/review-checklist.md
# and post the result on the PR.
# Usage: scripts/agent-review.sh <pr-number> [--dry-run] [--force] [--effort low|medium|high]
#   --force   review a draft PR or an already reviewed commit anyway
#   --effort  override the automatic effort (also AGENT_REVIEW_EFFORT)
# Env: AGENT_REVIEW_MODEL (default opus). Runs on the Claude subscription of the logged-in user.
set -euo pipefail

usage() { echo "Usage: $0 <pr-number> [--dry-run] [--force] [--effort low|medium|high]" >&2; exit 2; }

pr="${1:-}"
[[ "$pr" =~ ^[0-9]+$ ]] || usage
shift
dry_run=false
force=false
effort="${AGENT_REVIEW_EFFORT:-}"
while (($#)); do
    case "$1" in
        --dry-run) dry_run=true ;;
        --force) force=true ;;
        --effort) (($# >= 2)) || usage; effort="$2"; shift ;;
        *) usage ;;
    esac
    shift
done
[[ -z "$effort" || "$effort" =~ ^(low|medium|high)$ ]] || usage
model="${AGENT_REVIEW_MODEL:-opus}"
# Small diffs outside sensitive areas get a medium effort; everything else keeps a high effort.
small_diff_lines=100
sensitive_paths='(/Migrations/|/Data/CloudKit/|/Config/DataSource/|\.entitlements$|\.sh$|^scripts/|^ci_scripts/|^fastlane/|^\.github/workflows/|^\.claude/|^CLAUDE\.md$)'

for tool in gh claude git; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

repo_root="$(git rev-parse --show-toplevel)"
checklist="$repo_root/docs/agents/review-checklist.md"
[[ -f "$checklist" ]] || { echo "Missing $checklist" >&2; exit 1; }

read -r base head cross_repo is_draft title < <(gh pr view "$pr" \
    --json baseRefName,headRefName,isCrossRepository,isDraft,title \
    --jq '[.baseRefName, .headRefName, .isCrossRepository, .isDraft, .title] | @tsv')
if [[ "$is_draft" == "true" ]] && ! $force; then
    echo "PR #$pr is a draft: mark it ready for review first, or pass --force." >&2
    exit 1
fi
pr_body="$(gh pr view "$pr" --json body --jq '.body')"
issue_ref="$(grep -oiE 'Refs #[0-9]+' <<< "$pr_body" | head -1 || true)"

work="$(mktemp -d)"
review_dir="$work/pr-$pr"
cleanup() {
    git -C "$repo_root" worktree remove --force "$review_dir" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

# The API can report a stale head right after a push, so read the head from git: the branch itself for
# same-repository PRs, the PR ref for forks.
head_ref="refs/heads/$head"
[[ "$cross_repo" == "true" ]] && head_ref="refs/pull/$pr/head"
git -C "$repo_root" fetch --quiet origin "$base"
git -C "$repo_root" fetch --quiet origin "$head_ref" || { echo "Could not fetch $head_ref" >&2; exit 1; }
head_sha="$(git -C "$repo_root" rev-parse FETCH_HEAD)"

comments="$(gh pr view "$pr" --json comments --jq '.comments[].body')"
if ! $force && [[ "$comments" == *"Commit reviewed: \`${head_sha:0:8}\`"* ]]; then
    echo "Commit ${head_sha:0:8} of PR #$pr was already reviewed: push changes first, or pass --force." >&2
    exit 1
fi

if [[ -z "$effort" ]]; then
    diff_files="$(git -C "$repo_root" diff --name-only "origin/$base...$head_sha")"
    # Version bumps and translation catalogs inflate the line count without adding review work.
    diff_lines="$(git -C "$repo_root" diff --numstat "origin/$base...$head_sha" \
        | awk '$3 !~ /\.(pbxproj|xcstrings)$/ { n += $1 + $2 } END { print n + 0 }')"
    if ((diff_lines <= small_diff_lines)) && ! grep -qE "$sensitive_paths" <<< "$diff_files"; then
        effort=medium
    else
        effort=high
    fi
fi
git -C "$repo_root" worktree add --quiet --detach "$review_dir" "$head_sha"
[[ -f "$review_dir/.claude/agents/reviewer.md" ]] || {
    echo "The PR head has no .claude/agents/reviewer.md: rebase it on the current base branch first." >&2
    exit 1
}

issue_context=""
if [[ -n "$issue_ref" ]]; then
    issue_context="$(gh issue view "${issue_ref#*#}" --json title,body --jq '"# " + .title + "\n\n" + .body')"
fi

prompt="Review PR #$pr \"$title\" (branch: $head, base: $base).
Review only. Do not modify files, commit, push or comment on GitHub.
The PR changes are \`git diff origin/$base...HEAD\` (commits: \`git log origin/$base..HEAD\`). Read the full
changed files and their surroundings as needed, not only the hunks.

Follow CLAUDE.md and CONTRIBUTING.md in this repository. Load the Apple skills as your instructions say. Review the diff against every item of this checklist:

$(cat "$checklist")

PR description (check workflow rules, validation claims and remaining work against it):

$pr_body

Linked issue (${issue_ref:-none}) — check the PR against its acceptance criteria:

${issue_context:-No linked issue found.}

Do not call GitHub: rely on the PR description and issue above.

Use the output format defined in your agent instructions."

output="$work/review.md"
# Read-only by construction: only Read/Grep/Glob and read-only git commands are allowed, everything else is
# denied without prompting (dontAsk). No MCP server is loaded, no session is saved.
claude_args=(-p --agent reviewer --model "$model" --effort "$effort"
    --tools "Read,Grep,Glob,Bash"
    --allowedTools "Read" "Grep" "Glob" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)"
    --permission-mode dontAsk --strict-mcp-config --no-session-persistence --output-format text)
(cd "$review_dir" && claude "${claude_args[@]}" <<< "$prompt" >"$output" 2>"$work/claude.log") || {
    echo "Claude review failed, log:" >&2
    tail -n 40 "$work/claude.log" >&2
    exit 1
}
[[ -s "$output" ]] || { echo "Claude returned an empty review." >&2; tail -n 40 "$work/claude.log" >&2; exit 1; }

comment="$work/comment.md"
{
    echo "## 🤖 Claude review ($model, effort $effort)"
    echo
    echo "_Commit reviewed: \`${head_sha:0:8}\`. Advisory review against \`docs/agents/review-checklist.md\`._"
    echo
    cat "$output"
} >"$comment"

if $dry_run; then
    cat "$comment"
else
    gh pr comment "$pr" --body-file "$comment"
fi
