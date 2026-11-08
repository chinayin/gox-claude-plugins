---
name: delegate
description: Token-saving subagent routing. Use when facing token-heavy, read-heavy, conclusion-only work (reading Lark/Feishu in full or writing to it, wide code searches, log/long-document analysis) to decide whether to offload the work to a cheaper-model subagent and which tier to use.
---

# Token-saving three-tier split

The main agent (whatever top-tier model the session runs) does only orchestration and decisions with the user. Offload token-heavy work; keep raw material out of the main context.

## Which tier

| Kind of work | Dispatch to | Model (Claude Code) | Why |
|---|---|---|---|
| Read / compare / verify / search (conclusion only) | `cheap-reader` | Haiku | Cheapest tier; raw material is read once and discarded |
| Correctness-sensitive writes (Lark/Feishu XML/blocks, reliable persistence) | `careful-writer` | Sonnet | Write errors are costly; mid tier at a fraction of the top tier's price |
| Orchestration / decisions | main agent | session model | Keep the main context lean |

In Claude Code, a read that needs subtle judgment may be promoted to Sonnet; a purely mechanical append may drop to Haiku. Change the model within the same role: a cheaper write still belongs to a writer, not the read-only reader.

Cursor uses the same task tiers: economical reads through `cheap-reader`, reliable writes through `careful-writer`, and decisions in the main session. Use the models and permissions configured in `agents-cursor/`; the routing policy does not depend on a particular model family or version. These are role mappings, not claims of equal model capability.

## When it's worth offloading

Rule of thumb (empirical, not benchmarked): offload when the throwaway material the subagent must process is **≳ 3,000 tokens**. Because:
1. Skill loading (e.g. `lark-*` SKILL + references, often tens of thousands of tokens) moves from the main model's pricing to the cheaper tier's.
2. Raw material stays out of the main context, avoiding it being re-billed on every subsequent turn (the biggest lever).

If the task is tiny, or the main thread will need the raw material again, keep it inline instead.

## How to dispatch

- Claude Code: use the Task/Agent tool with `subagent_type` set to `cheap-reader` or `careful-writer`.
- Cursor: select the same named custom agent through its native delegation tool; use the model and permissions from its Cursor agent definition.

Have it return only a compact conclusion. If the result is large, an agent with write permission may save it to an authorized scratchpad and return the path. A read-only agent returns a compact source index instead; the parent can decide what to retrieve or save. Keep the main context lean.
