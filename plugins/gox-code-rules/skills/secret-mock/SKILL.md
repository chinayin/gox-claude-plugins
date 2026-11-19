---
name: secret-mock
description: >-
  How to write a fake password, token, API key or credential URL so a secret scanner clears it by rule. Use before putting any credential-like literal into a test, fixture, doc example, sample config or script — even an obviously fake one, and even if the user never mentions scanning.
---

# Mock Secrets

A secret scanner (betterleaks, run before push and in CI) cannot tell a made-up credential from a
leaked one. Every false hit blocks a push and costs a triage round, so write the value in a form
the scanner clears by rule.

## Pick the value, in this order

1. **The repo's convention.** Read `.betterleaks.toml` at the repo root. A top-level `filter` — or
   `[[allowlists]]` in an older file — that matches on the secret value defines what a mock looks
   like here. If its pattern is `^mock-`, write `mock-db-password`.
2. **No such file or rule.** Use a form the scanner ignores by design: a password written as
   `<password>`, `${PASSWORD}` or `your-password`; a credential URL on an `example.com`,
   `example.org` or `example.net` host. Still reported: `REPLACE`, `CHANGEME`, `replace-me`, and
   hosts under `.invalid` or `.test`. (Checked against betterleaks 1.10.1; re-check after an
   upgrade.)
3. **The code under test needs a real-format value** — a provider key shape, a length or entropy
   check. Keep it and put a `betterleaks:allow` comment on that line, in the commit that adds it.

## Do not

- Invent a realistic-looking value (random hex or base64, `sk_live_…`, `AKIA…`), or paste a real
  one "for now".
- Create or edit `.betterleaks.toml` to make a value pass. A missing or too-narrow convention is
  the user's decision — raise it.
- Count on the path. A value under `testdata/` or in a README is scanned like any other.
