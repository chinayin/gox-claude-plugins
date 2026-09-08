# gox-guard: triage protocol

You are reading this because gox-guard blocked a `git push`: betterleaks found something that looks like a credential in the commits not yet on any remote. Work through the findings one by one. Do not bypass the gate to "get the push done".

## 1. Decide: real secret or false positive

Look at the flagged line in the flagged commit (`git show <commit> -- <file>`). A real secret is a value that grants access somewhere: API keys, tokens, passwords, private keys, connection strings with credentials. A false positive is a fixture, an example, a hash, a random-looking ID, or a placeholder.

If you cannot tell, treat it as real and ask the user.

## 2. Real secret

1. Remove the value from every commit that contains it. Typical recipe: `git reset --soft <last clean commit>`, replace the value (read it from the environment or a gitignored file instead), then recommit. For a secret buried under several commits, an interactive-free alternative is `git rebase --onto` or redoing the commits; keep the user informed before rewriting more than a few commits.
2. Tell the user, explicitly: the value already exists in local git history and possibly in their shell history or editor backups, so it should be **rotated** regardless of the cleanup.
3. Never allowlist a real secret, and never move it into a file that is still committed.

## 3. False positive

Pick the cheapest fix that is honest:

- **One line, easy to recommit:** add a `# betterleaks:allow` comment on that line (use the language's comment syntax) and amend/recommit.
- **Already committed, not worth rewriting:** append the finding's fingerprint (shown in the block message as `fp=...`) as one line to `.betterleaksignore` at the repo root.
- **A recurring pattern** (test fixtures, example configs, generated files): add a path or regex allowlist to `.betterleaks.toml` at the repo root, e.g.

  ```toml
  [extend]
  useDefault = true

  [allowlist]
  paths = ['''testdata/''', '''.*\.example$''']
  ```

Both files are ordinary committed files. Commit them with a message that says what was allowlisted and why, so reviewers can check it.

## 4. Push again

Run the same push command. The gate re-scans the pending range; a clean scan produces no output.

## Bypass

`GOX_GUARD_SKIP=1 git push ...` skips the gate. Use it only when the user explicitly asks for it, and say in your reply that the push went out unscanned.

## What the gate does not cover

It only sees pushes run from this Claude session. Pushes typed in a terminal and CI are outside it; the repository's CI remains the last hard gate.
