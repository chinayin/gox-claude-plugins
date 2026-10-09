# 使用手册 — gox-code-rules

> 总览 / 为什么用它 → 见 [`README.md`](README.md)。本手册讲**细节**:怎么启用、怎么用、怎么问、没触发怎么办。

本文的安装配置和调用方式针对 Claude Code。Codex 的安装与验证边界见 [docs/CODEX.md](docs/CODEX.md)。

团队代码规范以 **Claude Code 技能(Agent Skills)** 的形式分发，由模型按任务选择或用户显式调用；插件不向你的 repo 写入规范文件。

---

## 1. 启用

### 团队 repo(推荐,project-scope)
把 [项目模板](templates/project-settings.json) 并入该 repo 的 `.claude/settings.json` 并提交。完整模板启用三个本地插件；下面是只启用代码规范的最小示例：

```json
{
  "extraKnownMarketplaces": {
    "chinayin": { "source": { "source": "github", "repo": "chinayin/gox-claude-plugins" } }
  },
  "enabledPlugins": {
    "gox-code-rules@chinayin": true
  }
}
```

`enabledPlugins` 是插件 ID 到布尔值的对象。项目配置声明该 repo 的启用范围；协作者仍需各自安装并信任插件，不会因提交配置而自动完成安装。已有其他插件配置时合并键值，不要覆盖整个对象。参见[官方配置参考](https://code.claude.com/docs/en/settings-reference#enabledplugins)。

### 手动试用(单机)
```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/reload-plugins        # 确认 /plugin 列表里有它、无 Errors
```

---

## 2. 有哪些技能、何时触发

| 技能 | 调用名 | 自动触发条件 | 内容 |
|---|---|---|---|
| 通用工程准则 | `/gox-code-rules:engineering` | nudge + 描述匹配(无文件限定) | Karpathy 行为准则:先想后写、简单优先、外科手术式改动、目标驱动 |
| Go 规范 | `/gox-code-rules:go` | 任务涉及 Go(nudge + description 驱动模型自调;`paths` 仅为声明,见下) | Go 架构/编码 + CLI(cobra)/配置(gox/config)/迁移(goose)/脚手架,正文在 `references/` 按需读 |
| 前端规范 | `/gox-code-rules:frontend` | 前端任务，通过 description 引导模型调用 | React/Vue/TS/JS/样式/状态管理(**骨架,正文 TODO 待填**) |
| Shell 规范 | `/gox-code-rules:shell` | 任务涉及 Shell 脚本(机制同上) | bash/CLI 脚本约定:stdout·stderr 分流、状态前缀、标准 flag、退出码、`test.sh` 自测(单文件 SKILL.md,无 references) |
| 技能编写规范 | `/gox-code-rules:skill` | 任务涉及写或改 SKILL.md(机制同上) | 命名(一个词是规则集;多词一律对象-动作;不带版本后缀)、正文默认英文、环境事实不入技能;编写过程交给官方 skill-creator,不复述(单文件 SKILL.md,无 references) |

**触发机制(重要)**:实测(见 `docs/MVP_FINDINGS.md`,CC 2.1.183)技能加载由模型**显式调用 Skill 工具**驱动,推动力是两层——每会话/子代理注入的 `[gox-code-rules]` 提示(nudge)+ 技能 `description`。设计期(还没动任何文件)同样能触发。frontmatter 的 `paths` 是声明性字段,实测**未观察到**"按文件自动注入"生效,不要把它当成触发保证。

> 触发带有不确定性；历史的“2/3”仅来自三个任务，不能当作当前稳定命中率。需要明确加载时，直接手动调用(见 §4)。

---

## 3. 怎么问(帮助模型识别适用技能)

句子里**显式带上语言/框架/工具词**，让任务与技能描述的关联更清楚；仍不保证每次自动加载：

| 你想做 | 这样问 | 会用到 |
|---|---|---|
| 写 HTTP 接口 | `给 /v1/users 加个列表端点` / `这个 handler 怎么取路径参数` | go → `references/http.md` |
| 迁到 gin | `把这个 net/http 的服务迁到 gin` | go → `references/http.md`(末节) |
| 加命令行参数 | `用 cobra 给 cmd/server 加个 --port flag` | go → `references/cli.md` |
| 读配置 | `这个服务从配置里读 PORT,用 gox/config` | go → `references/config.md` |
| 数据库迁移 | `用 goose 给 users 表加一版迁移` | go → `references/db-migrations.md` |
| 时间列/时区 | `新表的时间列用 DATETIME 还是 epoch` / `这个 upsert 的 updated_at 没更新` | go → `references/time-and-timezone.md` |
| 新建项目骨架 | `给这个 Go 项目补齐 Makefile / golangci / CI` | go → `references/scaffold.md` |
| 写业务代码 | `给这个 handler 加上超时和错误包装` | go → `references/rules.md` |
| 写前端组件 | `给这个 React 组件加个 loading 状态` | frontend |
| 设计/重构前 | `我们先想清楚这个模块怎么拆` | engineering |

---

## 4. 没触发怎么办

1. **直接手动调用**——最可靠:`/gox-code-rules:go` 或 `/gox-code-rules:engineering`,绕过一切判断强制加载。
2. **设计期也能触发**:实测无 `.go` 文件、纯聊设计时,nudge 也能推动模型调起技能——但同样带概率。漏了就:① 句子里点明语言/框架;② 或先手动 `/gox-code-rules:go` 再开聊。
3. 每次会话开始会有一条 `[gox-code-rules]` 提示(SessionStart),推动模型主动使用规范技能;从 0.2.0 起,子代理也会收到提示(SubagentStart;0.4.0 起对 token-thrift 的纯只读 `cheap-reader` 跳过注入;0.6.0 起子代理收到的是更短的"以 brief 为准"版本——主会话已把规范写进 brief 时,子代理不再重复加载技能)。它只是提示,模型仍可能忽略——拿不准就回到第 1 条。

---

## 5. 强制力说明

技能是会话内的**软引导**(模型按需加载,可能不触发,可能不完全遵守)。**真正的强制以仓库的 `golangci-lint` / CI / PR review 为准**——规范能不能落地,最终看硬层,不看技能是否触发。

---

## 6. 以后加语言/领域

一语言(领域)一技能,同一插件内并存(如已有 `skills/frontend/`),各自带 `description` + `paths` + `references/`。模型按"正在动哪种文件 / 任务"自动挑对应技能。详见 `docs/DESIGN.md`。
