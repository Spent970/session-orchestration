#!/usr/bin/env bash
# Self-check for history-git: the Stop hook's repo (git dir outside the folder, pre-push refusing, a file over 1 MB
# left out), a commit per changed turn and none otherwise, `versions` feeding pending's --scan and history LABEL, `run`,
# adopting a repo set up by hand, config history.dirs (adopting, one repo per file when folders nest, a folder holding
# the root refused), one commit per repo named after the session, and waiting out another git's index lock. Run: bash history-git.test.sh
set -euo pipefail; unset XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_CODE_SESSION_ID GIT_DIR GIT_WORK_TREE
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; trap 'echo "failed at line $LINENO: $BASH_COMMAND" >&2' ERR
export HOME=$tmp CLAUDE_CONFIG_DIR=$tmp/cfg XDG_CACHE_HOME=$tmp/cache
fail() { echo "history-git.test: $*"; exit 1; }
mkroot() {
  local r; r=$(mkdir -p "$tmp/$1/.claude" "$tmp/$1/notes" "$tmp/$1/$2" && cd "$tmp/$1" && pwd -P)
  echo '{"pending": {"file": "notes/pending.md"}}' > "$r/.claude/coordination.local.json"
  printf -- '- Replies folder: `%s`\n' "$2" > "$r/CLAUDE.md"; echo "$r"
}
root=$(mkroot proj replies); P=$root/notes/pending.md; R=$root/replies
stop() { printf '{"session_id":"%s-1111","cwd":"%s"}' "${2:-aaaabbbb}" "$1" | bash "$here/history-git" commit; }
H=$tmp/.local/state/session-orchestration/history
GR=$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$R").git; GP=$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root/notes").git
log() { git --git-dir="$1" log --format=%s 2>/dev/null; }

printf '# Pending\n\n- 2026-11-01 ABC-1: first wording\n- 2026-11-01 ABC-2: goes soon\n' > "$P"
echo 'unrelated' > "$root/notes/other.md"
echo 'report one' > "$R/ABC-1.md"
head -c 1100000 /dev/zero > "$R/dump.json"
stop "$root"
[ -d "$GR" ] && [ -d "$GP" ] && [ ! -e "$R/.git" ] && [ ! -e "$root/notes/.git" ] || fail "repos not made outside the folders"
[ "$(log "$GR")" = "aaaabbbb: ABC-1.md" ] || fail "replies commit: $(log "$GR")"
[ "$(git --git-dir="$GP" ls-files)" = pending.md ] && [ -z "$(git --git-dir="$GP" remote)" ] || fail "handoff repo files: $(git --git-dir="$GP" ls-files)"
grep -qx /dump.json "$GR/info/exclude" || fail "a dump wasn't left out"
! "$GR/hooks/pre-push" 2>/dev/null || fail "pre-push lets a push through"

stop "$root"   # nothing changed: no commit
[ "$(log "$GR" | wc -l | tr -d ' ')" = 1 ] && [ "$(log "$GP" | wc -l | tr -d ' ')" = 1 ] || fail "an unchanged turn committed"

# a Bash-style write (no Edit) shows the same: reworded, one gone, a reply deleted
printf '# Pending\n\n- 2026-11-01 ABC-1: second wording\n' > "$P"; rm "$R/ABC-1.md"; echo two > "$R/ABC-3.md"
stop "$root" ccccdddd
[ "$(log "$GP" | head -1)" = "ccccdddd: pending.md" ] && [ "$(git --git-dir="$GR" ls-files)" = ABC-3.md ] ||
  fail "second commit: $(log "$GP") / $(git --git-dir="$GR" ls-files)"

# versions → pending's --scan reads git, not transcripts
[ "$(bash "$here/history-git" versions "$P" | wc -l | tr -d ' ')" = 2 ] || fail "versions"
scan=$(cd "$root" && bash "$here/pending" history --scan)
grep -q $'\tccccdddd\tABC-1\tABC-1\tchange\t2026-11-01 ABC-1: second wording$' <<<"$scan" &&
  grep -q $'\tccccdddd\tABC-2\tABC-2\tgone\tunknown$' <<<"$scan" || fail "scan from git: $scan"
