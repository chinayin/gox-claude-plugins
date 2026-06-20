# gox-code-rules MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个最小可用的 Claude Code 插件 `gox-code-rules`,在团队 Go repo 的会话启动时把团队规范注入上下文,用于验证「采纳率 / token 成本 / 作用域」三个核心假设。

**Architecture:** 一个 marketplace monorepo(`gox-claude-plugins`),内含单插件 `gox-code-rules`。MVP 只用**一个 SessionStart hook**(纯 bash),拼接 `rules/common/*.md` +(当 repo 有 `go.mod` 时)`rules/go/rules.md`,经 `hookSpecificOutput.additionalContext` 注入。对用户 repo 零写入。作用域靠 **project-scope 启用**(团队 repo 提交 `.claude/settings.json`),不做运行时闸门。

**Tech Stack:** Bash、jq(JSON 构造/校验)、bats-core(hook 测试)、Claude Code plugin/marketplace 机制。

## Global Constraints

- 工作目录:`/Users/tian/Sites/github/chinayin/golibs/gox-claude-plugins`(已存在,尚非 git repo)。
- **失败策略 fail-open**:hook 任何错误路径(缺 jq、缺 rules、读失败)一律 `exit 0` 无输出;**绝不 `exit 2`**(exit 2 会阻断用户编辑)。
- **可观测性**:`GOX_RULES_DEBUG` 非空时,把决策日志打到 **stderr**(不污染 stdout 的 JSON)。
- **零副作用**:不写用户 repo 任何文件;无规则可注入时静默 `exit 0`。
- **路径定位**:`PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"`;`PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"`。
- 依赖:`jq`、`bats`(`brew install jq bats-core`)。
- 规则正文唯一来源 = 本插件 `rules/`,不复制到别处。
- MVP **不做** PreToolUse 路由、不做去重、不做二进制、不做 project-local scope(均为 P1/P2)。

---

### Task 1: 仓库与 marketplace/plugin 清单

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/gox-code-rules/.claude-plugin/plugin.json`
- Create: `.gitignore`
- Test: `tests/manifests.bats`

**Interfaces:**
- Produces: marketplace 名 `chinayin`;插件名 `gox-code-rules`,源 `./plugins/gox-code-rules`。后续任务的 hook/rules 都放在 `plugins/gox-code-rules/` 下。

- [ ] **Step 1: 初始化 git 仓库**

Run:
```bash
cd /Users/tian/Sites/github/chinayin/golibs/gox-claude-plugins
git init
```
Expected: `Initialized empty Git repository ...`

- [ ] **Step 2: 写 `.gitignore`**

Create `.gitignore`:
```gitignore
.DS_Store
*.log
```

- [ ] **Step 3: 写失败测试 `tests/manifests.bats`**

Create `tests/manifests.bats`:
```bash
#!/usr/bin/env bats

@test "marketplace.json is valid and names chinayin + gox-code-rules" {
  run jq -e '.name == "chinayin" and (.plugins | map(.name) | index("gox-code-rules") != null)' .claude-plugin/marketplace.json
  [ "$status" -eq 0 ]
}

@test "marketplace plugin source is the relative path ./plugins/gox-code-rules" {
  run jq -er '.plugins[] | select(.name=="gox-code-rules") | .source' .claude-plugin/marketplace.json
  [ "$status" -eq 0 ]
  [ "$output" = "./plugins/gox-code-rules" ]
}

