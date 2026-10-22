#!/usr/bin/env bash
# Simulation test for scripts/loop-start.sh. Uses fake gh, git, orca-ide and
# loop-launch.sh (nothing reaches GitHub or Orca, no worker is launched) and a
# wrapper around the real loop-prompt.sh, to drive every launcher scenario.
# Checks the exit code, the prompt keys, the launch arguments, which calls were
# made and key output. Exits non-zero on any mismatch.
#
#   bash scripts/test-loop-start.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER=${HELPER:-$here/loop-start.sh}
[ -f "$HELPER" ] || { echo "test-loop-start: helper not found: $HELPER" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
FIX=$work/fix LOG=$work/log
SPEC_SHA=abc1234def5678901234567890abcdef12345678
HEAD_SHA=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
MERGED_SHA=feedface00112233445566778899aabbccddeeff

# Fake gh. Reads fixtures from $FIX; every call is appended to $LOG.
#   repo.json            gh repo view (missing file: the call fails)
#   prs.json             gh pr list --state all (unfiltered: the launcher must match titles exactly)
#   open.json            gh pr list --state open
#   pr-<N>.json          gh pr view <N> (missing: "Could not resolve")
#   view-<N>.json        gh pr view <N> --json headRefOid,... (status)
#   issue-<N>.json       gh issue view <N> (missing: "Could not resolve")
#   (cleanup reads a linked PR's state from pr-<N>.json)
cat > "$work/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
case "$1 $2" in
  "repo view") [ -f "$FIX/repo.json" ] || { echo "HTTP 502" >&2; exit 1; }; cat "$FIX/repo.json" ;;
  "pr list") if [[ " $* " == *" --state all "* ]]; then cat "$FIX/prs.json"; else cat "$FIX/open.json"; fi ;;
  "pr view")
    if [[ "$*" == *headRefOid* ]]; then cat "$FIX/view-$3.json"
    elif [ -f "$FIX/pr-$3.json" ]; then cat "$FIX/pr-$3.json"
    else echo "GraphQL: Could not resolve to a PullRequest with the number of $3. (repository.pullRequest)" >&2; exit 1; fi ;;
  "issue view")
    [ -f "$FIX/issue-$3.json" ] || { echo "GraphQL: Could not resolve to an issue or pull request with the number of $3." >&2; exit 1; }
    cat "$FIX/issue-$3.json" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB

# Fake git: fetch succeeds (unless $FIX/fetch-fail), the main worktree is
# /fake/agent-works, branches from $FIX/refs. For cleanup:
#   toplevel             rev-parse --show-toplevel (default: /fake/agent-works)
#   tree                 ls-tree of the default branch
#   head-<name>          HEAD of /fake/ws/<name> (default: $MERGED_SHA; "fail": the call fails)
#   dirty-<name>         status --porcelain output of /fake/ws/<name>
#   kept-branches        refs show-ref finds (one per line)
# merge-base --is-ancestor succeeds only for $MERGED_SHA.
cat > "$work/git" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "$LOG"
wt=""
[ "$1" != -C ] || { wt=${2##*/}; shift 2; }
case "$1" in
  fetch) [ ! -f "$FIX/fetch-fail" ] || { echo "fatal: unable to access" >&2; exit 128; } ;;
  rev-parse)
    case "$*" in
      *--show-toplevel*) cat "$FIX/toplevel" 2>/dev/null || echo /fake/agent-works ;;
      *HEAD*) h=$(cat "$FIX/head-$wt" 2>/dev/null || echo "$MERGED_SHA"); [ "$h" != fail ] || exit 128; echo "$h" ;;
      *) echo /fake/agent-works/.git ;;
    esac ;;
  for-each-ref) cat "$FIX/refs" 2>/dev/null || true ;;
  ls-tree) cat "$FIX/tree" ;;
  merge-base) [ "$3" = "$MERGED_SHA" ] ;;
  status) cat "$FIX/dirty-$wt" 2>/dev/null || true ;;
  show-ref) grep -qxF -- "$4" "$FIX/kept-branches" 2>/dev/null || exit 1 ;;
  *) echo "unexpected git call: $*" >&2; exit 1 ;;
esac
STUB

