# Writing instructions

The plugin's skills, feature docs and the reply card are prompts: Claude follows them. Write them by Anthropic's
prompting guides, Agent Skills pages and the Claude Code docs on memory, skills, subagents and hooks.

Last reviewed 2026-11-19 against: prompt-engineering/overview,
prompt-engineering/claude-prompting-best-practices, agent-skills/overview, agent-skills/quickstart,
agent-skills/best-practices, agent-skills/enterprise, agent-skills/claude-api-skill,
strengthen-guardrails/mitigate-jailbreaks, strengthen-guardrails/reduce-hallucinations,
strengthen-guardrails/increase-consistency, strengthen-guardrails/reduce-latency,
strengthen-guardrails/reduce-prompt-leak, strengthen-guardrails/handle-streaming-refusals, cc/memory,
cc/best-practices, cc/skills, cc/sub-agents, cc/hooks-guide, cc/context-window, cc/cross-session-messaging,
cc/large-codebases, cc/agent-teams, cc/workflows, cc/goal, cc/plugins/components.

The per-model prompting pages (`prompt-engineering/prompting-claude-*`) are left off the list until a review
reads them, so the docs watch ([features/docs-watch.md](features/docs-watch.md)) shows each one. The coordinator of
the plugin repo's project sees a `docs watch:` Notices line for every watched page this list lacks.

To act on one: read the page (a platform page's URL plus `.md` gives its Markdown), change the skills and docs
where it changes how they should be written, then add the page to the list, with a period only at its end, and
update the date.
