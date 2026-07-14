---
name: delegate
description: Token-saving subagent routing. Use when facing token-heavy, read-heavy, conclusion-only work (reading Lark/Feishu in full or writing to it, wide code searches, log/long-document analysis) to decide whether to offload the work to a cheaper-model subagent and which tier to use.
---

# Token-saving three-tier split

The main agent (Opus) does only orchestration and decisions with the user. Offload token-heavy work; keep raw material out of the main context.

## Which tier

| Kind of work | Dispatch to | Model | Why |
|---|---|---|---|
| Read / compare / verify / search (conclusion only) | `cheap-reader` | Haiku | Cheapest ($1/$5); raw material is read once and discarded |
| Correctness-sensitive writes (Lark/Feishu XML/blocks, reliable persistence) | `careful-writer` | Sonnet | Write errors are costly; Sonnet is only 40–60% of Opus |
| Orchestration / decisions | main agent | Opus | Keep the main context lean |

A read that needs subtle judgment may be promoted to Sonnet; a purely mechanical append may drop to Haiku.

## When it's worth offloading

Rule of thumb: offload when the throwaway material the subagent must process is **≳ 3,000 tokens**. Because:
1. Skill loading (e.g. `lark-*` SKILL + references, often tens of thousands of tokens) moves from Opus pricing to the cheaper model's pricing.
2. Raw material stays out of the main context, avoiding it being re-billed on every subsequent turn (the biggest lever).

If the task is tiny, or the main thread will need the raw material again, keep it inline instead.

## How to dispatch

Use the Task/Agent tool with `subagent_type` set to `cheap-reader` or `careful-writer`. Have it return only a compact conclusion; if the result is large, have it write a scratchpad file and return the path. Keep the Opus main context lean.