# Fake orca-ide: `worktree list` prints $FIX/worktrees.json (or, with $FIX/unregistered,
# Orca's repo_not_found error). `worktree rm --worktree path:<p>` drops that row
# ($FIX/rm-fail-<name>: exits 1 not ok; $FIX/rm-stays-<name>: reports ok, row
# kept; $FIX/rm-dirties-<name>: names a worktree that gets uncommitted changes). `terminal list` prints $FIX/terminals.json (default: none). Anything
# else is recorded and fails.
cat > "$work/orca-ide" <<'STUB'
#!/usr/bin/env bash
echo "orca-ide $*" >> "$LOG"
case "$1 $2" in
  "worktree list")
    [ -f "$FIX/unregistered" ] && { echo '{"ok":false,"error":{"code":"repo_not_found","message":"repo_not_found"}}'; exit 1; }
    cat "$FIX/worktrees.json" ;;
  "worktree rm")
    p=${4#path:}; n=${p##*/}
    [ ! -f "$FIX/rm-dirties-$n" ] || echo " M file" > "$FIX/dirty-$(cat "$FIX/rm-dirties-$n")"
    [ ! -f "$FIX/rm-fail-$n" ] || { echo '{"ok":false,"error":{"code":"worktree_remove_failed","message":"fatal: worktree is locked"}}'; exit 1; }
    [ -f "$FIX/rm-stays-$n" ] || python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["result"]["worktrees"] = [w for w in d["result"]["worktrees"] if w["path"] != sys.argv[2]]
json.dump(d, open(sys.argv[1], "w"))
' "$FIX/worktrees.json" "$p"
    echo '{"ok":true,"result":{}}' ;;
  "terminal list") cat "$FIX/terminals.json" 2>/dev/null || echo '{"ok":true,"result":{"terminals":[],"truncated":false}}' ;;
  *) echo "unexpected orca-ide call: $*" >&2; exit 1 ;;
esac
STUB

# loop-prompt.sh wrapper: records the keys, then runs the real helper (PROMPT_FAIL=1: refuses).
cat > "$work/loop-prompt.sh" <<STUB
#!/usr/bin/env bash
echo "prompt \$*" >> "\$LOG"
[ "\${PROMPT_FAIL:-0}" = 1 ] && { echo "loop-prompt: unfilled launch-time placeholder <x>" >&2; exit 1; }
exec bash "$here/loop-prompt.sh" "\$@"
STUB

# Fake loop-launch.sh (LAUNCH_FAIL=1: exits 4 as after a failed resend).
cat > "$work/loop-launch.sh" <<'STUB'
#!/usr/bin/env bash
echo "launch $*" >> "$LOG"
[ "${LAUNCH_FAIL:-0}" = 1 ] && { echo "loop-launch: resend did not reach turn_started; handle=term_stub" >&2; exit 4; }
echo "handle=term_stub stage=screen_activity"
STUB
chmod +x "$work/gh" "$work/git" "$work/orca-ide"

# pr <number> <title> <state> [refs-issue] [head-branch]: one PR object.
pr() {
  local merged=null commit=null body="Summary"
  [ "$3" != MERGED ] || { merged="\"2026-10-0$(( $1 % 9 + 1 ))T10:00:00Z\""; commit="{\"oid\":\"$SPEC_SHA\"}"; }
  [ -z "${4:-}" ] || body="Summary\\n\\nRefs #$4"
  printf '{"number":%s,"title":"%s","state":"%s","mergedAt":%s,"mergeCommit":%s,"headRefName":"%s","body":"%s"}' \
    "$1" "$2" "$3" "$merged" "$commit" "${5:-jolbax/x}" "$body"
}
# wt <name> <status> [comment] [activity]: one Orca worktree row.
wt() { printf '{"path":"/fake/ws/%s","isMainWorktree":false,"workspaceStatus":"%s","comment":"%s","lastActivityAt":%s}' "$1" "$2" "${3:-}" "${4:-0}"; }
join() { local IFS=,; echo "[$*]"; }

# fresh: new fixtures with one GitHub repo, the main worktree and no branches.
fresh() {
  rm -rf "$FIX"; mkdir -p "$FIX"; : > "$LOG"
  echo '{"nameWithOwner":"acme/widgets","defaultBranchRef":{"name":"main"}}' > "$FIX/repo.json"
  echo '[]' > "$FIX/prs.json"; echo '[]' > "$FIX/open.json"
  worktrees
}
# worktrees [row...]: the Orca worktree list (the main worktree is always present).
worktrees() {
  local main='{"path":"/fake/agent-works","isMainWorktree":true,"workspaceStatus":"in-progress","comment":"","lastActivityAt":0}'
  printf '{"ok":true,"result":{"worktrees":%s,"truncated":false}}' "$(join "$main" "$@")" > "$FIX/worktrees.json"
}
prs() { join "$@" > "$FIX/prs.json"; }

