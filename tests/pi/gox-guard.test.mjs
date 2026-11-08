// gox-guard 的 pi 扩展：把 pi 的 tool_call / session_start 转给 plugins/gox-guard/hooks/secrets.sh，
// 再把脚本的 deny / 提示翻译回 pi。扫描规则由 secrets.bats / push-scope.bats 覆盖；这里测翻译层及安装包的范围解析。
// 扫描器用 GOX_GUARD_BIN 指向的 stub 模拟；git 操作只发生在临时目录里。
// 运行：node --test tests/pi/*.test.mjs（make test 会一起跑）

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

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

function load(extension = guard) {
  const handlers = {};
  extension({ on: (name, handler) => { handlers[name] = handler; } });
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
  // 保留 Node 的环境代理对象；替换整个对象会让 Node 26 子进程继承旧环境。
  for (const key of Object.keys(process.env)) {
    if (!(key in savedEnv)) delete process.env[key];
  }
  Object.assign(process.env, savedEnv);
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

test("still blocks when Cursor and Claude plugin roots are inherited", async () => {
  process.env.CURSOR_PLUGIN_ROOT = "/cursor";
  process.env.CLAUDE_PLUGIN_ROOT = "/claude";
  stubScanner(1, FINDING);
  const { handlers, ctx } = load();
  const result = await handlers.tool_call({ type: "tool_call", toolName: "bash", input: { command: "git push" } }, ctx);
  assert.equal(result?.block, true);
  assert.match(result.reason, /aws-access-key {2}config\.txt:3/);
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

// 按 pi 包布局复制扩展和完整插件，验证安装后仍能通过相对路径加载 lib。
async function installedGuard() {
  const installed = join(tmp, "installed package");
  mkdirSync(join(installed, ".pi/extensions"), { recursive: true });
  cpSync(join(repoRoot, "plugins/gox-guard"), join(installed, "plugins/gox-guard"), { recursive: true });
  const extension = join(installed, ".pi/extensions/gox-guard.ts");
  cpSync(join(repoRoot, ".pi/extensions/gox-guard.ts"), extension);
  return { installed, extension: (await import(pathToFileURL(extension).href)).default };
}

test("installed pi package scans a non-HEAD source via git -C and allows a clean source", async () => {
  git("-C", repo, "checkout", "-qb", "feature");
  writeFileSync(join(repo, "config.txt"), "REVIEW_SECRET\n");
  git("-C", repo, "commit", "-qam", "fixture");
  git("-C", repo, "checkout", "-q", "main");
  const scanner = join(tmp, "scope-scanner");
  writeFileSync(scanner, [
    "#!/usr/bin/env bash",
    'for arg in "$@"; do',
    '  case "$arg" in --log-opts=*) range="${arg#--log-opts=}" ;; esac',
    "done",
    "for commit in $(git rev-list $range); do",
    '  if git grep -q REVIEW_SECRET "$commit" --; then',
    "    printf '%s' '" + FINDING + "'",
    "    exit 1",
    "  fi",
    "done",
    "exit 0",
  ].join("\n") + "\n");
  chmodSync(scanner, 0o755);
  process.env.GOX_GUARD_BIN = scanner;
  const { extension } = await installedGuard();
  const { handlers, ctx } = load(extension);
  ctx.cwd = tmp;
  const push = (ref) => handlers.tool_call({
    type: "tool_call", toolName: "bash",
    input: { command: "git -C '" + repo + "' push origin " + ref },
  }, ctx);
  assert.equal((await push("feature"))?.block, true);
  assert.equal(await push("main"), undefined);
});

test("installed pi package denies when its scope helper is missing", async () => {
  stubScanner(0);
  const { installed, extension } = await installedGuard();
  rmSync(join(installed, "plugins/gox-guard/lib/push-scope.sh"));
  const { handlers, ctx } = load(extension);
  const result = await handlers.tool_call({ type: "tool_call", toolName: "bash", input: { command: "git push" } }, ctx);
  assert.equal(result?.block, true);
  assert.match(result.reason, /helper could not be loaded/);
});
