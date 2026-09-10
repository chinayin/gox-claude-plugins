---
name: skill
description: Rules for naming an agent skill, choosing its body language, and keeping environment facts out of it. Use whenever a skill is created, renamed, split, reviewed, or edited — writing a SKILL.md or its frontmatter, adding a skill to a repo or plugin, splitting an overloaded skill in two, versioning one, or deciding what a new skill should be called — even when the user only says "add a skill for X" or asks what to name it. Use it together with skill-creator, which owns the authoring process; naming and language are decided here.
paths: "**/SKILL.md"
---

# Skill Authoring Rules

skill-creator owns the authoring process. This file adds only what it leaves open.

## Naming

- **One word** for a rule set about one kind of file or language: `go`, `shell`, `skill`.
- **Otherwise `object-action`** — the resource, then the one thing done to it: `cluster-deploy`,
  `token-rotate`, `user-invite`. Resources outnumber verbs, so listings group by resource, and the
  CLIs a skill wraps are noun-verb themselves (`kubectl get`, `gh pr`).
- **Verb-first only for a methodology with no single object** (`writing-plans`).
- Follow the form the sibling skills use. Do not rename an existing skill — the name is the
  invocation handle.
- No version in the name (`-v2`): two names for the same job compete for triggering. Version the
  plugin, or use the frontmatter `metadata` field.

## Language

English for the description, the body, and everything a script prints. Chinese only when the
repo's instructions or the user ask for it, or when the sibling skills are already in Chinese —
one skill set, one language.

## Environment facts

A skill is distributed and loaded into context. It must not contain a hostname, IP, account or
resource ID, or credential. Write where the value is read from, never the value itself.
