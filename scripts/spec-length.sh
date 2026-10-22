#!/usr/bin/env bash
# Length check for the spec-driven loop: lists every requirement in a change's
# delta specs whose text is over 500 characters. `openspec validate --strict`
# applies that limit to ADDED requirements only; MODIFIED ones overflow only
# when the archive syncs them into openspec/specs/.
#
#   bash scripts/spec-length.sh <change-dir>
#
# For each <change-dir>/specs/**/spec.md, a requirement's text is the lines
# between its `### Requirement:` heading and its first `####` or next heading,
# each trimmed, blank lines dropped, joined with newlines (as openspec measures
# it, without its code-fence and metadata handling).
#
# Exit codes: 0 every requirement is within the limit; 1 at least one is over
# (each is named on stdout); 2 usage, or no spec.md under <change-dir>/specs.
set -euo pipefail
export LC_ALL=C.UTF-8

usage() { echo "usage: spec-length.sh <change-dir>" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
dir=${1%/}
[ -d "$dir/specs" ] || { echo "spec-length: no specs/ directory in '$dir'" >&2; exit 2; }
# A read loop, not a bash 4 builtin: this script runs on bash 3.2 (macOS) too.
specs=()
while IFS= read -r f; do specs+=("$f"); done < <(find "$dir/specs" -name spec.md -type f | sort)
[ "${#specs[@]}" -gt 0 ] || { echo "spec-length: no spec.md under '$dir/specs'" >&2; exit 2; }

limit=500 over=0 count=0
# check <file> <name> <text>
check() {
  count=$((count + 1))
  local len=${#3}
  if [ "$len" -gt "$limit" ]; then
    echo "spec-length: $1: \"$2\" is $len characters (limit $limit)"
    over=1
  fi
}

for f in "${specs[@]}"; do
  name="" text="" inreq=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == '### Requirement:'* ]]; then
      [ "$inreq" = 0 ] || check "$f" "$name" "$text"
      name=${line#'### Requirement:'} name=${name# } text="" inreq=1
      continue
    fi
    [ "$inreq" = 1 ] || continue
    if [[ "$line" == '#'* ]]; then
      check "$f" "$name" "$text"
      inreq=0
      continue
    fi
    trimmed=${line#"${line%%[![:space:]]*}"}
    trimmed=${trimmed%"${trimmed##*[![:space:]]}"}
    [ -n "$trimmed" ] || continue
    text+=${text:+$'\n'}$trimmed
  done < "$f"
  [ "$inreq" = 0 ] || check "$f" "$name" "$text"
done

if [ "$over" = 1 ]; then
  echo "spec-length: requirements over $limit characters; shorten them (move detail into scenarios)"
  exit 1
fi
echo "spec-length: all $count requirements in $dir are within $limit characters"
