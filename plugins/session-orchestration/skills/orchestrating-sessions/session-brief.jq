# The daily brief, session-status --yesterday's data: built, checked against its format, drawn as text. By --arg mode:
#   build  jq -n, session-status's parts as named arguments (below) → the brief
#   check  a brief → nothing; its violations on stderr and exit 1
#   text   a brief → the text view (jq -r): what moved, what waits on you, whom you wait on, what is new, what you
#          worked on. discussed items aren't in it: they are for the list and the standup.
# The format (status-reference.md, The brief): {since: "YYYY-MM-DD", from: EPOCH, how, notes: [TEXT], template: TEXT,
# failed: [TEXT], tasks: {KEY: {status, title}}, items: [ITEM]}, ITEM = {kind (KINDS), key ("": no task),
# people: [NAME], source (a lowercase word: commit, session, pr, jira, teams…), at: EPOCH, text: one line}.
def KINDS: ["worked", "moved", "comment", "discussed", "asked", "waiting", "todo", "new"];
def strs: type == "array" and all(.[]; type == "string");
def item_ok: type == "object" and (.kind as $k | any(KINDS[]; . == $k)) and (.key | type) == "string"
  and (.people | strs) and (.source | type) == "string" and (.source | test("^[a-z][a-z0-9-]*$"))
  and (.at | type) == "number" and .at >= 0 and .at == (.at | floor)
  and (.text | type) == "string" and (.text | test("\\S")) and (.text | test("\n") | not);
def errs: [ (select(type != "object") | "not an object"),
  (objects
    | (select(.since | type != "string" or (test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not)) | "since: not a day (YYYY-MM-DD)"),
      (select(.from | type != "number") | "from: not a number"),
      (("how", "template") as $f | select(.[$f] | type != "string") | "\($f): not a string"),
      (("notes", "failed") as $f | select(.[$f] | strs | not) | "\($f): not a list of strings"),
      (select(.tasks | type != "object" or any(.[]; (.status | type) != "string" or (.title | type) != "string"))
        | "tasks: not {KEY: {status, title}}"),
      (select(.items | type != "array") | "items: not a list"),
      (.items | arrays | to_entries[] | select(.value | item_ok | not) | "items[\(.key)]: not an item: \(.value | tojson | .[0:200])")) ];

