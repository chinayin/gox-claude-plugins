# 使用手册 — gox-code-rules

> 总览 / 为什么用它 → 见 [`README.md`](README.md)。本手册讲**细节**:怎么启用、怎么用、怎么问、没触发怎么办。

团队代码规范以 **Claude Code 技能(Agent Skills)** 的形式分发:写/设计代码时按需自动加载规范,对你的 repo 零写入。

---

## 1. 启用

### 团队 repo(推荐,project-scope)
把 `templates/project-settings.json` 的内容并入该 repo 的 `.claude/settings.json` 并提交:

```json
{
  "extraKnownMarketplaces": {
    "chinayin": { "source": { "source": "github", "repo": "chinayin/gox-claude-plugins" } }
  },
  "enabledPlugins": ["gox-code-rules@chinayin"]
}
```

协作者信任该 repo 文件夹后,Claude Code 会提示安装/启用本插件 → **仅该 repo 生效**。

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
| 通用工程准则 | `/gox-code-rules:engineering` | 描述匹配即可(无文件限定) | Karpathy 行为准则:先想后写、简单优先、外科手术式改动、目标驱动 |
| Go 规范 | `/gox-code-rules:go` | **正在动 Go 文件**(`**/*.go, go.mod, go.work, go.sum`)**且**任务相关 | Go 架构/编码 + CLI(cobra)/配置(gox/config)/迁移(goose)/脚手架,正文在 `references/` 按需读 |
| 前端规范 | `/gox-code-rules:frontend` | 正在动前端文件(`*.tsx/*.jsx/*.vue/*.ts/*.js/*.css/*.scss` 等)**且**任务相关 | React/Vue/TS/JS/样式/状态管理(**骨架,正文 TODO 待填**) |

**触发机制(重要)**:技能 `paths` 是**闸门**——给 `go` 技能加了 `paths`,意味着它**只在你正在编辑/处理 Go 文件时**才会被自动考虑;光在聊天里提"Go"但还没动 `.go` 文件,可能不会自动加载(见 §4)。`engineering` 没有 `paths`,描述匹配就能触发。

> 触发是**模型判断 + 闸门**两层,本质带概率(实测真实编码场景约 2/3 命中)。要保证在场,直接手动调用(见 §4)。

---

## 3. 怎么问(能稳定激活的话术)

句子里**显式带上语言/框架/工具词**,命中率明显更高:

| 你想做 | 这样问 | 会用到 |
|---|---|---|
| 加命令行参数 | `用 cobra 给 cmd/server 加个 --port flag` | go → `references/cli.md` |
| 读配置 | `这个服务从配置里读 PORT,用 gox/config` | go → `references/config.md` |
| 数据库迁移 | `用 goose 给 users 表加一版迁移` | go → `references/db-migrations.md` |
| 新建项目骨架 | `给这个 Go 项目补齐 Makefile / golangci / CI` | go → `references/scaffold.md` |
| 写业务代码 | `给这个 handler 加上超时和错误包装` | go → `references/rules.md` |
| 写前端组件 | `给这个 React 组件加个 loading 状态` | frontend |
| 设计/重构前 | `我们先想清楚这个模块怎么拆` | engineering |

---

## 4. 没触发怎么办

1. **直接手动调用**——最可靠:`/gox-code-rules:go` 或 `/gox-code-rules:engineering`,绕过一切判断强制加载。
2. **设计期盲区**:还没动 `.go` 文件、只是在讨论方案时,`go` 技能可能不自动弹。对策:① 句子里点明语言/框架;② 或先手动 `/gox-code-rules:go` 再开聊。
3. 每次会话开始会有一条 `[gox-code-rules]` 提示(SessionStart),推动模型主动使用规范技能;它只是提示,模型仍可能忽略——拿不准就回到第 1 条。

---

## 5. 强制力说明

技能是会话内的**软引导**(模型按需加载,可能不触发,可能不完全遵守)。**真正的强制以仓库的 `golangci-lint` / CI / PR review 为准**——规范能不能落地,最终看硬层,不看技能是否触发。

---

## 6. 以后加语言/领域

一语言(领域)一技能,同一插件内并存(如已有 `skills/frontend/`),各自带 `description` + `paths` + `references/`。模型按"正在动哪种文件 / 任务"自动挑对应技能。详见 `docs/DESIGN.md`。
