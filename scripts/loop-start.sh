#!/usr/bin/env bash
# Launcher for the spec-driven loop: starts a loop step with every launch-time
# value derived from GitHub, so the operator types only the change name, brief,
# issue number or PR number. The sdd-loop skill calls this script.
#
#   bash scripts/loop-start.sh [--dry-run] start <change> (--brief <text> | --issue <N>)
#   bash scripts/loop-start.sh [--dry-run] implement <change>
#   bash scripts/loop-start.sh [--dry-run] judge <pr>
#   bash scripts/loop-start.sh [--dry-run] archive <change>
#   bash scripts/loop-start.sh status
#
# A launch runs `git fetch origin`, derives owner, repo and default branch with
# `gh repo view`, finds PRs by the exact titles the templates prescribe
# (`spec: <change>`, `impl: <change>`) and the issue from the PR body's
# `Refs #<N>` line, refuses what it cannot derive, builds the prompt with
# loop-prompt.sh into a mktemp file outside the repository, and launches with
# loop-launch.sh:
#
#   verb       template    worker name               agent   base
#   start      propose.md  <change>                  claude  origin/<default>
#   implement  apply.md    <change>-impl             claude  origin/<default>
#   judge      judge.md    <change>-judge[-N]        codex   origin/<PR head branch>
#   archive    archive.md  <change>-archive          claude  origin/<default>
#
# --dry-run does everything up to and including the prompt, then prints the
# prompt path and the launch command instead of launching. `status` is read
# only: it lists the loop worktrees and open loop PRs and where the operator acts.
#
# This script never approves, merges or writes to an existing terminal; the
# operator types `approve <sha>` and `fix` in the worker's own terminal.
#
# Exit codes: 0 launched, dry run done or status shown; 1 a gh, git, Orca,
# loop-prompt.sh or loop-launch.sh call failed; 2 usage; 3 no merged spec PR
# (implement); 4 no open implementation PR (judge); 5 implementation PR not
# merged (archive); 6 worktree or branch of the worker's name present; 7 intake
# issue missing or closed. Nothing is launched on a non-zero exit before the
# launch itself.
#
# Environment (all optional; tests point them at stubs):
#   GH, GIT, ORCA_IDE        commands (default: gh, git, orca-ide)
#   LOOP_PROMPT, LOOP_LAUNCH helper scripts run with bash (default: next to this script)
#   LOOP_REQUIRED_CHECK      check shown by status (default: openspec)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GH_CMD=${GH:-gh}
GIT_CMD=${GIT:-git}
ORCA=${ORCA_IDE:-orca-ide}
PROMPT_HELPER=${LOOP_PROMPT:-$here/loop-prompt.sh}
LAUNCH_HELPER=${LOOP_LAUNCH:-$here/loop-launch.sh}
TEMPLATES=$here/../.agents/loop
REMINDER="The operator types 'approve <sha>' and 'fix' in the worker's own terminal; this launcher never approves or merges."

usage() {
  cat >&2 <<'EOF'
usage: loop-start.sh [--dry-run] start <change> (--brief <text> | --issue <N>)
       loop-start.sh [--dry-run] implement <change>
       loop-start.sh [--dry-run] judge <pr>
       loop-start.sh [--dry-run] archive <change>
       loop-start.sh status
EOF
  exit 2
}
fail() { echo "loop-start: $1" >&2; exit 1; }
refuse() { echo "loop-start: $2; nothing launched" >&2; exit "$1"; }
kebab() { [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "loop-start: change name must be kebab-case, got '$1'" >&2; exit 2; }; }
number() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "loop-start: $2 must be a number, got '$1'" >&2; exit 2; }; }

