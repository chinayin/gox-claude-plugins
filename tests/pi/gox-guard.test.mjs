// gox-guard 的 pi 扩展：把 pi 的 tool_call / session_start 转给 plugins/gox-guard/hooks/secrets.sh，
// 再把脚本的 deny / 提示翻译回 pi。扫描逻辑本身由 secrets.bats 覆盖，这里只测翻译层。
// 扫描器用 GOX_GUARD_BIN 指向的 stub 模拟；git 操作只发生在临时目录里。
// 运行：node --test tests/pi/*.test.mjs（make test 会一起跑）

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import guard from "../../.pi/extensions/gox-guard.ts";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../..");

const FINDING =
  '[{"RuleID":"aws-access-key","File":"config.txt","StartLine":3,"Commit":"0123456789abcdef","Fingerprint":"0123456789abcdef:config.txt:aws-access-key:3"}]';

let tmp;
let repo;
let savedEnv;

function git(...args) {
  execFileSync("git", args, { stdio: "ignore" });
}

// 有远端、已推送一次、再多一个待推送提交的仓库
function makeRepo() {
  const remote = join(tmp, "remote.git");
  repo = join(tmp, "repo");
  git("init", "-q", "--bare", remote);
  git("init", "-q", "-b", "main", repo);
  git("-C", repo, "config", "user.email", "t@example.com");
  git("-C", repo, "config", "user.name", "t");
  writeFileSync(join(repo, "README.md"), "base\n");
  git("-C", repo, "add", "README.md");
  git("-C", repo, "commit", "-qm", "base");
  git("-C", repo, "remote", "add", "origin", remote);
  git("-C", repo, "push", "-q", "-u", "origin", "main");
  writeFileSync(join(repo, "config.txt"), "x=1\n");
  git("-C", repo, "add", "config.txt");
  git("-C", repo, "commit", "-qm", "ahead");
}

// stub 扫描器：按给定退出码退出，报告打到 stdout（模拟 -r -）
function stubScanner(code, report = "") {
  const bin = join(tmp, "betterleaks");
  writeFileSync(bin, `#!/usr/bin/env bash\nprintf '%s' '${report}'\nexit ${code}\n`);
  chmodSync(bin, 0o755);
  process.env.GOX_GUARD_BIN = bin;
}

// 只含 jq 的 PATH，确保系统上真装的 betterleaks 不会被找到
function pathWithoutScanner() {
  const binDir = join(tmp, "bin");
  mkdirSync(binDir);
  const jq = execFileSync("bash", ["-c", "command -v jq"], { encoding: "utf8" }).trim();
  symlinkSync(jq, join(binDir, "jq"));
  return `${binDir}:/usr/bin:/bin`;
}

function load() {
  const handlers = {};
  guard({ on: (name, handler) => { handlers[name] = handler; } });
  const notes = [];
  const ctx = { cwd: repo, hasUI: true, ui: { notify: (message, type) => notes.push({ message, type }) } };
  return { handlers, ctx, notes };
}

beforeEach(() => {
  savedEnv = { ...process.env };
  delete process.env.GOX_GUARD_BIN;
  delete process.env.GOX_GUARD_SKIP;
  tmp = mkdtempSync(join(tmpdir(), "gox-guard-pi-"));
  makeRepo();
});

afterEach(() => {
  process.env = savedEnv;
  rmSync(tmp, { recursive: true, force: true });
});

test("root package.json declares the guard extension as a pi package", () => {
  const pkg = JSON.parse(readFileSync(join(repoRoot, "package.json"), "utf8"));
  assert.ok(pkg.keywords.includes("pi-package"));
  assert.ok(pkg.pi.extensions.includes("./.pi/extensions/gox-guard.ts"));
  for (const p of pkg.pi.extensions) assert.ok(existsSync(join(repoRoot, p)), `missing ${p}`);
});

test("blocks a bash git push when the scanner reports a finding", async () => {
  stubScanner(1, FINDING);
  const { handlers, ctx } = load();
  const result = await handlers.tool_call({ type: "tool_call", toolName: "bash", input: { command: "git push" } }, ctx);
  assert.equal(result.block, true);
  assert.match(result.reason, /^\[gox-guard\/secrets\] Push blocked: 1 potential secret/);
  assert.match(result.reason, /aws-access-key {2}config\.txt:3/);
});

test("lets a bash git push through when the scan is clean", async () => {
  stubScanner(0);
  const { handlers, ctx } = load();
  const result = await handlers.tool_call({ type: "tool_call", toolName: "bash", input: { command: "git push" } }, ctx);
  assert.equal(result, undefined);
});

test("ignores tools other than bash", async () => {
  stubScanner(1, FINDING);
  const { handlers, ctx } = load();
  const result = await handlers.tool_call(
    { type: "tool_call", toolName: "write", input: { path: "x.sh", content: "git push" } },
    ctx,
  );
  assert.equal(result, undefined);
});

test("warns the user at session start when the scanner is missing", async () => {
  process.env.PATH = pathWithoutScanner();
  const { handlers, ctx, notes } = load();
  await handlers.session_start({ type: "session_start", reason: "startup" }, ctx);
  assert.equal(notes.length, 1);
  assert.equal(notes[0].type, "warning");
  assert.match(notes[0].message, /^\[gox-guard\/secrets\] .*betterleaks is not installed/);
});

test("stays silent at session start when dependencies are present", async () => {
  stubScanner(0);
  const { handlers, ctx, notes } = load();
  await handlers.session_start({ type: "session_start", reason: "startup" }, ctx);
  assert.deepEqual(notes, []);
});
