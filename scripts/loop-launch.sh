#!/usr/bin/env bash
# Launch helper for the spec-driven loop: starts an Orca worker from a prompt
# file and confirms the prompt arrived, so a silently dropped launch prompt does
# not leave an idle worker.
#
#   bash scripts/loop-launch.sh <name> <agent> <prompt-file> [extra worktree-create args]
#
# 1. `worktree create --json`; the terminal handle is result.launch.outcome.handle.
# 2. Poll `terminal read --screen --json` until the agent shows activity (Claude
#    Code: a line starting "● "; Codex: a line starting "• Working") or the wait ends.
# 3. If no activity, resend the prompt ONCE with `terminal send --enter
#    --wait-submit` and require stage `turn_started`. No third attempt.
#
# Exit codes: 0 confirmed; 1 launch/read/send failed or result uninterpretable;
# 2 usage; 3 no terminal handle; 4 second attempt did not reach turn_started.
#
# Environment (all optional):
#   ORCA_IDE                 orca-ide command (default: orca-ide); tests point it at a stub
#   LOOP_LAUNCH_WAIT         seconds to wait for first activity (default 60)
#   LOOP_LAUNCH_POLL         seconds between screen reads (default 5)
#   LOOP_LAUNCH_SUBMIT_WAIT  --wait-submit seconds for the resend (default 20)
set -euo pipefail

[ "$#" -ge 3 ] || { echo "usage: loop-launch.sh <name> <agent> <prompt-file> [extra worktree-create args]" >&2; exit 2; }
name=$1 agent=$2 promptfile=$3
shift 3
[ -r "$promptfile" ] || { echo "loop-launch: cannot read prompt file: $promptfile" >&2; exit 2; }

ORCA=${ORCA_IDE:-orca-ide}
WAIT=${LOOP_LAUNCH_WAIT:-60}
POLL=${LOOP_LAUNCH_POLL:-5}
SUBMIT_WAIT=${LOOP_LAUNCH_SUBMIT_WAIT:-20}
prompt=$(cat "$promptfile")

# json_get <python-expr on d>: print a value from JSON on stdin; non-zero if unparsable.
json_get() { python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }

create=$("$ORCA" worktree create --name "$name" --agent "$agent" --prompt "$prompt" "$@" --json) || {
  echo "loop-launch: worktree create failed; if the error names an operationId, re-issue the same command with --retry-launch <operationId> and do not launch fresh" >&2
  exit 1
}
handle=$(json_get 'd["result"]["launch"]["outcome"].get("handle") or ""' <<<"$create") || {
  echo "loop-launch: cannot parse worktree create result; sent nothing further" >&2
  exit 1
}
if [ -z "$handle" ]; then
  echo "loop-launch: launch result has no terminal handle (not a terminal launch); sent nothing" >&2
  exit 3
fi

deadline=$((SECONDS + WAIT))
while :; do
  screen=$("$ORCA" terminal read --terminal "$handle" --screen --json) || {
    echo "loop-launch: terminal read failed for $handle; sent nothing further" >&2
    exit 1
  }
  state=$(python3 -I -c '
import json, sys
d = json.load(sys.stdin)
tail = d["result"]["terminal"]["tail"]
if not isinstance(tail, list) or not all(isinstance(l, str) for l in tail):
    sys.exit("tail is not a list of strings")
print("working" if any(l.startswith(("● ", "• Working")) for l in tail) else "idle")
' <<<"$screen") || {
    echo "loop-launch: cannot parse terminal read result for $handle; sent nothing further" >&2
    exit 1
  }
  if [ "$state" = working ]; then
    echo "handle=$handle stage=screen_activity"
    exit 0
  fi
  [ "$SECONDS" -lt "$deadline" ] || break
  sleep "$POLL"
done

echo "loop-launch: no agent activity on $handle after ${WAIT}s; resending the prompt once (it may arrive twice if the first was only slow)" >&2
send=$("$ORCA" terminal send --terminal "$handle" --text "$prompt" --enter --wait-submit "$SUBMIT_WAIT" --json) || {
  echo "loop-launch: terminal send failed on $handle; outcome unknown, not resending a new payload." >&2
  echo "loop-launch: inspect the terminal, or re-issue the exact send command with the --retry-request ID from the error." >&2
  exit 1
}
ok=$(python3 -I -c '
import json, sys
send = json.load(sys.stdin)["result"]["send"]
stages = send["prompt"]["stages"]
if not isinstance(stages, list) or not all(isinstance(x, str) for x in stages) or not isinstance(send["accepted"], bool):
    sys.exit("send result has unexpected types")
print("yes" if send["accepted"] and "turn_started" in stages else "no")
' <<<"$send") || {
  echo "loop-launch: cannot parse terminal send result for $handle; not resending" >&2
  exit 1
}
if [ "$ok" != yes ]; then
  echo "loop-launch: resend did not reach turn_started; handle=$handle" >&2
  exit 4
fi
echo "handle=$handle stage=turn_started (resent once)"
