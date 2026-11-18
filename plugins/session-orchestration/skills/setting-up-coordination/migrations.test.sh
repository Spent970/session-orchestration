#!/usr/bin/env bash
# Coverage check for migrations: every migration id the code names (a `[m7]`-style prefix in session-init or lib.sh)
# has a row in migrations.md and a `# migration fixture: m7` line in session-status.test.sh, and every row has a
# valid class. Proves itself first: a copy with a row or a fixture removed must fail.
# Run: bash migrations.test.sh  (prints "ok" or what failed).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
orch=$here/../orchestrating-sessions
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# check CODE_FILES... -- TABLE FIXTURES: prints one problem per line, exit 1 if any.
check() {
  local code=() table fixtures bad=0 id
  while [ "$1" != -- ]; do code+=("$1"); shift; done; table=$2 fixtures=$3
  while read -r id; do
    [ -n "$id" ] || continue
    grep -qE "^\| $id \|" "$table" || { echo "migration $id: no row in migrations.md"; bad=1; }
    grep -qE "^# migration fixture: $id[[:space:]]*\$" "$fixtures" || { echo "migration $id: no fixture"; bad=1; }
  done < <(grep -ohE '\[[mh][0-9]+\] ' "${code[@]}" | tr -d '[] ' | sort -u)
  while IFS='|' read -r _ id _ class _; do
    id=${id// /}
    [[ $id =~ ^[mh][0-9]+$ ]] || continue
    [[ $class =~ ^[[:space:]]*(auto|ask|hand)([^a-z]|$) ]] || { echo "migration $id: class '$class' is not auto, ask or hand"; bad=1; }
  done < <(grep -E '^\| [mh][0-9]+ \|' "$table")
  return $bad
}

code=("$here/session-init" "$here/../../lib.sh")
out=$(check "${code[@]}" -- "$here/migrations.md" "$orch/session-status.test.sh") || { echo "$out"; exit 1; }

# Self-check on a fixture set: ids m1 (covered), m2 (no row), m3 (no fixture).
printf '[m1] a\n[m2] b\n[m3] c\n' > "$tmp/code"
printf '| m1 | x | auto | d | f |\n| m3 | x | ask | d | f |\n' > "$tmp/table"
printf '# migration fixture: m1\n# migration fixture: m2\n' > "$tmp/fix"
out=$(check "$tmp/code" -- "$tmp/table" "$tmp/fix") && { echo "self-check: a missing row and fixture passed"; exit 1; }
[[ $out == *"migration m2: no row"* && $out == *"migration m3: no fixture"* && $out != *"migration m1"* ]] ||
  { echo "self-check: wrong report: $out"; exit 1; }
printf '| m1 | x | maybe | d | f |\n' > "$tmp/table"
out=$(check "$tmp/code" -- "$tmp/table" "$tmp/fix") && { echo "self-check: bad class passed"; exit 1; }
[[ $out == *"maybe"* ]] || { echo "self-check: bad class not named: $out"; exit 1; }
echo ok
