#!/usr/bin/env bash
# Prompt helper for the spec-driven loop: builds a launch prompt from a template
# in .agents/loop/, so nobody fills placeholders by hand.
#
#   bash scripts/loop-prompt.sh <template> <out> key=value...
#
# Writes to <out> the template text after its first line that is exactly `---`,
# with each launch-time placeholder `<key>` replaced literally by its value (one
# pass; a value is never re-read for placeholders). Runtime placeholders
# `{name}` are values the worker resolves while running and are never replaced.
# Intake: when the body has "Intake:" lines, exactly one of `issue-number` and
# `brief` must be given; the "Intake: issue" or "Intake: brief" line that does
# not apply is dropped.
#
# Exit codes: 0 written; 1 a launch-time placeholder `<[a-z][a-z0-9-]*>` was not
# given (each is named on stderr, <out> is not written); 2 usage, unreadable
# template, no `---` line, or neither or both Intake keys.
set -euo pipefail

usage() { echo "usage: loop-prompt.sh <template> <out> key=value..." >&2; exit 2; }
[ "$#" -ge 2 ] || usage
template=$1 out=$2
shift 2
[ -r "$template" ] || { echo "loop-prompt: cannot read template '$template'" >&2; exit 2; }

declare -A vals=()
for kv in "$@"; do
  [[ "$kv" == *=* ]] || usage
  key=${kv%%=*}
  [[ "$key" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "loop-prompt: invalid key '$key' (expected [a-z][a-z0-9-]*)" >&2; exit 2; }
  vals[$key]=${kv#*=}
done

# Body: the lines after the first line that is exactly `---`.
body="" seen=0 intake=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$seen" = 0 ]; then [ "$line" = --- ] && seen=1; continue; fi
  [[ "$line" == Intake:* ]] && intake=1
  body+="$line"$'\n'
done < "$template"
[ "$seen" = 1 ] || { echo "loop-prompt: no '---' line in '$template'" >&2; exit 2; }

if [ "$intake" = 1 ]; then
  has_issue=0 has_brief=0
  [ -z "${vals[issue-number]+x}" ] || has_issue=1
  [ -z "${vals[brief]+x}" ] || has_brief=1
  [ $((has_issue + has_brief)) = 1 ] || { echo "loop-prompt: give exactly one of issue-number and brief for the Intake line" >&2; exit 2; }
  if [ "$has_issue" = 1 ]; then drop="Intake: brief"; else drop="Intake: issue"; fi
  kept=""
  while IFS= read -r line; do
    [[ "$line" == "$drop"* ]] || kept+="$line"$'\n'
  done <<< "${body%$'\n'}"
  body=$kept
fi

# One literal pass: copy text up to each <token>, then its value or, if not
# given, the token itself (and remember it as unfilled).
result="" rest=$body
declare -A unfilled=()
re='<([a-z][a-z0-9-]*)>'
while [[ "$rest" =~ $re ]]; do
  token=${BASH_REMATCH[0]} key=${BASH_REMATCH[1]}
  result+=${rest%%"$token"*}
  rest=${rest#*"$token"}
  if [ -n "${vals[$key]+x}" ]; then
    result+=${vals[$key]}
  else
    result+=$token
    unfilled[$key]=1
  fi
done
result+=$rest

if [ "${#unfilled[@]}" -gt 0 ]; then
  for key in $(printf '%s\n' "${!unfilled[@]}" | sort); do
    echo "loop-prompt: unfilled launch-time placeholder <$key>" >&2
  done
  exit 1
fi
printf '%s' "$result" > "$out"
echo "loop-prompt: wrote $out from $template"
