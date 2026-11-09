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
- Codex: use the native subagent tool with the model selection and role brief below. The role names describe responsibilities; they do not require registered Claude agents.

Have it return only a compact conclusion. If the result is large, an agent with write permission may save it to an authorized scratchpad and return the path. A read-only agent returns a compact source index instead; the parent can decide what to retrieve or save. Keep the main context lean.

### Codex model selection and brief

When offloading is worthwhile, this skill requests native subagent delegation with an explicit model selection:

1. Use the model choices exposed by the current tool/client. Honor an explicit user choice for delegated work; otherwise select the cheapest available model adequate for the task. Prefer an economical tier for clear reads/searches/extraction and a more capable tier for correctness-sensitive writes or ambiguous reads. Luna and Sol are examples of these categories, not capability equivalents to Haiku/Sonnet. Resolve to an actual supported model ID; never pass a Claude alias, a guessed family alias, or an assumed latest version.
2. Pass that ID through the native spawn tool's model option. Omitting it can inherit the parent's expensive model. Follow the active tool schema: when `fork_turns` is exposed, use `"none"` with a self-contained brief so model overrides are allowed and the full parent conversation is not copied. Honor user reasoning settings; otherwise use a supported effort proportionate to the task. Do not enable a premium speed mode for thrift.
3. Include the role, objective, working directory, source locations, applicable skill/rule paths, constraints, and expected compact result in the brief. A `cheap-reader` may read and report source locations, but must not modify files or external state. A `careful-writer` may change only the authorized targets and must verify the result. Without a Skill tool, read the relevant SKILL.md and references. These are task constraints; permissions and sandboxing remain those supplied by Codex.
4. If native delegation or model selection is unavailable, no suitable cheaper model is available, or the selected model is rejected, keep the work inline and briefly state the limitation. Do not silently use an unknown or more expensive model, create agent/config files, or launch a separate CLI session as a workaround. An explicit user model choice takes precedence, but same-model delegation is context isolation, not a cheaper model tier.

Check the actual model in host-provided metadata when exposed; a requested model or the subagent's self-report alone does not prove which model ran. If unobservable, report that limit. A lower-priced model and compact output do not by themselves prove lower total tokens, cost, or subscription usage.