fail=0 out="" rc=0
# run <args...>: run the launcher against the stubs; sets $out and $rc.
run() {
  rc=0
  out=$(LOG=$LOG FIX=$FIX MERGED_SHA=$MERGED_SHA GH=$work/gh GIT=$work/git ORCA_IDE=$work/orca-ide \
        LOOP_PROMPT=$work/loop-prompt.sh LOOP_LAUNCH=$work/loop-launch.sh TMPDIR=$work \
        bash "$HELPER" "$@" 2>&1) || rc=$?
}
# check <scenario> <want-exit> [has:<text>|not:<text>|next:<a>=><b>|log:<text>|nolog:<text>|lines:<n> ...]
#   has/not search the output, next: the line after the first output line with <a>
#   contains <b>, log/nolog search the call log; lines: number of log lines.
check() {
  local name=$1 want=$2 ok=1 a; shift 2
  [ "$rc" = "$want" ] || ok=0
  for a in "$@"; do
    case "$a" in
      has:*) grep -qF -- "${a#has:}" <<<"$out" || ok=0 ;;
      not:*) ! grep -qF -- "${a#not:}" <<<"$out" || ok=0 ;;
      next:*) x=${a#next:}; grep -m1 -A1 -F -- "${x%%=>*}" <<<"$out" | sed -n 2p | grep -qF -- "${x#*=>}" || ok=0 ;;
      log:*) grep -qF -- "${a#log:}" "$LOG" || ok=0 ;;
      nolog:*) ! grep -qF -- "${a#nolog:}" "$LOG" || ok=0 ;;
      lines:*) [ "$(wc -l < "$LOG")" = "${a#lines:}" ] || ok=0 ;;
    esac
    [ "$ok" = 1 ] || { echo "FAIL $name: exit $rc (want $want), failed on '$a'; output:"; sed 's/^/    /' <<<"$out"; echo "  log:"; sed 's/^/    /' "$LOG"; fail=1; return 0; }
  done
  echo "PASS $name (exit $rc)"
}

# --- Launcher derives launch-time values from GitHub ---
fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)" "$(pr 23 "spec: add-foo-bar" MERGED 32)"
run implement add-foo
check "implement derives the spec PR" 0 log:"git fetch origin" \
  log:"change-name=add-foo issue-number=31 spec-pr-number=22 spec-merge-commit=$SPEC_SHA default-branch=main" \
  log:"launch add-foo-impl claude $work/loop-start-add-foo-impl." log:"--base-branch origin/main --issue 31"
check "output after launch" 0 has:"worker: add-foo-impl" has:"terminal: term_stub" has:"next: " has:"approve <sha>' and 'fix' in the worker's own terminal"

fresh; prs "$(pr 40 "impl: add-foo" MERGED 31)"
run archive add-foo
check "archive derives the implementation PR" 0 log:"owner=acme repo=widgets change-name=add-foo issue-number=31 impl-pr-number=40" \
  log:"launch add-foo-archive claude" log:"--base-branch origin/main --issue 31"

fresh; pr 40 "impl: add-foo" OPEN 31 jolbax/add-foo-impl > "$FIX/pr-40.json"
run judge 40
check "judge derives the change from the PR" 0 log:"change-name=add-foo pr-number=40" \
  log:"launch add-foo-judge codex" log:"--base-branch origin/jolbax/add-foo-impl --issue 31" nolog:"gh pr list"

fresh; prs "$(pr 20 "spec: add-foo" MERGED 30)" "$(pr 22 "spec: add-foo" MERGED 31)" "$(pr 24 "spec: add-foo" CLOSED 31)" "$(pr 25 "spec: add-foo-x" MERGED 9)"
run implement add-foo
check "several PRs match a title" 0 log:"spec-pr-number=22" has:"#20 (MERGED)" has:"#24 (CLOSED)" not:"#25"

fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
PROMPT_FAIL=1 run implement add-foo
check "prompt builder refuses" 1 has:"loop-prompt.sh refused" log:"prompt " nolog:"launch "
unset PROMPT_FAIL

# --- Launcher uses the documented worker layout ---
fresh
run start add-foo --brief "add a foo"
check "start with a brief" 0 log:"brief=add a foo" log:"launch add-foo claude" log:"--base-branch origin/main" nolog:"--issue" nolog:"gh issue view"

fresh; echo '{"state":"OPEN","url":"https://github.com/acme/widgets/issues/31"}' > "$FIX/issue-31.json"
run start add-foo --issue 31
check "start from an issue" 0 log:"issue-number=31" log:"launch add-foo claude" log:"--base-branch origin/main --issue 31" nolog:"brief="

fresh; worktrees "$(wt add-foo-judge completed)" "$(wt add-foo-judge-2 completed)"
pr 40 "impl: add-foo" OPEN 31 jolbax/add-foo-impl > "$FIX/pr-40.json"
run judge 40
check "next free judge number" 0 log:"launch add-foo-judge-3 codex"

fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
LAUNCH_FAIL=1 run implement add-foo
check "launch fails after the worktree exists" 1 has:"loop-launch.sh exited 4" has:"Not retried, not removed" has:"orca-ide terminal read" \
  nolog:"orca-ide worktree rm" nolog:"orca-ide worktree remove" nolog:"orca-ide terminal"
[ "$(grep -c '^launch ' "$LOG")" = 1 ] || { echo "FAIL launch fails after the worktree exists: launched more than once"; fail=1; }
unset LAUNCH_FAIL

# --- Launcher refuses what it cannot derive ---
fresh; prs "$(pr 22 "spec: add-foo" OPEN 31)"
run implement add-foo
check "implement before the spec merged (open)" 3 has:"'spec: add-foo'" has:"#22 (OPEN)" nolog:"prompt " nolog:"launch "
fresh
run implement add-foo
check "implement before the spec merged (none)" 3 has:"'spec: add-foo'" nolog:"launch "

for case in CLOSED MERGED missing title; do
  fresh
  case $case in
    missing) ;;
    title) pr 40 "spec: add-foo" OPEN 31 > "$FIX/pr-40.json" ;;
    *) pr 40 "impl: add-foo" "$case" 31 > "$FIX/pr-40.json" ;;
  esac
  run judge 40
  check "judge on a PR that is not an open implementation PR ($case)" 4 nolog:"prompt " nolog:"launch "
done

for case in OPEN CLOSED absent; do
  fresh; [ "$case" = absent ] || prs "$(pr 40 "impl: add-foo" "$case" 31)"
  run archive add-foo
  check "archive before the implementation merged ($case)" 5 nolog:"launch "
done

fresh; prs "$(pr 22 "spec: add-foo" MERGED)"
run implement add-foo
check "merged PR without an issue reference (implement)" 3 has:"Refs" nolog:"launch "
fresh; prs "$(pr 40 "impl: add-foo" MERGED)"
run archive add-foo
check "merged PR without an issue reference (archive)" 5 has:"Refs" nolog:"launch "

for case in worktree local origin-prefixed; do
  fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
  case $case in
    worktree) worktrees "$(wt add-foo-impl completed)" ;;
    local) echo refs/heads/add-foo-impl > "$FIX/refs" ;;
    origin-prefixed) echo refs/remotes/origin/jolbax/add-foo-impl > "$FIX/refs" ;;
  esac
  run implement add-foo
  check "name already taken ($case)" 6 has:"add-foo-impl" nolog:"prompt " nolog:"launch "
done
fresh; echo refs/heads/jolbax/add-foo-impl-old > "$FIX/refs"; prs "$(pr 22 "spec: add-foo" MERGED 31)"
run implement add-foo
check "similar branch name is not taken" 0 log:"launch add-foo-impl"

fresh
run start add-foo --issue 31
check "issue not usable (missing)" 7 nolog:"launch "
fresh; echo '{"state":"CLOSED","url":"https://github.com/acme/widgets/issues/31"}' > "$FIX/issue-31.json"
run start add-foo --issue 31
check "issue not usable (closed)" 7 nolog:"launch "
fresh; echo '{"state":"OPEN","url":"https://github.com/acme/widgets/pull/31"}' > "$FIX/issue-31.json"
run start add-foo --issue 31
check "issue not usable (a pull request)" 7 nolog:"launch "

usage_cases=(
  "" "frobnicate add-foo" "start" "start add-foo" "start add-foo --brief x --issue 3"
  "start add-foo --issue x" "implement" "implement Add_Foo" "archive add-foo extra" "judge abc" "status extra"
  "cleanup --force" "cleanup extra" "cleanup --dry-run extra" "--dry-run cleanup --dry-run" "--dry-run status"
)
for args in "${usage_cases[@]}"; do
  fresh; : > "$LOG"
  # shellcheck disable=SC2086
  run $args
  check "usage error: '${args}'" 2 lines:0
done

fresh; rm "$FIX/repo.json"
run implement add-foo
check "gh call fails" 1 has:"gh repo view failed" nolog:"launch "

fresh; touch "$FIX/unregistered"; prs "$(pr 22 "spec: add-foo" MERGED 31)"
run implement add-foo
check "checkout not registered in Orca (launch)" 1 \
  has:"loop-start: this checkout (/fake/agent-works) is not a repository registered in Orca; run from an Orca worktree of the repository" nolog:"prompt " nolog:"launch "
