---
name: secret-triage
description: Triage betterleaks findings — decide real secret vs false positive and clear each one the right way. Use when a `git push` is blocked with `[gox-guard/secrets]`, a betterleaks scan reports findings, or the task involves `.betterleaksignore`, `betterleaks:allow`, or a betterleaks allowlist.
---

# Secret Finding Triage

The gate scans every commit being pushed that no remote has yet, one commit diff at a time. A
finding line reads `rule  file:line  @commit  fp=<commit>:<file>:<rule>:<line>`.

## 1. Get the full list

The block message lists at most 10 findings. When it truncates, it prints the rescan command for
the same commit range — run it as printed. Keep `--redact`; never add `--validation` (it sends the
candidate secret to the vendor's API).

## 2. Judge each finding

Read every flagged line in one command, run from the repo root, with the fingerprints pasted in:

```bash
while IFS=: read -r commit rest; do
  line="${rest##*:}"; file="${rest%:*:*}"
  printf '%s:%s\t%s\n' "$file" "$line" "$(git show "$commit:$file" | sed -n "${line}p")"
done <<'EOF'
<fingerprints, one per line>
EOF
```

This prints the values into the transcript, which is why the gate redacts — so if one looks real,
do not repeat it in replies, commit messages, or files.

With more than about five findings and a cheaper subagent available, hand it this step: give it
the fingerprints and the command, and ask for one line per finding — fingerprint, verdict (`real`,
`false positive`, `unsure`), reason, never the value. Count `unsure` as real. Prefer a mid-tier
model over the cheapest: a real secret passed off as a false positive is the costly mistake. What
to ignore and what to rewrite stays your decision.

- **Real, or you cannot tell**: a provider-format token, a random-looking value, a password next
  to a real host or account. Treat "cannot tell" as real and ask the user.
- **False positive**: the value evidently authenticates nothing — a placeholder (`REPLACE`,
  `CHANGEME`), a format verb or template (`%s`), a regex or code expression, a fixture literal
  (`"test-password"`), credentials on a reserved host (`.invalid`, `.test`, `example.com`).

The path is not evidence. Real secrets get pasted into tests and READMEs; judge the value.

## 3. Real secret

1. Remove it from the pending commits themselves (amend or rebase — they are unpushed). A
   follow-up commit that deletes the line leaves the old commit flagged and the secret in history.
   Rewriting commits you did not create in this session is the user's call.
2. Tell the user the value sat in local history and must be rotated.
3. Never add it to an ignore file or allowlist.

## 4. False positive — narrowest fix first

| Situation | Fix |
|---|---|
| The line is added by a commit you are still writing or will amend | Rewrite the fake value with a `mock-` prefix (`mock-password`); if it must keep a real format, put a `betterleaks:allow` comment on that line |
| The line is in an earlier pending commit, even if a later commit changed or deleted it | Append its fingerprint to `.betterleaksignore` |
| A pattern other than `mock-` keeps recurring across commits | Propose a value rule in `.betterleaks.toml` to the user (below); do not edit scanner config on your own |

One finding, one place: a finding the config already clears needs no ignore entry.

**`.betterleaksignore`** lives at the repo root: one fingerprint per line, copied exactly from
`fp=`; lines starting with `#` are comments — use one to say what was verified, in words: a
comment that quotes the flagged line gets the ignore file's own commit flagged. The scanner reads
it from the working tree, not from the commits being pushed, so it covers findings in older
commits — push from a checkout that contains it. Commit it so teammates and CI see the same
result. A fingerprint embeds the commit ID: finish any amend or rebase before collecting
fingerprints. An entry clears exactly one finding; the same value in a new commit is flagged again.

**`.betterleaks.toml`** is team policy, not a per-finding fix. An allowlist there clears a pattern
in every future commit, and a careless one switches detection off — hence the user's decision.

- A repo without the file needs none: the gate then scans with its own default, the built-in
  rules plus the `mock-` rule below.
- A repo-root file replaces that default — nothing is merged — so it must carry the `mock-` rule
  itself, or `mock-` values get flagged. The gate reads it from the working tree like the ignore
  file; `BETTERLEAKS_CONFIG` in the environment replaces both.
- Keep `[extend]` / `useDefault = true`: without it the built-in rules are gone. The gate refuses a
  file that has neither rules nor `[extend]`.
- Outside the gate, betterleaks 1.10 loads no config by itself: CI and terminal runs need
  `-c .betterleaks.toml`, so a repo scanned in CI commits the file.
- Write a value rule as a top-level `filter`, never on a path. It must sit above `[extend]`: a key
  below a `[table]` line belongs to that table, and betterleaks 1.x then ignores it without an
  error.

```toml
filter = 'matchesAny(finding["secret"], [`^mock-`])'

[extend]
useDefault = true
```

This reads "drop a finding whose value starts with `mock-`"; a provider-format token is still
reported with that prefix, because its match starts at the token. It is checked on betterleaks 1.10.1
and is the form v2 keeps. `[[allowlists]]` works on 1.x only; v2 refuses to load it per its
migration guide, so move an existing one to `filter` before upgrading. After any change run
`betterleaks config check .betterleaks.toml`, then rescan: a value that matches must disappear and
one that does not must stay. The check matters: betterleaks 1.10.1 scans on without a `filter`
that fails to compile and says nothing, so the mock values simply stay flagged.

## 5. Push again

Commit the changes, then run `git push` as its own command so the scan sees the final commits.
`GOX_GUARD_SKIP=1` is not a way past findings; use it only when the user explicitly asks.
