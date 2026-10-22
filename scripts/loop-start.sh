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
#   bash scripts/loop-start.sh [--dry-run] cleanup [--dry-run]
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
# `cleanup` runs `git fetch origin` and `gh repo view`, then removes an Orca
# worktree of the repository only if all of these hold, checked in this order
# (the first failing rule is printed as the keep reason): not the main worktree
# nor the one this script runs in; status `completed`; name `<change>`,
# `<change>-impl`, `<change>-judge`, `<change>-judge-<N>` or `<change>-archive`
# of a change directory on origin/<default>; HEAD an ancestor of
# origin/<default>; linked PR, if any, MERGED or CLOSED; no uncommitted or
# untracked files. --dry-run prints `<name>  remove` or `<name>  keep: <reason>`
# for every worktree and removes nothing. The real run prints the same list,
# evaluates the rules again before each removal, removes with
# `orca-ide worktree rm --worktree path:<path> --json` (never forced), and
# reports per worktree whether its local branch was deleted or kept and which
# Orca terminals remain for its path. It deletes no remote branch.
#
# This script never approves, merges or writes to an existing terminal; the
# operator types `approve <sha>` and `fix` in the worker's own terminal.
#
# Exit codes: 0 launched, dry run done or status shown; 1 a gh, git, Orca,
# loop-prompt.sh or loop-launch.sh call failed; 2 usage; 3 no merged spec PR
# (implement); 4 no open implementation PR (judge); 5 implementation PR not
# merged (archive); 6 worktree or branch of the worker's name present; 7 intake
# issue missing or closed; 8 a cleanup removal failed (no further worktree
# attempted). Nothing is launched or removed on a non-zero exit before the
# launch or removal itself.
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
       loop-start.sh [--dry-run] cleanup [--dry-run]
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
  cleanup)
    if [ "$#" = 1 ] && [ "$1" = --dry-run ] && [ "$dry" = 0 ]; then dry=1; shift; fi
    [ "$#" = 0 ] || usage ;;
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
pat = re.compile(r"^(?:\*\*)?Verdict:\s*(.*?)\s+at\s+([0-9a-fA-F]{7,40})\b")
loop_prs = [p for p in prs if p["title"].startswith(("spec: ", "impl: ", "archive: "))]
info = {}
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
    info[p["number"]] = (head, ci, verdict, at_head)
# A spec or archive PR whose worker waits for "type: approve <sha7>" at the PR
# head: the PR line and the worktree line give the same action, and say to wait
# for CI while the required check has not succeeded on the head (loop-merge.sh
# would refuse the approval with exit 5).
pr_act, wt_act = {}, {}
for w in active:
    comment = w.get("comment") or ""
    m = re.search(r"type: approve ([0-9a-fA-F]{7,40})\b", comment)
    if w.get("workspaceStatus") != "in-review" or not m:
        continue
    r = re.search(r"PR #(\d+)", comment)
    n = int(w["linkedPR"]) if w.get("linkedPR") else (int(r.group(1)) if r else None)
    p = next((p for p in loop_prs if p["number"] == n and p["title"].startswith(("spec: ", "archive: "))), None)
    sha = m.group(1).lower()
    if p is None or not info[n][0].startswith(sha):
        continue
    head, ci = info[n][0], info[n][1]
    then = f"type approve {sha} in the terminal of {name(w)}"
    act = f"ACT: {then}" if ci == "SUCCESS" else f"ACT: wait for CI ({check}: {ci} on {head[:7]}), then {then}"
    pr_act.setdefault(n, act)
    wt_act[name(w)] = act
print(f"Worktrees ({len(active)} listed, {len(done)} completed not listed):")
for w in active:
    status, comment = w.get("workspaceStatus") or "none", w.get("comment") or ""
    print(f"  {name(w)}  [{status}]  {comment or '(no comment)'}")
    # Only a "type: approve <sha>" or "type: fix" line is a reply typed in that
    # worktree's terminal; "ready for the judge" asks the operator to launch the judge.
    if status != "in-review":
        print("    -> no action")
    elif name(w) in wt_act:
        print(f"    -> {wt_act[name(w)]}")
    elif "ready for the judge" in comment:
        m = re.search(r"PR #(\d+)", comment)
        n = m.group(1) if m else (str(w["linkedPR"]) if w.get("linkedPR") else "<PR>")
        print(f"    -> ACT: judge it with /sdd-loop judge {n} (bash scripts/loop-start.sh judge {n})")
    elif re.search(r"type: (approve [0-9a-fA-F]{7,40}|fix)\b", comment):
        print(f"    -> ACT in the terminal of {name(w)}: {comment}")
    else:
        print(f"    -> ACT: {comment}")
