---
name: delegate
description: Token-saving subagent routing. Use when facing token-heavy, read-heavy, conclusion-only work (reading Lark/Feishu in full or writing to it, wide code searches, log/long-document analysis) to decide whether to offload the work to a cheaper-model subagent and which tier to use.
---

# Token-saving three-tier split

Keep bulk material in a subagent's context when the parent needs only a conclusion. The parent retains decisions, authorization, and integration; small tasks can stay inline.

## Which role

| Kind of work | Dispatch to | Responsibility |
|---|---|---|
| Read / compare / verify / search | `cheap-reader` | Read-only evidence gathering; return a compact conclusion |
| Correctness-sensitive, authorized writes | `careful-writer` | Read the target, make the requested change, verify persistence |
| Decisions / integration | main agent | Use the session model and keep its context lean |

Model configuration belongs to each host's agent definitions. Claude uses Haiku for reads and Sonnet for writes. Cursor uses its own concrete model IDs and permission fields. These are corresponding work roles, not claims of equal model capability or guaranteed savings. Availability, billing, and the actual model selected must be checked in the host.

For difficult read-only work, request a stronger read-only agent or keep it with the parent; do not give a reading task write permission just to change models.

## When to offload

A starting heuristic, not a benchmark: delegate when throwaway source material is around 3,000 tokens or more. Skill loading and large reads then stay in the subagent's context, and the parent receives only the useful result.

Keep tiny tasks inline. Also stay inline when the parent will need most of the raw material again. Compare total usage, including subagent startup, retries, and output, before claiming savings.

## How to dispatch

- Claude Code: select `cheap-reader` or `careful-writer` through the available Task/Agent tool's `subagent_type`.
- Cursor: select the installed custom subagent by name through its native delegation tool, or use the `/cheap-reader` or `/careful-writer` picker entry. Do not assume Claude's tool API or model aliases.
- Other hosts: these agent definitions have no supported routing yet. Keep the task inline unless a host-native equivalent has explicitly been configured.

Give the subagent a self-contained brief: question or approved change, sources, applicable rules, constraints, and expected output. Request a compact result with paths or links and validation evidence. A read-only agent must not write scratchpads; the parent can save its result if needed. A writer may save larger output only within its authorized target.