fresh; touch "$FIX/unregistered"
run status
check "checkout not registered in Orca (status)" 1 has:"is not a repository registered in Orca" nolog:"gh pr"

# --- Launcher dry run launches nothing ---
fresh; prs "$(pr 22 "spec: add-foo" MERGED 31)"
run --dry-run implement add-foo
promptfile=$(sed -n 's/^prompt: //p' <<<"$out")
check "dry run of implement" 0 has:"prompt: $work/" has:"launch (dry run, not run): bash scripts/loop-launch.sh add-foo-impl claude" \
  has:"--base-branch origin/main --issue 31" log:"prompt " nolog:"launch "
if [ -z "$promptfile" ] || [ ! -s "$promptfile" ] || grep -qE '<[a-z][a-z0-9-]*>' "$promptfile"; then
  echo "FAIL dry run of implement: prompt file missing, empty or with a <name> token: $promptfile"; fail=1
else
  echo "PASS dry run prompt has no <name> token"
fi
fresh
run --dry-run implement add-foo
check "dry run still refuses" 3 nolog:"prompt "

# --- Status names where the operator acts ---
fresh
worktrees "$(wt add-foo in-review "PR #14 at a1b2c3d: review, then type: approve a1b2c3d" 5)" \
  "$(wt add-bar-impl in-progress "implement: add-bar" 4)" "$(wt add-baz-impl completed "merged 1234567" 3)" \
  "$(wt add-qux-judge in-progress "" 2)"
join '{"number":14,"title":"spec: add-foo","headRefName":"jolbax/add-foo"}' \
     '{"number":40,"title":"impl: add-bar","headRefName":"jolbax/add-bar-impl"}' \
     '{"number":41,"title":"impl: add-old","headRefName":"jolbax/add-old-impl"}' \
     '{"number":42,"title":"impl: add-pass","headRefName":"jolbax/add-pass-impl"}' \
     '{"number":43,"title":"impl: add-qux","headRefName":"jolbax/add-qux-impl"}' \
     '{"number":50,"title":"chore: unrelated","headRefName":"jolbax/x"}' > "$FIX/open.json"
check_ok='[{"__typename":"CheckRun","name":"openspec","status":"COMPLETED","conclusion":"SUCCESS"}]'
view() { printf '{"headRefOid":"%s","statusCheckRollup":%s,"comments":%s}' "$HEAD_SHA" "$2" "$3" > "$FIX/view-$1.json"; }
view 14 "$check_ok" '[]'
view 40 '[]' '[]'
view 41 "$check_ok" '[{"createdAt":"2026-10-20T10:00:00Z","body":"Verdict: PASS at 0000000"}]'
view 42 "$check_ok" '[{"createdAt":"2026-10-20T10:00:00Z","body":"Verdict: PASS at a1b2c3d\n\ndetails"}]'
view 43 "$check_ok" '[]'
run status
check "worker waits for the operator" 0 has:"-> ACT: type approve a1b2c3d in the terminal of add-foo" \
  has:"add-bar-impl  [in-progress]" not:"add-baz-impl" has:"1 completed not listed" not:"agent-works  [" has:"approve <sha>' and 'fix'"
check "implementation PR without a verdict at its head" 0 has:"ACT: judge it with /sdd-loop judge 40" has:"ACT: judge it with /sdd-loop judge 41" \
  not:"judge 42" not:"judge 14" not:"#50" has:"openspec: missing" has:"not at head a1b2c3d"
check "judge in progress is not suggested again" 0 not:"judge 43 " has:"judge add-qux-judge in progress"
fresh
worktrees "$(wt add-j-impl in-review "PR #44 at a1b2c3d: ready for the judge (launch it, then wait for its verdict)" 3)" \
  "$(wt add-v-impl in-review "Verdict: BLOCKING (2 findings) at a1b2c3d; type: fix" 2)" \
  "$(wt add-p-impl in-review "Verdict: PASS at a1b2c3d; type: approve a1b2c3d" 1)"
run status
check "comment: ready for the judge" 0 has:"-> ACT: judge it with /sdd-loop judge 44 (bash scripts/loop-start.sh judge 44)" not:"ACT in the terminal of add-j-impl"
check "comment: verdict BLOCKING, type: fix" 0 has:"-> ACT in the terminal of add-v-impl: Verdict: BLOCKING (2 findings) at a1b2c3d; type: fix"
check "comment: verdict PASS, type: approve" 0 has:"-> ACT in the terminal of add-p-impl: Verdict: PASS at a1b2c3d; type: approve a1b2c3d"

