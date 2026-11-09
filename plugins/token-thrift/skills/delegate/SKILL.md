---
name: delegate
description: Use when the parent agent faces bulk reading, searches, log/document analysis, or already-decided writes suitable for a cheaper model. Not for workers executing an assigned brief.
---

# Delegate bulk work

Parent routing policy. An assigned worker should execute its brief, not load this policy or delegate again unless explicitly asked.

## When and where

Delegate before reading bulk source material in the parent. Keep tiny tasks, or work needing the full raw material in the parent, inline. About 3,000 disposable tokens is a rough heuristic, not a measured break-even point.

Batch related inputs for one result into one worker; split for independent objectives or context limits.

- `cheap-reader`: read/search/compare/verify; no local or external writes.
- `careful-writer`: authorized writes; verify the saved result.
- Parent: decisions and synthesis.

## Dispatch

- Claude Code: Task/Agent with the registered `cheap-reader` or `careful-writer`; Haiku for reads, Sonnet for reliable writes. Adjust the model for difficulty while preserving the role.
- Cursor: native delegation using the named agent's model and permissions in `agents-cursor/`.
- Codex: this skill requests native delegation with an explicit supported model ID. Honor the user's delegated-model and reasoning choices; otherwise choose the cheapest adequate tier and supported task-appropriate effort. Resolve from current tool/client choices, never Claude aliases or guessed IDs. Reuse the choice for similar work; reconsider when requirements or availability change. Follow the active schema; when `fork_turns` is exposed, use `"none"`. Do not enable premium speed for thrift.

Codex fallback: if native delegation/model selection is unavailable or rejected, work inline. Without a user override, also stay inline if no suitable cheaper model exists. Do not create configuration or launch another CLI as a workaround.

## Brief and return

Send only the objective, source locations/working directory, necessary task-skill paths, authorized targets/constraints, and output limit. Do not forward this routing skill, full history, or raw material accessible at those locations. Tell workers to execute the brief without further delegation and load only necessary task skills.

Request compact findings with evidence locations; writes also report verification. Large results may go to an authorized artifact; read-only workers return a source index. Verify against relevant evidence instead of automatically rereading every input.

Use successful results even if model metadata is absent; do not infer actual models or savings from requests or self-reports. Roles do not create permission sandboxes.