def lines: split("\n") | map(select(test("\\S")));
def ts: (strings // "") | sub("\\.[0-9]+"; "") | try fromdate catch 0;
# An adapter's older `yesterday` rows (`KEY<TAB>STATUS<TAB>TITLE`, then `  EPOCH<TAB>TEXT`), as heads and moved items.
def old_rows: reduce lines[] as $l ({k: "", out: []};
    ($l | split("\t")) as $p
    | if ($l | test("^  [0-9]+\t")) and .k != "" then
        .out += [{kind: "moved", key: .k, source: "tracker", at: ($p[0] | sub("^ +"; "") | tonumber), text: ($p[1:] | join("\t"))}]
      elif $l | test("^[^ \t]") then .k = $p[0] | .out += [{task: $p[0], status: ($p[1] // ""), title: ($p[2:] | join("\t"))}]
      else . end) | .out;
# Named arguments: since, from, how; and as raw text: events (session-status's own, `KIND<TAB>SOURCE<TAB>KEY<TAB>EPOCH<TAB>TEXT`),
# adapter (its `brief` lines: an item or a task's head `{task, status, title}` as JSON, anything else a failure
# message), old (its `yesterday` rows), notices (the messages module's notices.jsonl), notes, template.
def build: $ARGS.named as $a
  | (($a.adapter | lines | map(. as $l | try fromjson catch $l)) + ($a.old | old_rows)) as $ad
  # A line that is neither a head nor an item fails as it was written (a tracker's error body, a bare number).
  | [$ad[] | select(type != "string" and (objects | .task | type == "string") != true) | {raw: ., it: (objects | .key //= "" | .people //= [] | {kind, key, people, source, at, text})}] as $got
  | [$got[].it] as $its
  | [$ad[] | select(type != "string" and type != "object") | "not a brief item: \(tojson | .[0:200])"] as $scalars
  | { since: $a.since, from: ($a.from | tonumber), how: $a.how, notes: ($a.notes | lines), template: ($a.template | sub("^\\s+"; "") | sub("\\s+$"; "")),
      failed: ([$ad[] | strings | sub("^\\s+"; "")] + [$got[] | select(.it | item_ok | not) | "not a brief item: \(.raw | tojson | .[0:200])"] + $scalars),
      tasks: ([$ad[] | objects | select(.task | type == "string") | {key: .task, value: {status: (.status // "" | tostring), title: (.title // "" | tostring)}}] | from_entries),
      # A malformed line of the plugin's own (an empty time, a field short) is left out, never the whole brief.
      items: ([ ($a.events | lines[] | split("\t") | {kind: .[0], key: .[2], people: [], source: .[1], at: (.[3] // "" | tonumber? // -1), text: (.[4:] | join("\t"))}),
                $its[],
                # What still needs the user in Teams and mail, whenever it was sent: the module's current lines.
                ($a.notices | lines[] | (try fromjson catch empty) | objects | select(.line | type == "string")
                  | {kind: "new", key: (.mine[0]? // .triageTicket // "" | tostring), people: [.from | strings], source: (if .chat == "mail" then "mail" else "teams" end),
                     at: (.time | ts), text: (.line | sub("^(teams (DM|@|\\?)|mail) +"; ""))}) ] | map(select(item_ok)) | unique | sort_by(.at)) };

# The people an item's text doesn't already name.
def who: . as $i | [.people[] | select(. as $p | $i.text | contains($p) | not)] | if length > 0 then " (\(join(", ")))" else "" end;
def head($t): "\(.key)\($t[.key].title // "" | if . != "" then " " + . else "" end)";
def plural($w): "\(length) \($w)\(if length == 1 then "" else "s" end)";
def passing: .kind == "moved" or .kind == "comment";
# A task's line (the pane's briefLine): its sessions as a count (their texts are long), commits without their last
# subject, of what moved or was said only the latest from each source (where it stands now), the rest whole; each
# once, oldest first.
def line: [ (map(select(.source == "session")) | select(length > 0) | plural("session")),
    (map(select(.source != "session")) | (map(select(passing | not)) + (map(select(passing)) | group_by([.kind, .source]) | map(last))) | sort_by(.at)[]
      | if .kind == "worked" then .text | sub(" — last: .*"; "") else .text + who end) ]
  | reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end) | join("; ");
# Sessions under no task key and with nothing but their own text: counted in one line (the pane's isLoose).
def loose: (.[0].key | startswith("\"")) and all(.[]; .source == "session");
# One line per task, its latest first; an item of no task is a line of its own.
def section($title; $t): (group_by(.key) | map(if .[0].key == "" then .[] | [.] else . end) | sort_by(-(map(.at) | max))) as $rows
  | ($rows | map(select(loose | not) | "  " + (if .[0].key == "" then "" else (.[0] | head($t)) + " — " end) + line)
      + ($rows | map(select(loose)) | if length > 0 then ["  " + plural("session") + " on no task"] else [] end)) as $l
  | if ($l | length) > 0 then "", $title, $l[] else empty end;
def text: .tasks as $t | .items as $i
  | "Since: \(.since) \(.from | strflocaltime("%a")) (\(.how))",
    (.failed[] | "Lookup failed: " + .),
    ($i | map(select(.kind == "moved" or .kind == "comment")) | section("MOVED"; $t)),
    ($i | map(select(.kind == "todo")) | section("WAITS ON YOU"; $t)),
    ($i | map(select(.kind == "asked" or .kind == "waiting")) | section("YOU WAIT ON"; $t)),
    ($i | map(select(.kind == "new")) | section("NEW FOR YOU"; $t)),
    ($i | map(select(.kind == "worked")) | section("WORKED ON"; $t)),
    (if ($i | length) == 0 then "", "Nothing found since then."
     elif all($i[]; .kind == "discussed") then "", "Only discussions since then (--json lists them)." else empty end);

if $mode == "build" then build
elif $mode == "check" then errs | if length > 0 then (join("\n") + "\n" | halt_error(1)) else empty end
else text end