# --- usage: checked completely before any command runs ---
dry=0
if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi
[ "$#" -ge 1 ] || usage
verb=$1; shift
change="" brief="" issue="" pr="" have_brief=0
case "$verb" in
  start)
    [ "$#" -ge 1 ] || usage
    change=$1; shift
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --brief) [ "$#" -ge 2 ] && [ "$have_brief" = 0 ] || usage; brief=$2; have_brief=1; shift 2 ;;
        --issue) [ "$#" -ge 2 ] && [ -z "$issue" ] || usage; issue=$2; shift 2 ;;
        *) usage ;;
      esac
    done
    [ $((have_brief + (${#issue} > 0))) = 1 ] || { echo "loop-start: start takes exactly one of --brief and --issue" >&2; exit 2; }
    kebab "$change"
    [ "$have_brief" = 1 ] && { [[ "$brief" =~ [^[:space:]] ]] || { echo "loop-start: --brief must not be empty" >&2; exit 2; }; }
    [ -z "$issue" ] || number "$issue" "--issue" ;;
  implement|archive)
    [ "$#" = 1 ] || usage
    change=$1; kebab "$change" ;;
  judge)
    [ "$#" = 1 ] || usage
    pr=$1; number "$pr" "PR" ;;
  status)
    [ "$#" = 0 ] && [ "$dry" = 0 ] || usage ;;
  *) usage ;;
esac

# Repository path as Orca knows it: the main worktree, parent of the common .git.
repo_path() {
  local common
  common=$("$GIT_CMD" rev-parse --path-format=absolute --git-common-dir) || fail "git rev-parse failed"
  [[ "$common" == */.git ]] || fail "cannot locate the main worktree from git common dir '$common'"
  printf '%s\n' "${common%/.git}"
}

# Orca worktree list of the repository as JSON; refuses a truncated list.
orca_worktrees() {
  local top out rc=0
  top=$(repo_path)
  out=$("$ORCA" worktree list --repo "path:$top" --limit 1000 --json) || rc=$?
  # --json reports errors on stdout.
  if grep -q '"repo_not_found"' <<<"$out"; then
    fail "this checkout ($top) is not a repository registered in Orca; run from an Orca worktree of the repository"
  fi
  [ "$rc" = 0 ] || fail "orca-ide worktree list failed"
  python3 -I -c '
import json, sys
d = json.load(sys.stdin)
if d.get("ok") is not True or d["result"].get("truncated"):
    sys.exit(1)
json.dump(d["result"]["worktrees"], sys.stdout)
' <<<"$out" || fail "cannot read orca-ide worktree list result (not ok, truncated or unparsable)"
}

# --- status: read only ---
if [ "$verb" = status ]; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  orca_worktrees > "$work/worktrees.json"
  "$GH_CMD" pr list --state open --limit 100 --json number,title,headRefName > "$work/prs.json" || fail "gh pr list failed"
  numbers=$(python3 -I -c '
import json, sys
for p in json.load(open(sys.argv[1])):
    if p["title"].startswith(("spec: ", "impl: ", "archive: ")):
        print(p["number"])
' "$work/prs.json") || fail "cannot read gh pr list result"
  for n in $numbers; do
    "$GH_CMD" pr view "$n" --json headRefOid,statusCheckRollup,comments > "$work/pr-$n.json" || fail "gh pr view #$n failed"
  done
  python3 -I - "$work" "${LOOP_REQUIRED_CHECK:-openspec}" <<'PY' || fail "cannot read Orca or gh results for status"
import json, os, re, sys
work, check = sys.argv[1], sys.argv[2]
wts = json.load(open(os.path.join(work, "worktrees.json")))
prs = json.load(open(os.path.join(work, "prs.json")))
name = lambda w: w["path"].rstrip("/").rsplit("/", 1)[-1]
loop = [w for w in wts if not w.get("isMainWorktree")]
done = [w for w in loop if w.get("workspaceStatus") == "completed"]
active = sorted((w for w in loop if w.get("workspaceStatus") != "completed"),
                key=lambda w: w.get("lastActivityAt") or 0, reverse=True)
print(f"Worktrees ({len(active)} listed, {len(done)} completed not listed):")
for w in active:
    status, comment = w.get("workspaceStatus") or "none", w.get("comment") or ""
    print(f"  {name(w)}  [{status}]  {comment or '(no comment)'}")
    # Only a "type: approve <sha>" or "type: fix" line is a reply typed in that
    # worktree's terminal; "ready for the judge" asks the operator to launch the judge.
    if status != "in-review":
        print("    -> no action")
    elif "ready for the judge" in comment:
        m = re.search(r"PR #(\d+)", comment)
        n = m.group(1) if m else (str(w["linkedPR"]) if w.get("linkedPR") else "<PR>")
        print(f"    -> ACT: judge it with /sdd-loop judge {n} (bash scripts/loop-start.sh judge {n})")
    elif re.search(r"type: (approve [0-9a-fA-F]{7,40}|fix)\b", comment):
        print(f"    -> ACT in the terminal of {name(w)}: {comment}")
    else:
        print(f"    -> ACT: {comment}")
pat = re.compile(r"^(?:\*\*)?Verdict:\s*(.*?)\s+at\s+([0-9a-fA-F]{7,40})\b")
loop_prs = [p for p in prs if p["title"].startswith(("spec: ", "impl: ", "archive: "))]
print(f"Open loop PRs ({len(loop_prs)}):")
for p in loop_prs:
    v = json.load(open(os.path.join(work, f"pr-{p['number']}.json")))
    head = v["headRefOid"].lower()
    runs = [c for c in v.get("statusCheckRollup") or [] if (c.get("name") or c.get("context")) == check]
    if not runs:
        ci = "missing"
    else:
        c = max(runs, key=lambda c: c.get("completedAt") or c.get("startedAt") or "")
        ci = c.get("state") if "state" in c else (c.get("conclusion") or c.get("status"))
    found = sorted(((c.get("createdAt") or "", c.get("body") or "") for c in v.get("comments") or []
                    if pat.match(c.get("body") or "")), key=lambda f: f[0])
    if found:
        line = found[-1][1].splitlines()[0]
        at = pat.match(found[-1][1]).group(2).lower()
        verdict, at_head = f"{line} ({'at head' if head.startswith(at) else 'not at head ' + head[:7]})", head.startswith(at)
    else:
        verdict, at_head = "none", False
    print(f"  #{p['number']} {p['title']}  head {head[:7]}  {check}: {ci}  verdict: {verdict}")
    act = "no action"
    if p["title"].startswith("impl: ") and not at_head:
        change = p["title"][len("impl: "):]
        judging = [w for w in active if w.get("workspaceStatus") == "in-progress"
                   and re.fullmatch(re.escape(change) + r"-judge(-\d+)?", name(w))]
        if judging:
            act = f"no action (judge {name(judging[0])} in progress)"
        else:
            act = f"ACT: judge it with /sdd-loop judge {p['number']} (bash scripts/loop-start.sh judge {p['number']})"
    print(f"    -> {act}")
PY
  echo "$REMINDER"
  exit 0
fi

# --- derive common values ---
"$GIT_CMD" fetch origin >/dev/null || fail "git fetch origin failed"
repo_json=$("$GH_CMD" repo view --json nameWithOwner,defaultBranchRef) || fail "gh repo view failed"
read -r owner_repo default_branch < <(python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(d["nameWithOwner"], d["defaultBranchRef"]["name"])
' <<<"$repo_json") || fail "cannot read gh repo view result"
[[ "$owner_repo" == */* ]] && [ -n "$default_branch" ] || fail "cannot read gh repo view result"
owner=${owner_repo%%/*} repo=${owner_repo#*/}

# find_pr <title>: newest merged PR with exactly that title. Prints
# "<number> <merge-commit> <issue-or-none>" on line 1 (or "none") and the other
# PRs with that title on line 2.
find_pr() {
  local list
  list=$("$GH_CMD" pr list --state all --limit 50 --search "\"$1\" in:title" --json number,title,state,mergedAt,mergeCommit,body) \
    || fail "gh pr list for '$1' failed"
  python3 -I -c '
import json, re, sys
title, prs = sys.argv[1], json.load(sys.stdin)
exact = [p for p in prs if p["title"] == title]
merged = sorted((p for p in exact if p["state"] == "MERGED"), key=lambda p: p.get("mergedAt") or "", reverse=True)
if merged:
    p = merged[0]
    m = re.search(r"^Refs #(\d+)\b", p.get("body") or "", re.M)
    print(p["number"], (p.get("mergeCommit") or {}).get("oid") or "-", m.group(1) if m else "none")
else:
    print("none")
print(", ".join("#%d (%s)" % (p["number"], p["state"]) for p in exact if not merged or p is not merged[0]))
' "$1" <<<"$list" || fail "cannot read gh pr list result for '$1'"
}

agent=claude base="origin/$default_branch" keys=() others=""
case "$verb" in
  start)
    template=propose name=$change
    if [ -n "$issue" ]; then
      iv_rc=0
      iv=$("$GH_CMD" issue view "$issue" --json state,url 2>&1) || iv_rc=$?
      if [ "$iv_rc" != 0 ]; then
        [[ "$iv" == *"Could not resolve"* ]] && refuse 7 "issue #$issue does not exist"
        fail "gh issue view #$issue failed: $iv"
      fi
      istate=$(python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(d["state"] if "/issues/" in d.get("url", "") else "NOT_AN_ISSUE")
' <<<"$iv") || fail "cannot read gh issue view result"
      [ "$istate" = OPEN ] || refuse 7 "issue #$issue is $istate, not an open issue"
      keys+=("issue-number=$issue")
    else
      keys+=("brief=$brief")
    fi ;;
  implement)
    template=apply name=$change-impl
    found=$(find_pr "spec: $change")
    read -r spec_pr spec_commit issue <<<"${found%%$'\n'*}"
    others=""; [[ "$found" != *$'\n'* ]] || others=${found#*$'\n'}
    [ "$spec_pr" != none ] || refuse 3 "no merged PR titled exactly 'spec: $change'${others:+ (found: $others)}"
    [ "$spec_commit" != - ] || fail "merged PR #$spec_pr has no merge commit in gh's result"
    [ "$issue" != none ] || refuse 3 "merged spec PR #$spec_pr has no 'Refs #<N>' line in its body"
    keys+=("issue-number=$issue" "spec-pr-number=$spec_pr" "spec-merge-commit=$spec_commit" "default-branch=$default_branch") ;;
  archive)
    template=archive name=$change-archive
    found=$(find_pr "impl: $change")
    read -r impl_pr _ issue <<<"${found%%$'\n'*}"
    others=""; [[ "$found" != *$'\n'* ]] || others=${found#*$'\n'}
    [ "$impl_pr" != none ] || refuse 5 "no merged PR titled exactly 'impl: $change'${others:+ (found: $others)}"
    [ "$issue" != none ] || refuse 5 "merged implementation PR #$impl_pr has no 'Refs #<N>' line in its body"
    keys+=("issue-number=$issue" "impl-pr-number=$impl_pr") ;;
  judge)
    template=judge agent=codex
    pv_rc=0
    pv=$("$GH_CMD" pr view "$pr" --json state,title,headRefName,body 2>&1) || pv_rc=$?
    if [ "$pv_rc" != 0 ]; then
      [[ "$pv" == *"Could not resolve"* ]] && refuse 4 "PR #$pr does not exist"
      fail "gh pr view #$pr failed: $pv"
    fi
    read -r pstate change head_branch issue < <(python3 -I -c '
import json, re, sys
d = json.load(sys.stdin)
m = re.fullmatch(r"impl: ([a-z0-9]+(?:-[a-z0-9]+)*)", d["title"])
r = re.search(r"^Refs #(\d+)\b", d.get("body") or "", re.M)
print(d["state"], m.group(1) if m else "-", d["headRefName"] or "-", r.group(1) if r else "none")
' <<<"$pv") || fail "cannot read gh pr view result for #$pr"
    [ "$pstate" = OPEN ] || refuse 4 "PR #$pr is $pstate, not an open implementation PR"
    [ "$change" != - ] || refuse 4 "PR #$pr is not titled 'impl: <change>'"
    [ "$issue" != none ] || issue=""
    base="origin/$head_branch"
    keys+=("pr-number=$pr") ;;
esac
[ "$issue" != none ] || issue=""
keys=("owner=$owner" "repo=$repo" "change-name=$change" "${keys[@]}")

# --- name-taken check: Orca worktrees by name, local and origin branches by name or /name ---
worktrees=$(orca_worktrees)
refs=$("$GIT_CMD" for-each-ref --format='%(refname)' refs/heads refs/remotes/origin) || fail "git for-each-ref failed"
taken() {
  local n=$1 r b
  python3 -I -c '
import json, sys
sys.exit(0 if any(w["path"].rstrip("/").rsplit("/", 1)[-1] == sys.argv[1] for w in json.load(sys.stdin)) else 1)
' "$n" <<<"$worktrees" && return 0
  while IFS= read -r r; do
    b=${r#refs/heads/}; b=${b#refs/remotes/origin/}
    [ "$b" = "$n" ] || [[ "$b" == */"$n" ]] && return 0
  done <<<"$refs"
  return 1
}
if [ "$verb" = judge ]; then
  name=$change-judge k=2
  while taken "$name"; do name=$change-judge-$k; k=$((k + 1)); done
fi
taken "$name" && refuse 6 "a worktree or branch named '$name' (or ending in '/$name') already exists"

# --- prompt ---
promptfile=$(mktemp "${TMPDIR:-/tmp}/loop-start-$name.XXXXXX") || fail "mktemp failed"
prompt_out=$(bash "$PROMPT_HELPER" "$TEMPLATES/$template.md" "$promptfile" "${keys[@]}" 2>&1) || {
  rm -f "$promptfile"
  fail "loop-prompt.sh refused: $prompt_out"
}
[ -z "$others" ] || echo "loop-start: other PRs with that title, not used: $others"

launch=("$name" "$agent" "$promptfile" --base-branch "$base")
[ -z "$issue" ] || launch+=(--issue "$issue")
echo "prompt: $promptfile"
if [ "$dry" = 1 ]; then
  printf 'launch (dry run, not run): bash scripts/loop-launch.sh'
  printf ' %q' "${launch[@]}"
  printf '\n'
  echo "$REMINDER"
  exit 0
fi

launch_rc=0
launch_out=$(bash "$LAUNCH_HELPER" "${launch[@]}" 2>&1) || launch_rc=$?
printf '%s\n' "$launch_out"
if [ "$launch_rc" != 0 ]; then
  cat >&2 <<EOF
loop-start: loop-launch.sh exited $launch_rc; the worktree '$name' may exist without a confirmed prompt. Not retried, not removed.
loop-start: fallback: orca-ide terminal read --terminal <handle> --screen; if the agent sits at an empty input,
  resend the text of $promptfile once, as under "Failure handling" in docs/dev-loop.md.
EOF
  exit 1
fi
handle=$(grep -oE 'handle=[^ ]+' <<<"$launch_out" | head -n1 | cut -d= -f2)
case "$verb" in
  start)     next="wait for its 'review, then type: approve <sha7>' line in Orca, review the spec PR, then type approve <sha7> in the terminal of $name" ;;
  implement) next="wait for its 'ready for the judge' line in Orca, then launch the judge with /sdd-loop judge <PR>" ;;
  judge)     next="wait for the verdict on the builder's worktree ($change-impl), then type approve <sha7> or fix in the builder's terminal" ;;
  archive)   next="wait for its 'review, then type: approve <sha7>' line in Orca, review the archive PR, then type approve <sha7> in the terminal of $name" ;;
esac
echo "worker: $name ($agent, base $base)"
echo "terminal: ${handle:-unknown}"
echo "next: $next"
echo "$REMINDER"