hist=$(cd "$root" && bash "$here/pending" history ABC-1)
[ "$(grep -c '^- ' <<<"$hist")" = 2 ] && grep -q '(aaaabbbb) 2026-11-01 ABC-1: first wording' <<<"$hist" || fail "history from git: $hist"
grep -q 'seeded from git and transcripts: 1 open' <<<"$(cd "$root" && bash "$here/pending" history --seed)" || fail "seed from git"

# run: git on a folder's repo
[ "$(cd "$root" && bash "$here/history-git" run replies log --format=%s | wc -l | tr -d ' ')" = 2 ] || fail "run replies"
rc=0; (cd "$root" && bash "$here/history-git" run nope) >/dev/null || rc=$?; [ $rc = 2 ] || fail "run's usage"

# a repo set up by hand (the folder holding the replies, no remote) is adopted, not shadowed
root=$(mkroot adopt docs/replies); R=$root/docs/replies
git -C "$root/docs" init -q; echo mine > "$root/docs/notes.md"; git -C "$root/docs" add notes.md; printf '# Pending\n\n- 2026-11-01 X-1: x\n' > "$root/notes/pending.md"; echo r > "$R/X-1.md"
stop "$root"
[ "$(git -C "$root/docs" log --format=%s)" = "aaaabbbb: X-1.md" ] && [ ! -d "$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$R").git" ] ||
  fail "adopting: $(git -C "$root/docs" log --format=%s)"
[ "$(git -C "$root/docs" diff --cached --name-only)" = notes.md ] || fail "the user's staged change was committed"
# a repo holding the project root is never adopted: the project's handoff gets its own repo
mkdir -p "$tmp/mono"; git -C "$tmp/mono" init -q; root=$(mkroot mono/sub r)   # the file in the root, the repo its parent
echo '{"pending": {"file": "pending.md"}}' > "$root/.claude/coordination.local.json"
printf '# Pending\n\n- 2026-11-01 M-1: m\n' > "$root/pending.md"; stop "$root"
[ -z "$(git -C "$tmp/mono" log --oneline 2>/dev/null)" ] && [ -d "$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root").git" ] || fail "a repo above the root was adopted"

# history.dirs: a hand-made remote-less repo holding the replies folder and the handoff file is adopted, keeping its
# history; both are committed only there, in one commit named after the session; a plain listed folder gets an outside
# repo; "." (the root) is refused
root=$(mkroot dirs docs/claude/replies); D=$root/docs/claude; mkdir -p "$root/extra"
echo '{"pending": {"file": "docs/claude/pending.md"}, "history": {"dirs": ["docs/claude", "extra", "."]}}' > "$root/.claude/coordination.local.json"
git -C "$D" init -q; echo old > "$D/old.md"; git -C "$D" add old.md; git -C "$D" -c user.name=u -c user.email=u@x commit -qm "by hand"
mkdir -p "$tmp/cfg/sessions"; echo '{"sessionId":"eeeeffff-1111","name":"my task"}' > "$tmp/cfg/sessions/1.json"
printf '# Pending\n\n- 2026-11-01 D-1: d\n' > "$D/pending.md"; echo r > "$D/replies/D-1.md"; echo n > "$D/notes.md"; echo x > "$root/extra/x.md"
stop "$root" eeeeffff
[ "$(git -C "$D" log --format=%s | tr '\n' '|')" = "my task: notes.md pending.md D-1.md|by hand|" ] || fail "adopted repo's log: $(git -C "$D" log --format=%s)"
[ "$(git -C "$D" log -1 --format='%(trailers:key=Session,valueonly,separator=)')" = eeeeffff-1111 ] || fail "no Session trailer"
for d in "$D/replies" "$D" "$root"; do [ ! -d "$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$d").git" ] || fail "a second repo for $d"; done
GX=$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root/extra").git
[ "$(git --git-dir="$GX" ls-files)" = x.md ] && [ ! -e "$root/extra/.git" ] || fail "listed plain folder: $(git --git-dir="$GX" ls-files 2>&1)"
[ "$(cd "$root" && bash "$here/history-git" run replies log --format=%s | wc -l | tr -d ' ')" = 2 ] || fail "run replies: not the adopted repo"
v=$(cd / && bash "$here/history-git" versions "$D/pending.md")   # any cwd: FILE's project
[ "$(jq -r .s <<<"$v")" = eeeeffff ] || fail "versions via the outer repo: $v"