# Spec or archive PR awaiting approval: the PR line and the worktree line give the same action.
# approval_case <scenario> <statusCheckRollup> <comment-sha> <want...>
approval_case() {
  local scenario=$1 rollup=$2 sha=$3; shift 3
  fresh
  worktrees "$(wt add-foo in-review "PR #14 at $sha: review, then type: approve $sha" 2)" \
    "$(wt add-zap-archive in-review "PR #15 at $sha: review, then type: approve $sha" 1)"
  join '{"number":14,"title":"spec: add-foo","headRefName":"jolbax/add-foo"}' \
       '{"number":15,"title":"archive: add-zap","headRefName":"jolbax/add-zap-archive"}' > "$FIX/open.json"
  view 14 "$rollup" '[]'; view 15 "$rollup" '[]'
  run status
  check "$scenario" 0 "$@"
}
approval_case "spec or archive PR awaiting approval, CI green" "$check_ok" a1b2c3d \
  next:"#14 spec: add-foo  head a1b2c3d  openspec: SUCCESS  verdict: none=>-> ACT: type approve a1b2c3d in the terminal of add-foo" \
  next:"#15 archive: add-zap  head a1b2c3d  openspec: SUCCESS  verdict: none=>-> ACT: type approve a1b2c3d in the terminal of add-zap-archive" \
  next:"  add-foo  [in-review]  PR #14 at a1b2c3d: review, then type: approve a1b2c3d=>-> ACT: type approve a1b2c3d in the terminal of add-foo" not:"no action" not:"wait for CI"
for ci in missing pending failed; do
  case $ci in
    missing) rollup='[]' state=missing ;;
    pending) rollup='[{"__typename":"CheckRun","name":"openspec","status":"IN_PROGRESS","conclusion":""}]' state=IN_PROGRESS ;;
    failed) rollup='[{"__typename":"CheckRun","name":"openspec","status":"COMPLETED","conclusion":"FAILURE"}]' state=FAILURE ;;
  esac
  approval_case "spec or archive PR awaiting approval, CI not green ($ci)" "$rollup" a1b2c3d \
    next:"  #14 spec: add-foo  head a1b2c3d  openspec: $state  verdict: none=>-> ACT: wait for CI (openspec: $state on a1b2c3d), then type approve a1b2c3d in the terminal of add-foo" \
    next:"  add-foo  [in-review]  PR #14 at a1b2c3d: review, then type: approve a1b2c3d=>-> ACT: wait for CI (openspec: $state on a1b2c3d), then type approve a1b2c3d in the terminal of add-foo" \
    has:"-> ACT: wait for CI (openspec: $state on a1b2c3d), then type approve a1b2c3d in the terminal of add-zap-archive" \
    not:"-> ACT: type approve" not:"no action"
done
approval_case "announced head is not the PR head" "$check_ok" 0badbad \
  next:"#14 spec: add-foo  head a1b2c3d  openspec: SUCCESS  verdict: none=>-> no action" next:"#15 archive: add-zap  head a1b2c3d  openspec: SUCCESS  verdict: none=>-> no action" not:"ACT: type approve" not:"wait for CI"

bad=$(grep -vE '^(orca-ide worktree list |gh pr list --state open |gh pr view [0-9]+ --json headRefOid,statusCheckRollup,comments$|git rev-parse )' "$LOG" || true)
if [ -z "$bad" ]; then echo "PASS status is read only"; else echo "FAIL status is read only: unexpected calls:"; sed 's/^/    /' <<<"$bad"; fail=1; fi

# --- Cleanup removes only finished loop worktrees ---
# cw <name> [status] [linked-pr]: one Orca worktree row with branch jolbax/<name>
# (status "null": no status).
cw() {
  local st=${2:-completed}
  [ "$st" = null ] || st="\"$st\""
  printf '{"path":"/fake/ws/%s","branch":"refs/heads/jolbax/%s","isMainWorktree":false,"workspaceStatus":%s,"comment":"","linkedPR":%s,"lastActivityAt":0}' \
    "$1" "$1" "$st" "${3:-null}"
}
# changes <dir...>: change directories on origin/main (ls-tree output).
changes() {
  local d
  : > "$FIX/tree"
  printf '100644 blob %s\topenspec/changes/archive/.gitkeep\n' "$SPEC_SHA" >> "$FIX/tree"
  for d in "$@"; do printf '040000 tree %s\topenspec/changes/%s\n' "$SPEC_SHA" "$d" >> "$FIX/tree"; done
}
# cfresh [row...]: fixtures for cleanup with change add-foo (archived) and add-bar (active).
cfresh() { fresh; changes archive archive/2026-10-22-add-foo add-bar; worktrees "$@"; }
pr_state() { printf '{"state":"%s"}' "$2" > "$FIX/pr-$1.json"; }
# only reads may be logged by a dry run
readonly_log() {
  grep -vE '^(git fetch origin$|gh repo view |orca-ide worktree list |git rev-parse |git ls-tree |git -C /fake/ws/[^ ]+ (rev-parse HEAD|status --porcelain)|git merge-base --is-ancestor |gh pr view [0-9]+ --json state$)' "$LOG" || true
}

