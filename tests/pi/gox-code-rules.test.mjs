// gox-code-rules 的 pi 扩展：在 system prompt 的 gox-code-rules 段放提醒。文案只属于 pi，
// 写在扩展里；技能目录归插件所有，所以这里校验文案点名的技能都真实存在——
// 插件那边改名或删技能时，这里先失败，不会悄悄指向不存在的技能。
// 运行：node --test tests/pi/*.test.mjs（make test 会一起跑）

import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import rules from "../../.pi/extensions/gox-code-rules.ts";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../..");
const skillsDir = join(repoRoot, "plugins/gox-code-rules/skills");

function load() {
  const handlers = {};
  rules({ on: (name, handler) => { handlers[name] = handler; } });
  return handlers;
}

async function section(sections = {}) {
  const event = { type: "before_agent_start", prompt: "hi", systemPrompt: "", systemPromptOptions: { cwd: repoRoot, sections } };
  const result = await load().before_agent_start(event, {});
  return { text: event.systemPromptOptions.sections["gox-code-rules"], sections: event.systemPromptOptions.sections, result };
}

test("root package.json declares the skills and the extension as a pi package", () => {
  const pkg = JSON.parse(readFileSync(join(repoRoot, "package.json"), "utf8"));
  assert.ok(pkg.keywords.includes("pi-package"));
  assert.ok(pkg.pi.skills.includes("./plugins/gox-code-rules/skills"));
  assert.ok(pkg.pi.extensions.includes("./.pi/extensions/gox-code-rules.ts"));
  for (const p of [...pkg.pi.skills, ...pkg.pi.extensions]) assert.ok(existsSync(join(repoRoot, p)), `missing ${p}`);
});

test("adds the reminder as the gox-code-rules system prompt section without replacing the prompt", async () => {
  const { text, result } = await section();
  assert.match(text, /^\[gox-code-rules\] /);
  assert.equal(result, undefined, "must not replace the whole system prompt");
});

test("every skill the reminder names exists in the plugin", async () => {
  const { text } = await section();
  const names = [...text.matchAll(/`([a-z-]+)` skill/g)].map((m) => m[1]);
  assert.ok(names.length >= 3, `too few skills named: ${names}`);
  for (const name of names) assert.ok(existsSync(join(skillsDir, name, "SKILL.md")), `unavailable skill: ${name}`);
  assert.ok(existsSync(join(skillsDir, "engineering", "SKILL.md")));
  assert.match(text, /`engineering`/);
});

test("uses pi's bare skill names and read-the-SKILL.md loading, not Claude's Skill tool", async () => {
  const { text } = await section();
  assert.match(text, /read its `SKILL\.md`/);
  assert.match(text, /usually exactly one/);
  assert.doesNotMatch(text, /gox-code-rules:/);
  assert.doesNotMatch(text, /Skill tool/);
});

test("keeps other extensions' sections", async () => {
  const { sections } = await section({ other: "x" });
  assert.equal(sections.other, "x");
});