# another git holding the index lock: the hook waits it out
echo r2 > "$D/replies/D-2.md"; touch "$D/.git/index.lock"
stop "$root" eeeeffff & sleep 1; rm -f "$D/.git/index.lock"; wait
[ "$(git -C "$D" log -1 --format=%s)" = "my task: D-2.md" ] || fail "lock not waited out: $(git -C "$D" log -1 --format=%s)"

# a hand-made repo inside a listed folder keeps its own history: not a gitlink in the outer one
root=$(mkroot nest docs/claude/replies); D=$root/docs/claude
echo '{"history": {"dirs": ["docs"]}}' > "$root/.claude/coordination.local.json"
git -C "$D" init -q; echo top > "$root/docs/top.md"; echo r > "$D/replies/N-1.md"
stop "$root" eeeeffff
GD=$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root/docs").git
[ "$(git --git-dir="$GD" ls-files)" = top.md ] && grep -qx /claude/ "$GD/info/exclude" || fail "inner repo as a gitlink: $(git --git-dir="$GD" ls-files -s)"
[ "$(git -C "$D" log --format=%s)" = "my task: N-1.md" ] || fail "inner repo not committed: $(git -C "$D" log --format=%s 2>&1)"
# a symlinked replies folder: run still finds its repo
ln -s "$D/replies" "$tmp/rlink"; printf -- '- Replies folder: `%s`\n' "$tmp/rlink" > "$root/CLAUDE.md"
[ "$(cd "$root" && bash "$here/history-git" run replies log --format=%s)" = "my task: N-1.md" ] || fail "run through a symlink"
# the project's state folder: one outside repo holds it whole, the replies folder in it no second one
root=$(mkroot state x); S=$tmp/.local/state/session-orchestration/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root")
mkdir -p "$S/replies"; S=$(cd "$S" && pwd -P); echo '{}' > "$root/.claude/coordination.local.json"
printf -- '- Replies folder: `%s/replies/`\n' "$S" > "$root/CLAUDE.md"; echo r > "$S/replies/S-1.md"; echo m > "$S/memory.md"; echo p > "$S/pending.md"
stop "$root"
GS=$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$S").git
[ "$(git --git-dir="$GS" ls-files 2>&1 | paste -sd' ' -)" = "memory.md pending.md replies/S-1.md" ] && [ ! -d "$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$S/replies").git" ] ||
  fail "state folder: $(git --git-dir="$GS" ls-files 2>&1)"
# a folder the project's git tracks (team files, a committed docs folder) is skipped; an untracked one beside it kept;
# the repo file's pending.file and history.dirs are dropped (personal paths)
root=$(mkroot tracked r); git -C "$root" init -q; mkdir -p "$root/docs" "$root/.claude/coordination" "$root/mine"
echo t > "$root/docs/t.md"; echo m > "$root/.claude/coordination/memory.md"; echo x > "$root/mine/x.md"
git -C "$root" add docs .claude/coordination
echo '{"history": {"dirs": ["docs", ".claude/coordination", "mine"]}}' > "$root/.claude/coordination.local.json"
echo '{"pending": {"file": "docs/p.md"}, "history": {"dirs": ["elsewhere"]}}' > "$root/.claude/coordination/coordination.json"
echo '#!/bin/sh' > "$root/.claude/session-status-adapter"; chmod +x "$root/.claude/session-status-adapter"
stop "$root"
for d in docs .claude/coordination; do [ ! -d "$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root/$d").git" ] || fail "a history repo for tracked $d"; done
[ "$(git --git-dir="$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root/mine").git" ls-files 2>&1)" = x.md ] || fail "untracked listed folder skipped"
rm "$root/.claude/coordination.local.json"
[ -z "$(cd "$root" && . "$here/../../lib.sh" && config pending.file; config history.dirs)" ] || fail "the repo file set a personal path"
# a history.dirs that isn't a list warns
echo '{"history": {"dirs": "docs"}}' > "$root/.claude/coordination.local.json"
(cd "$root" && . "$here/../../lib.sh" && config history.dirs 2>&1) | grep -q 'history.dirs.* is not valid' || fail "no warning for a bad history.dirs"
echo "history-git.test: ok"