cfresh "$(cw add-foo-judge-2)"
run cleanup --dry-run
check "finished worker passes every rule" 0 has:"add-foo-judge-2  remove" has:"agent-works  keep: main worktree" has:"1 to remove, 1 kept"

cfresh "$(cw add-foo-impl)"; echo /fake/ws/add-foo-impl > "$FIX/toplevel"
run cleanup --dry-run
check "rule: current worktree" 0 has:"add-foo-impl  keep: current worktree" has:"0 to remove, 2 kept"
for st in in-progress in-review todo null; do
  cfresh "$(cw add-foo-impl "$st")"
  run cleanup --dry-run
  want=$st; [ "$st" != null ] || want=none
  check "rule: status $want" 0 has:"add-foo-impl  keep: status $want, not completed" has:"0 to remove"
done
cfresh "$(cw jlb-ideation-phase)" "$(cw add-foo-notes)"
run cleanup --dry-run
check "rule: not a loop worker name" 0 has:"jlb-ideation-phase  keep: not a loop worker name" has:"add-foo-notes  keep: not a loop worker name" \
  has:"0 to remove, 3 kept" nolog:"git -C"
cfresh "$(cw add-foo-impl)"; echo 0123456789abcdef0123456789abcdef01234567 > "$FIX/head-add-foo-impl"
run cleanup --dry-run
check "rule: HEAD not merged" 0 has:"add-foo-impl  keep: HEAD 0123456 not merged into origin/main" nolog:"gh pr view" nolog:"status --porcelain"
cfresh "$(cw add-foo-impl completed 20)" "$(cw add-foo completed 19)" "$(cw add-foo-archive completed 21)"
pr_state 20 OPEN; pr_state 19 MERGED; pr_state 21 CLOSED
run cleanup --dry-run
check "rule: linked PR open" 0 has:"add-foo-impl  keep: linked PR #20 is OPEN" has:"add-foo  remove" has:"add-foo-archive  remove" \
  log:"gh pr view 20 --json state" nolog:"git -C /fake/ws/add-foo-impl status"
for kind in uncommitted untracked; do
  cfresh "$(cw add-foo-impl)"
  if [ "$kind" = uncommitted ]; then echo " M scripts/x.sh" > "$FIX/dirty-add-foo-impl"; else echo "?? notes.txt" > "$FIX/dirty-add-foo-impl"; fi
  run cleanup --dry-run
  check "rule: $kind files" 0 has:"add-foo-impl  keep: uncommitted changes" has:"0 to remove" log:"git -C /fake/ws/add-foo-impl status --porcelain"
done
cfresh "$(cw add-foo-impl in-progress 20)"; echo "?? x" > "$FIX/dirty-add-foo-impl"; pr_state 20 OPEN
echo 0123456789abcdef0123456789abcdef01234567 > "$FIX/head-add-foo-impl"
run cleanup --dry-run
check "first failing rule is the reason" 0 has:"add-foo-impl  keep: status in-progress, not completed" not:"HEAD 0123456" not:"uncommitted" nolog:"git -C"
cfresh "$(cw add-bar)" "$(cw add-bar-impl)" "$(cw add-bar-judge)" "$(cw add-bar-judge-3)" "$(cw add-bar-archive)" "$(cw add-foo-judge-2)" \
  "$(cw add-bar-judge-1)" "$(cw add-bar-judge-x)" "$(cw add-bar-notes)" "$(cw add-baz-impl)" "$(cw archive)" "$(cw jlb-ideation-phase)"
run cleanup --dry-run
check "loop worker names" 0 has:"add-bar  remove" has:"add-bar-impl  remove" has:"add-bar-judge  remove" has:"add-bar-judge-3  remove" \
  has:"add-bar-archive  remove" has:"add-foo-judge-2  remove" has:"add-bar-judge-1  keep: not a loop worker name" \
  has:"add-bar-judge-x  keep: not a loop worker name" has:"add-bar-notes  keep: not a loop worker name" \
  has:"add-baz-impl  keep: not a loop worker name" has:"archive  keep: not a loop worker name" \
  has:"jlb-ideation-phase  keep: not a loop worker name" has:"6 to remove, 7 kept"