print(f"Open loop PRs ({len(loop_prs)}):")
for p in loop_prs:
    head, ci, verdict, at_head = info[p["number"]]
    print(f"  #{p['number']} {p['title']}  head {head[:7]}  {check}: {ci}  verdict: {verdict}")
    act = pr_act.get(p["number"], "no action")
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

# --- cleanup: remove finished loop worktrees ---
if [ "$verb" = cleanup ]; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  orca_worktrees > "$work/list.json"
  current=$("$GIT_CMD" rev-parse --show-toplevel) || fail "git rev-parse --show-toplevel failed"
  "$GIT_CMD" ls-tree "origin/$default_branch" openspec/changes/ openspec/changes/archive/ > "$work/tree" \
    || fail "git ls-tree origin/$default_branch failed"

  # rows <list.json>: one tab-separated line per worktree: name, path, branch,
  # linked PR and the keep reason of rules 1-3 ("-" when none applies).
  rows() {
    python3 -I - "$1" "$work/tree" "$current" <<'PY' || fail "cannot read orca-ide worktree list or git ls-tree result"
import json, os, re, sys
wts = json.load(open(sys.argv[1]))
changes = set()
for line in open(sys.argv[2]):
    meta, _, path = line.rstrip("\n").partition("\t")
    parts = path.rstrip("/").split("/")
    if meta.split()[1:2] != ["tree"] or parts[:2] != ["openspec", "changes"]:
        continue
    if len(parts) == 3 and parts[2] != "archive":
        changes.add(parts[2])
    elif len(parts) == 4 and parts[2] == "archive":
        m = re.fullmatch(r"\d{4}-\d{2}-\d{2}-(.+)", parts[3])
        if m:
            changes.add(m.group(1))
def loop_name(n):
    if n in changes or any(n.endswith(s) and n[:-len(s)] in changes for s in ("-impl", "-judge", "-archive")):
        return True
    m = re.fullmatch(r"(.+)-judge-([1-9][0-9]*)", n)
    return bool(m and int(m.group(2)) >= 2 and m.group(1) in changes)
cur = os.path.realpath(sys.argv[3])
for w in wts:
    path = w["path"].rstrip("/")
    name = path.rsplit("/", 1)[-1]
    status = w.get("workspaceStatus") or "none"
    if w.get("isMainWorktree"):
        reason = "main worktree"
    elif os.path.realpath(path) == cur:
        reason = "current worktree"
    elif status != "completed":
        reason = f"status {status}, not completed"
    elif not loop_name(name):
        reason = "not a loop worker name"
    else:
        reason = "-"
    print(name, path, w.get("branch") or "-", w.get("linkedPR") or "-", reason, sep="\t")
PY
  }

  # decide <path> <linked-pr> <reason of rules 1-3>: sets $reason to the first
  # failing rule, or to "" when every rule holds. A failing call exits 1.
  decide() {
    local path=$1 n=$2 head rc=0 state dirty
    reason=$3
    [ "$reason" = - ] || return 0
    reason=""
    head=$("$GIT_CMD" -C "$path" rev-parse HEAD) || fail "git rev-parse HEAD in $path failed"
    "$GIT_CMD" merge-base --is-ancestor "$head" "origin/$default_branch" || rc=$?
    case $rc in
      0) ;;
      1) reason="HEAD ${head:0:7} not merged into origin/$default_branch"; return 0 ;;
      *) fail "git merge-base --is-ancestor failed for $path" ;;
    esac
    if [ "$n" != - ]; then
      state=$("$GH_CMD" pr view "$n" --json state | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["state"])') \
        || fail "gh pr view #$n failed"
      case $state in
        MERGED|CLOSED) ;;
        *) reason="linked PR #$n is $state"; return 0 ;;
      esac
    fi
    dirty=$("$GIT_CMD" -C "$path" status --porcelain --untracked-files=normal) || fail "git status in $path failed"
    [ -z "$dirty" ] || reason="uncommitted changes"
  }

  rows "$work/list.json" > "$work/rows"
  : > "$work/remove"
  n_rm=0 n_keep=0
  while IFS=$'\t' read -r -u 3 name path branch linked pre; do
    decide "$path" "$linked" "$pre"
    if [ -z "$reason" ]; then
      echo "$name  remove"
      printf '%s\t%s\t%s\n' "$name" "$path" "$branch" >> "$work/remove"
      n_rm=$((n_rm + 1))
    else
      echo "$name  keep: $reason"
      n_keep=$((n_keep + 1))
    fi
  done 3< "$work/rows"
  echo "$n_rm to remove, $n_keep kept"
  if [ "$dry" = 1 ]; then
    echo "dry run: nothing removed"
    exit 0
  fi

  mapfile -t todo < "$work/remove"
  removed=()
  for i in "${!todo[@]}"; do
    IFS=$'\t' read -r name path branch <<<"${todo[$i]}"
    # The rules again, on a list read just now: a worktree that changed is kept.
    orca_worktrees > "$work/list.json"
    rows "$work/list.json" > "$work/rows"
    line=$(awk -F'\t' -v p="$path" '$2 == p' "$work/rows")
    if [ -z "$line" ]; then echo "$name  keep: no longer listed"; continue; fi
    IFS=$'\t' read -r _ _ _ linked pre <<<"$line"
    decide "$path" "$linked" "$pre"
    if [ -n "$reason" ]; then echo "$name  keep: $reason (changed since the list)"; continue; fi

    rm_rc=0 msg=""
    rm_out=$("$ORCA" worktree rm --worktree "path:$path" --json 2>"$work/rm.err") || rm_rc=$?
    rm_err=$(python3 -I -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
except ValueError:
    print("unparsable result"); sys.exit()
if d.get("ok") is not True:
    print((d.get("error") or {}).get("message") or "not ok")
' "$rm_out")
    if [ "$rm_rc" != 0 ]; then
      msg="orca-ide worktree rm exited $rm_rc: $rm_err $(head -c 300 "$work/rm.err")"
    elif [ -n "$rm_err" ]; then
      msg="orca-ide worktree rm reported: $rm_err"
    else
      orca_worktrees > "$work/list.json"
      if python3 -I -c '
import json, sys
sys.exit(0 if any(w["path"].rstrip("/") == sys.argv[2] for w in json.load(open(sys.argv[1]))) else 1)
' "$work/list.json" "$path"; then
        msg="still listed by orca-ide worktree list after removal"
      fi
    fi
    if [ -n "$msg" ]; then
      rest=()
      for j in "${!todo[@]}"; do [ "$j" -le "$i" ] || rest+=("${todo[$j]%%$'\t'*}"); done
      echo "cleanup: removal of $name failed: $msg; ${#removed[@]} removed (${removed[*]:-none}), not attempted: ${rest[*]:-none}" >&2
      exit 8
    fi
    removed+=("$name")

    if [ "$branch" = - ]; then
      b="none"
    else
      rc=0
      "$GIT_CMD" show-ref --verify --quiet "$branch" || rc=$?
      case $rc in
        0) b="${branch#refs/heads/} kept" ;;
        1) b="${branch#refs/heads/} deleted" ;;
        *) fail "git show-ref for $branch failed after removing $name" ;;
      esac
    fi
    terms=$("$ORCA" terminal list --json | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
if d.get("ok") is not True or d["result"].get("truncated"):
    sys.exit(1)
h = [t["handle"] for t in d["result"]["terminals"] if (t.get("worktreePath") or "").rstrip("/") == sys.argv[1]]
print(", ".join(h) or "none")
' "$path") || fail "orca-ide terminal list failed after removing $name"
    echo "removed $name: branch $b; terminals: $terms"
  done
  echo "cleanup: ${#removed[@]} removed (${removed[*]:-none})"
  exit 0
fi

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