@test "plugin.json is valid and names gox-code-rules" {
  run jq -e '.name == "gox-code-rules"' plugins/gox-code-rules/.claude-plugin/plugin.json
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 4: 运行测试,确认失败**

Run: `bats tests/manifests.bats`
Expected: FAIL(文件不存在 / jq 报错)。

- [ ] **Step 5: 写 `.claude-plugin/marketplace.json`**

```json
{
  "name": "chinayin",
  "owner": { "name": "chinayin", "url": "https://github.com/chinayin" },
  "plugins": [
    {
      "name": "gox-code-rules",
      "source": "./plugins/gox-code-rules",
      "description": "团队统一代码规范:会话启动注入团队规范(MVP:common + Go)"
    }
  ]
}
```

- [ ] **Step 6: 写 `plugins/gox-code-rules/.claude-plugin/plugin.json`**

```json
{
  "name": "gox-code-rules",
  "version": "0.0.1",
  "description": "团队统一代码规范(MVP:SessionStart 注入 common + Go 规范)",
  "author": { "name": "chinayin" }
}
```

- [ ] **Step 7: 运行测试,确认通过**

Run: `bats tests/manifests.bats`
Expected: 3 tests PASS。

- [ ] **Step 8: 提交**

```bash
git add .gitignore .claude-plugin/marketplace.json plugins/gox-code-rules/.claude-plugin/plugin.json tests/manifests.bats
git commit -m "feat: 初始化 marketplace 与 gox-code-rules 插件清单"
```

---

### Task 2: SessionStart 注入 hook(核心,TDD)

**Files:**
- Create: `plugins/gox-code-rules/rules/common/karpathy-guidelines.md`(种子)
- Create: `plugins/gox-code-rules/rules/go/rules.md`(种子)
- Create: `plugins/gox-code-rules/hooks/inject-common.sh`
- Create: `plugins/gox-code-rules/hooks/hooks.json`
- Test: `tests/inject-common.bats`

**Interfaces:**
- Consumes: Task 1 的目录布局。
- Produces: `inject-common.sh` 读 `${CLAUDE_PLUGIN_ROOT}/rules/`,据 `${CLAUDE_PROJECT_DIR}/go.mod` 是否存在决定是否含 Go 规范,stdout 输出 `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":<string>}}` 且 `exit 0`;无内容则无输出 `exit 0`。

- [ ] **Step 1: 种子规则文件**

Create `plugins/gox-code-rules/rules/common/karpathy-guidelines.md`:
```markdown
# 团队通用准则(MVP 种子)

- 简单优先:最小可用实现,不做未要求的功能/抽象。
- 外科手术式改动:只改与需求直接相关的行。
- 中文回复;代码注释用中文;git 提交用中文(约定式前缀保留英文)。

> 注:本文件为 MVP 种子,正式内容后续从 gox-claude-standards 的 karpathy-guidelines.md 同步。
```

Create `plugins/gox-code-rules/rules/go/rules.md`:
```markdown
# Go 规范(MVP 种子)

- 包级不使用可变全局状态。
- 错误用包前缀包装,不用 fmt 打日志。
- 编辑前阅读对应领域规范(cli/config/db/scaffold)。

> 注:本文件为 MVP 种子,正式内容后续从 gox-claude-standards 的 rules.md 同步。
```

- [ ] **Step 2: 写失败测试 `tests/inject-common.bats`**

Create `tests/inject-common.bats`:
```bash
#!/usr/bin/env bats

setup() {
  PLUGIN="$BATS_TEST_DIRNAME/../plugins/gox-code-rules"
  HOOK="$PLUGIN/hooks/inject-common.sh"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN"
  GOREPO="$(mktemp -d)"; touch "$GOREPO/go.mod"
  NONGO="$(mktemp -d)"
}

teardown() { rm -rf "$GOREPO" "$NONGO"; }

@test "Go repo: 输出合法 JSON 且含 common 与 Go 规范" {
  export CLAUDE_PROJECT_DIR="$GOREPO"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "团队通用准则"
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "Go 规范"
}

@test "非 Go repo:含 common 不含 Go 规范" {
  export CLAUDE_PROJECT_DIR="$NONGO"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -er '.hookSpecificOutput.additionalContext' | grep -q "团队通用准则"
  run bash -c "bash '$HOOK' | jq -er '.hookSpecificOutput.additionalContext' | grep -c 'Go 规范' || true"
  [ "$output" = "0" ]
}

@test "fail-open:rules 目录缺失也 exit 0 无崩溃" {
  export CLAUDE_PLUGIN_ROOT="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$GOREPO"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "绝不 exit 2" {
  export CLAUDE_PROJECT_DIR="$GOREPO"
  run bash "$HOOK"
  [ "$status" -ne 2 ]
}

@test "GOX_RULES_DEBUG 把日志写 stderr 不污染 stdout JSON" {
  export CLAUDE_PROJECT_DIR="$GOREPO" GOX_RULES_DEBUG=1
  run bash -c "bash '$HOOK' 2>/dev/null | jq -e '.hookSpecificOutput'"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 3: 运行测试,确认失败**

Run: `bats tests/inject-common.bats`
Expected: FAIL("$HOOK" 不存在)。

- [ ] **Step 4: 写 `plugins/gox-code-rules/hooks/inject-common.sh`**

```bash
#!/usr/bin/env bash
# SessionStart hook: 注入团队规范(MVP)。fail-open,绝不 exit 2。
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

dbg() { [ -n "${GOX_RULES_DEBUG:-}" ] && echo "gox: $*" >&2 || true; }

# 缺 jq → fail-open
if ! command -v jq >/dev/null 2>&1; then
  dbg "jq 缺失,fail-open"
  exit 0
fi

context=""
append_file() {
  [ -f "$1" ] || { dbg "跳过(不存在): $1"; return; }
  context+="$(cat "$1")"$'\n\n'
  dbg "已纳入: $1"
}

# common:全部
shopt -s nullglob
for f in "$PLUGIN_ROOT"/rules/common/*.md; do append_file "$f"; done
shopt -u nullglob

# Go:仅当 repo 有 go.mod
if [ -f "$PROJECT_DIR/go.mod" ]; then
  append_file "$PLUGIN_ROOT/rules/go/rules.md"
else
  dbg "无 go.mod,跳过 Go 规范"
fi

# 无内容 → 静默 exit 0
if [ -z "${context//[$'\n\t ']/}" ]; then
  dbg "无规则可注入"
  exit 0
fi

prefix=$'[gox-code-rules] 以下为团队规范,请在本会话中遵循:\n\n'
jq -n --arg ctx "${prefix}${context}" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' \
  || { dbg "jq 构造失败,fail-open"; exit 0; }
exit 0
```

- [ ] **Step 5: 写 `plugins/gox-code-rules/hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/inject-common.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: 赋可执行权限并运行测试**

Run:
```bash
chmod +x plugins/gox-code-rules/hooks/inject-common.sh
bats tests/inject-common.bats
```
Expected: 5 tests PASS。

- [ ] **Step 7: 校验 hooks.json 合法**

Run: `jq -e '.hooks.SessionStart' plugins/gox-code-rules/hooks/hooks.json`
Expected: 输出非空、exit 0。

- [ ] **Step 8: 提交**

```bash
git add plugins/gox-code-rules/rules plugins/gox-code-rules/hooks tests/inject-common.bats
git commit -m "feat: SessionStart 注入 hook(common + Go,fail-open)"
```

---

### Task 3: 启用模板与上线文档(project-scope 分发)

**Files:**
- Create: `templates/project-settings.json`
- Create: `README.md`
- Test: `tests/template.bats`

**Interfaces:**
- Consumes: Task 1 的 marketplace 名 `chinayin` 与插件名 `gox-code-rules`。
- Produces: 可直接拷进团队 repo `.claude/settings.json` 的片段,启用本插件。

- [ ] **Step 1: 写失败测试 `tests/template.bats`**

```bash
#!/usr/bin/env bats

@test "模板含 extraKnownMarketplaces 指向 chinayin 源" {
  run jq -e '.extraKnownMarketplaces.chinayin.source.repo == "chinayin/gox-claude-plugins"' templates/project-settings.json
  [ "$status" -eq 0 ]
}

@test "模板 enabledPlugins 开启 gox-code-rules@chinayin" {
  run jq -e '.enabledPlugins | index("gox-code-rules@chinayin") != null' templates/project-settings.json
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `bats tests/template.bats`
Expected: FAIL(文件不存在)。

- [ ] **Step 3: 写 `templates/project-settings.json`**

```json
{
  "extraKnownMarketplaces": {
    "chinayin": {
      "source": { "source": "github", "repo": "chinayin/gox-claude-plugins" }
    }
  },
  "enabledPlugins": ["gox-code-rules@chinayin"]
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `bats tests/template.bats`
Expected: 2 tests PASS。

- [ ] **Step 5: 写 `README.md`**

```markdown
# gox-claude-plugins

团队内部 Claude Code 规范插件 marketplace(marketplace 名:`chinayin`)。

## 插件
- `gox-code-rules` — 会话启动注入团队代码规范(MVP:common + Go)。

## 在一个团队 repo 启用(project-scope,推荐)
把 `templates/project-settings.json` 的内容并入该 repo 的 `.claude/settings.json` 并提交。
协作者信任该 repo 文件夹后,Claude Code 会提示安装/启用本插件 → 仅该 repo 生效。

## 手动试用
```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/reload-plugins
```

## 排错
- 设 `GOX_RULES_DEBUG=1` 启动 Claude Code,hook 决策日志会打到 stderr。
- hook 任何错误均 fail-open(编辑不受影响)。

## 开发
- 测试:`brew install jq bats-core && bats tests/`
```

- [ ] **Step 6: 提交**

```bash
git add templates/project-settings.json README.md tests/template.bats
git commit -m "feat: project-scope 启用模板与 README"
```

---

### Task 4: 端到端手工验收(MVP 假设验证)

**Files:** 无(手工验证;勾选即记录结果)。

**Interfaces:** Consumes: 全部前置任务产物。

- [ ] **Step 1: 本地加 marketplace 并安装**

Run(在 Claude Code 内):
```
/plugin marketplace add /Users/tian/Sites/github/chinayin/golibs/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/reload-plugins
```
Expected: 插件出现在 `/plugin` Installed 列表,无 Errors。

- [ ] **Step 2: 在一个 Go repo 开新会话,确认规范在场**

在含 `go.mod` 的 repo 打开新会话,问 Claude:「现在上下文里有团队规范吗?贴出 Go 规范前两条。」
Expected: 能复述 `[gox-code-rules]` 注入的 Go 规范内容。

- [ ] **Step 3: 在非 Go repo 确认不含 Go 规范**

在无 `go.mod` 的 repo 开会话,确认含 common、不含 Go 规范。

- [ ] **Step 4: 记录三项 MVP 假设的观测结果**

在 `docs/mvp-findings.md` 写下:① 模型对注入规范的采纳度(对比开启前后);② SessionStart 注入的每轮 token 成本(`/plugin` 详情页或 `/context`);③ 作用域是否只在已启用 repo 生效。
Expected: 三项均有结论。**据此决定是否进入 P1(PreToolUse 路由 + 去重)。**

- [ ] **Step 5: 提交验收记录**

```bash
git add docs/mvp-findings.md
git commit -m "docs: MVP 端到端验收与三假设观测结果"
```

---

## Self-Review

- **Spec coverage**:覆盖 DESIGN §11 MVP(SessionStart+bash+common/go、3 repo 验证三假设)、§Global fail-open + GOX_RULES_DEBUG、§5 project-scope 启用模板、§13 测试(bats)。**有意不覆盖** P1/P2(PreToolUse、去重、二进制、project-local、Managed force-enable、gox-prd)——按决策门,P1 仅在 MVP 证明不足时启动。
- **Placeholder scan**:无 TODO/TBD;每个代码步给出完整内容。规则文件标注为"MVP 种子",非占位(刻意的最小内容,Step 明确后续从 standards 同步)。
- **Type/名称一致**:marketplace 名 `chinayin`、插件名 `gox-code-rules`、源 `./plugins/gox-code-rules`、hook `inject-common.sh`、JSON 形 `hookSpecificOutput.{hookEventName,additionalContext}`、启用串 `gox-code-rules@chinayin` —— 全文一致。
