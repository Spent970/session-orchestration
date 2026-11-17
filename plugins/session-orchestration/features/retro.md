# Feature: retro

> **Start**: nothing to do: a retro run reports to you when it ends.
> **Read when**: a retro run's report arrives; the user approves some of its proposals; the user asks about the
> retro's schedule, scope or model; the newest retro report is over 8 days old.

Off by default. On when `features.retro` is `true` in the person's `.claude/coordination.local.json` (or the
person-wide `~/.config/session-orchestration/config.json`). It's a person key, like the whole `retro` block: a
committed file never starts a token-spending scheduled run for anyone, so the repo file can't set either. `/retro` by
hand works with the feature off.

A retro run (the `retro` skill) measures how this setup's sessions turn tokens into finished work and ranks at most 5
changes. It only measures and proposes; the user approves.

## Settings

`session-status --config KEY` prints each one in effect.

| Key | Values | Default |
|-----|--------|---------|
| `retro.scope` | `project` (this project's sessions) \| `plugin` (every project and account, what the plugin can change) \| `both` (one run each) | `project` |
| `retro.schedule` | `<day> HH:MM`, local time, day `mon`…`sun` (e.g. `mon 12:00`) | unset: by hand only |
| `retro.account` | the Claude config dir a scheduled run starts under (`~` expanded) | the current account |
| `retro.sections` | JSON list of section names: `units`, `context`, `waste`, `feedback`, `coordinator`, `memory`, `protocol`, `features`, `sizing` | unset: every section of the scope |
| `plan.models.retro` | `model/effort` a retro run starts on (`session-status --kind retro NAME`) | `fable/xhigh` under an account `fable.accounts` lists, else `opus/xhigh` |
| `plan.models.research` | `model/effort` for a research task (`--kind research`): a question answered from sources outside the project | `opus/high` |

A value outside its set falls back to the default with one warning line.

## Your part

- **A report arrives** (the retro's `reply`: its path and top proposals): pass it to the user as it is, with the
  report's path. Don't act on a proposal before the user approves it.
- **The user approves proposals**: start one fresh followups session for them, as
  [memory-rules.md](../skills/orchestrating-sessions/memory-rules.md) says. Never resume the retro session for it.
  A proposal the retro filed as a plugin feedback case is the plugin coordinator's, not yours.
- **An overdue run**: with `retro.schedule` set, the newest retro report in the replies folder is over
  8 days old. Tell the user once, with the start line (`claude --bg $(session-status --kind retro retro-<date>)
  -n retro-<date> "Session task: retro run. Use the session-orchestration:retro skill and follow it."` from the root)
  and start it on their yes.
