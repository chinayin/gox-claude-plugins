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
| The line is added by a commit you are still writing or will amend | Rewrite the fixture to a form the scanner ignores (below), or put a `betterleaks:allow` comment on that line |
| The line is in an earlier pending commit, even if a later commit changed or deleted it | Append its fingerprint to `.betterleaksignore` |
| The same pattern keeps recurring across commits | Propose a value allowlist in `.betterleaks.toml` to the user (below); do not edit scanner config on your own |

One finding, one place: a finding the config already clears needs no ignore entry.

**`.betterleaksignore`** lives at the repo root: one fingerprint per line, copied exactly from
`fp=`; lines starting with `#` are comments — use one to say what was verified, in words: a
comment that quotes the flagged line gets the ignore file's own commit flagged. The scanner reads
it from the working tree, not from the commits being pushed, so it covers findings in older
commits — push from a checkout that contains it. Commit it so teammates and CI see the same
result. A fingerprint embeds the commit ID: finish any amend or rebase before collecting
fingerprints. An entry clears exactly one finding; the same value in a new commit is flagged again.

**Forms ignored by design** (checked against betterleaks 1.10.1; re-check after an upgrade):
passwords written as `<password>`, `${PASSWORD}`, or `your-password`; credential URLs whose host is
under `example.com` / `example.org` / `example.net`. Still reported: `REPLACE`, `CHANGEME`,
`replace-me`, and hosts under `.invalid` or `.test`.

**`.betterleaks.toml`** is team policy, not a per-finding fix. An allowlist there clears a pattern
in every future commit, and a careless one switches detection off — hence the user's decision.

- The gate passes the repo-root file to the scanner, read from the working tree like the ignore
  file. `BETTERLEAKS_CONFIG` in the environment replaces it; the two are not merged.
- Keep `[extend]` / `useDefault = true`: without it the built-in rules are gone. The gate refuses a
  file that has neither rules nor `[extend]`.
- Match the value (`regexTarget = "secret"`), not a path.
- Outside the gate, betterleaks 1.10 does not pick the file up by itself: CI and terminal runs
  need `-c .betterleaks.toml`.

## 5. Push again

Commit the changes, then run `git push` as its own command so the scan sees the final commits.
`GOX_GUARD_SKIP=1` is not a way past findings; use it only when the user explicitly asks.
