#!/bin/bash
# Tests for standup-summary against a stub claude: the model gets the brief's template and its items (kind, key,
# people, source, text, their task's title and status, a local time); no template, no run; cached per day, a
# session's moving text doesn't rerun it; failures and a hung call exit 1 with the cache untouched.
# Run: bash standup-summary.test.sh  (prints "ok" or the failure).
set -uo pipefail
s=$(cd "$(dirname "$0")" && pwd)/standup-summary
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/claude" <<STUB
#!/bin/bash
echo run >> "$t/runs"; cat > "$t/stdin"; printf '%s\n' "\$*" > "$t/args"
[ -z "\${STUB_FAIL:-}" ] || { echo '{"is_error":true,"result":"rate limited"}'; exit 1; }
[ -z "\${STUB_HANG:-}" ] || exec sleep 30
echo 'warning: an update is available' >&2
echo '{"result":"Yesterday I finished ABC-1."}'
STUB
chmod +x "$t/bin/claude"
export XDG_CACHE_HOME=$t/cache PATH=$t/bin:$PATH TZ=UTC
sum() { bash "$s"; }
runs() { grep -c . "$t/runs"; }
# A brief (session-status --yesterday --json): its day, its session item's text, more items.
brief() { jq -nc --arg day "${1:-2030-01-03}" --arg stext "${2:-session \"a\" (09:00–10:00): working on it}" --argjson more "${3:-[]}" '
  {since: $day, from: 1893628800, how: "last working day", notes: ["Staging is down by design."], failed: [],
   template: "Yesterday I worked on <tasks>, discussed <tasks> with <people>. Today I will work on <tasks>.",
   tasks: {"ABC-1": {status: "In Review", title: "Fix it"}},
   items: ([{kind: "worked", key: "ABC-1", people: [], source: "session", at: 1893664800, text: $stext},
            {kind: "discussed", key: "ABC-1", people: ["Ann Lee"], source: "teams", at: 1893668400, text: "the retry limit"}] + $more)}'; }
out=$(brief | sum) && [ "$out" = "Yesterday I finished ABC-1." ] || { echo "first run: $out"; exit 1; }
# The model gets the template in its prompt; then today's date, the start day, the notes and each item with its
# data fields, its task's title and status and a local time; haiku by default, no tools.
grep -qF 'discussed <tasks> with <people>. Today I will work on <tasks>.' "$t/args" && grep -q -- '--model haiku --tools  --safe-mode' "$t/args" &&
  [ "$(head -3 "$t/stdin")" = "Today: $(date '+%a %F')"$'\nSince: 2030-01-03 Thu\nNote: Staging is down by design.' ] &&
  [ "$(tail -n +4 "$t/stdin" | jq -c '[.kind, .key, .people, .source, .when, .title, .status, .text]')" = '["worked","ABC-1",[],"session","Thu 10:00","Fix it","In Review","session \"a\" (09:00–10:00): working on it"]
["discussed","ABC-1",["Ann Lee"],"teams","Thu 11:00","Fix it","In Review","the retry limit"]' ] ||
  { echo "the model's input or flags"; cat "$t/stdin" "$t/args"; exit 1; }
# No template: no standup and no run.
out=$(brief | jq -c '.template = ""' | sum) && [ -z "$out" ] && [ "$(runs)" = 1 ] || { echo "a brief without a template: $out"; exit 1; }
# A session's span and last text moved: cached, no second run.
out=$(brief '' 'session "a" (09:00–11:00): done' | sum) && [ "$out" = "Yesterday I finished ABC-1." ] && [ "$(runs)" = 1 ] ||
  { echo "a session's new text ran the model again"; exit 1; }
# A new item: run again.
item() { echo "[{\"kind\":\"moved\",\"key\":\"ABC-1\",\"people\":[],\"source\":\"pr\",\"at\":$1,\"text\":\"$2\"}]"; }
brief '' '' "$(item 1893672000 'app#1 merged')" | sum >/dev/null && [ "$(runs)" = 2 ] || { echo "a new item didn't run the model"; exit 1; }
# A failure: exit 1 and the reason, the cache untouched.
out=$(brief '' '' "$(item 1893675600 'Jira: A → B')" | STUB_FAIL=1 sum) && { echo "a failed call exited 0"; exit 1; }
grep -q 'rate limited' <<<"$out" || { echo "failure reason missing: $out"; exit 1; }
[ "$(sed -n 2p "$t/cache/session-orchestration/standup/2030-01-03.txt")" = "Yesterday I finished ABC-1." ] ||
  { echo "a failure changed the cache"; exit 1; }
out=$(sum <<<"not a brief") && { echo "an input that is no brief exited 0"; exit 1; }
[ "$out" = "not a brief on stdin (session-status --yesterday --json)" ] || { echo "no brief: $out"; exit 1; }
# A hung call: killed at the cap, not waited out.
st=$SECONDS
out=$(brief '' '' "$(item 1893679200 'Jira: B → C')" | STUB_HANG=1 STANDUP_SUMMARY_CAP_S=1 sum) && { echo "a hung call exited 0"; exit 1; }
[ $((SECONDS - st)) -lt 10 ] || { echo "a hung call took $((SECONDS - st))s"; exit 1; }
# Another model or template: written again, though the items are the same; another day has its own cache.
brief | SESSION_STATUS_SUMMARY_MODEL=sonnet sum >/dev/null && [ "$(runs)" = 5 ] &&
  grep -q -- '--model sonnet' "$t/args" || { echo "another model reused the cache"; exit 1; }
brief | jq -c '.template = "Yesterday: <tasks>."' | sum >/dev/null && [ "$(runs)" = 6 ] || { echo "another template reused the cache"; exit 1; }
brief 2030-01-06 | sum >/dev/null && [ "$(runs)" = 7 ] &&
  [ -f "$t/cache/session-orchestration/standup/2030-01-06.txt" ] || { echo "another day reused the cache"; exit 1; }
echo ok
