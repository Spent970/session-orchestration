#!/usr/bin/env bash
# Side effects only, so a coordinator sees what a background session waits on without `claude attach`:
#  request (PermissionRequest: a permission dialog is about to show) keeps the call it asks about in
#          ~/.cache/session-status/blocked/<session_id>.call: the transcript doesn't hold it while it waits.
#  notify  (Notification: permission_prompt|agent_needs_input|elicitation_dialog) writes
#          ~/.cache/session-status/blocked/<session_id>.json: time, type, message, and, for a permission prompt,
#          that call (tool, input's first 300 chars; used up) when it's from the last 2 minutes. session-status
#          shows it while the session waits (status waiting, or not idle and its transcript no newer).
#  denied  (PermissionDenied: an auto-mode denial) appends time, session, cwd, tool, input, reason to
#          ~/.cache/session-status/denied.jsonl.
d=~/.cache/session-status; mkdir -p "$d/blocked" 2>/dev/null
in=$(cat)
call='{tool: .tool_name, input: ((.tool_input.command // (.tool_input | tojson)) | gsub("\\s+"; " ") | .[:300])}'
sid=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null); [ -n "$sid" ] || exit 0
case "${1:-}" in
  request)
    jq -c "{time: (now | floor)} + $call" <<<"$in" > "$d/blocked/$sid.call" 2>/dev/null ;;
  notify)
    c=
    if [ "$(jq -r .notification_type <<<"$in")" = permission_prompt ]; then
      c=$(jq -c 'select(.time >= (now - 120)) | del(.time)' "$d/blocked/$sid.call" 2>/dev/null); rm -f "$d/blocked/$sid.call"
    fi
    [ -n "$c" ] || c='{}'
    jq -c --argjson c "$c" '{time: (now | floor), type: .notification_type, message} + $c' <<<"$in" > "$d/blocked/$sid.json.tmp" &&
      mv "$d/blocked/$sid.json.tmp" "$d/blocked/$sid.json" ;;
  denied)
    jq -c "{time: (now | floor), session: .session_id, cwd} + $call + {reason}" <<<"$in" >> "$d/denied.jsonl" 2>/dev/null
    # telemetry=full: a refuse line naming the tool (lib.sh usage); another server's MCP tool only as mcp, its name may
    # name a company.
    { read -r t; read -r cwd; } < <(jq -r '(.tool_name // "" | if startswith("mcp__session-orchestration__") then "mcp-" + .[28:]
      elif startswith("mcp__") then "mcp" else . end | ascii_downcase | gsub("[^a-z0-9-]"; "-") | .[:40]), (.cwd // ".")' <<<"$in")
    ( l=$(cd "${0%/*}/.." 2>/dev/null && pwd)/lib.sh; cd "$cwd" 2>/dev/null; . "$l" && usage "$t" refuse ) >/dev/null 2>&1 ;;
esac
exit 0