for case in fetch repo orca ls-tree pr head; do
  cfresh "$(cw add-foo-impl completed 20)" "$(cw add-foo-judge)"; pr_state 20 MERGED
  case $case in
    fetch) touch "$FIX/fetch-fail" ;;
    repo) rm "$FIX/repo.json" ;;
    orca) touch "$FIX/unregistered" ;;
    ls-tree) rm "$FIX/tree" ;;
    pr) rm "$FIX/pr-20.json" ;;
    head) echo fail > "$FIX/head-add-foo-judge" ;;
  esac
  run cleanup
  check "fetch or lookup fails ($case)" 1 has:"loop-start: " not:"removed " nolog:"worktree rm"
done

# --- Cleanup dry run removes nothing ---
for form in "cleanup --dry-run" "--dry-run cleanup"; do
  cfresh "$(cw add-foo-impl)" "$(cw add-bar-judge in-review)"
  # shellcheck disable=SC2086
  run $form
  check "dry-run listing ($form)" 0 has:"agent-works  keep: main worktree" has:"add-foo-impl  remove" \
    has:"add-bar-judge  keep: status in-review, not completed" has:"1 to remove, 2 kept" has:"dry run: nothing removed" not:"removed "
  bad=$(readonly_log)
  if [ -z "$bad" ]; then echo "PASS nothing changed ($form)"; else echo "FAIL nothing changed ($form): unexpected calls:"; sed 's/^/    /' <<<"$bad"; fail=1; fi
done

# --- Cleanup removes without force and reports what remains ---
cfresh "$(cw add-foo-judge-2)" "$(cw add-bar-impl in-progress)"
run cleanup
check "finished worker removed" 0 has:"add-foo-judge-2  remove" \
  has:"removed add-foo-judge-2: branch jolbax/add-foo-judge-2 deleted; terminals: none" has:"cleanup: 1 removed (add-foo-judge-2)" \
  log:"orca-ide worktree rm --worktree path:/fake/ws/add-foo-judge-2 --json" nolog:"--force" nolog:"git push" nolog:"git branch" \
  nolog:"worktree rm --worktree path:/fake/ws/add-bar-impl" log:"git show-ref --verify --quiet refs/heads/jolbax/add-foo-judge-2" \
  log:"orca-ide terminal list --json"
cfresh "$(cw add-foo-impl)" "$(cw add-foo-archive)"
echo refs/heads/jolbax/add-foo-impl > "$FIX/kept-branches"
printf '{"ok":true,"result":{"terminals":[%s,%s,%s],"truncated":false}}' \
  '{"handle":"term_a","worktreePath":"/fake/ws/add-foo-impl"}' '{"handle":"term_b","worktreePath":"/fake/ws/add-foo-impl"}' \
  '{"handle":"term_c","worktreePath":"/fake/agent-works"}' > "$FIX/terminals.json"
run cleanup
check "branch kept and terminal left behind" 0 has:"removed add-foo-impl: branch jolbax/add-foo-impl kept; terminals: term_a, term_b" \
  has:"removed add-foo-archive: branch jolbax/add-foo-archive deleted; terminals: none" has:"cleanup: 2 removed (add-foo-impl add-foo-archive)" not:"term_c"
cfresh "$(cw add-foo-impl)" "$(cw add-foo-archive)"; echo add-foo-archive > "$FIX/rm-dirties-add-foo-impl"
run cleanup
check "rules evaluated again before each removal" 0 has:"add-foo-archive  remove" has:"removed add-foo-impl:" \
  has:"add-foo-archive  keep: uncommitted changes (changed since the list)" nolog:"worktree rm --worktree path:/fake/ws/add-foo-archive"

# --- Cleanup stops at the first failed removal ---
for case in fail stays; do
  cfresh "$(cw add-foo)" "$(cw add-foo-impl)" "$(cw add-foo-archive)"
  touch "$FIX/rm-$case-add-foo-impl"
  run cleanup
  if [ "$case" = fail ]; then scenario="second removal fails" why="exited 1: fatal: worktree is locked"
  else scenario="removal reported but still listed" why="still listed by orca-ide worktree list after removal"; fi
  check "$scenario" 8 has:"removed add-foo:" has:"cleanup: removal of add-foo-impl failed: " has:"$why" \
    has:"; 1 removed (add-foo), not attempted: add-foo-archive" not:"removed add-foo-archive" \
    log:"worktree rm --worktree path:/fake/ws/add-foo-impl --json" nolog:"worktree rm --worktree path:/fake/ws/add-foo-archive"
done

[ "$fail" = 0 ] && echo "test-loop-start: all scenarios passed (simulation)" || { echo "test-loop-start: FAILED" >&2; exit 1; }
