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
| 通用工程准则 | `/gox-code-rules:engineering` | nudge + 描述匹配(无文件限定) | Karpathy 行为准则:先想后写、简单优先、外科手术式改动、目标驱动 |
| Go 规范 | `/gox-code-rules:go` | 任务涉及 Go(nudge + description 驱动模型自调;`paths` 仅为声明,见下) | Go 架构/编码 + CLI(cobra)/配置(gox/config)/迁移(goose)/脚手架,正文在 `references/` 按需读 |
| 前端规范 | `/gox-code-rules:frontend` | 任务涉及前端(机制同上) | React/Vue/TS/JS/样式/状态管理(**骨架,正文 TODO 待填**) |
| Shell 规范 | `/gox-code-rules:shell` | 任务涉及 Shell 脚本(机制同上) | bash/CLI 脚本约定:stdout·stderr 分流、状态前缀、标准 flag、退出码、`test.sh` 自测(单文件 SKILL.md,无 references) |

**触发机制(重要)**:实测(见 `docs/mvp-findings.md`,CC 2.1.183)技能加载由模型**显式调用 Skill 工具**驱动,推动力是两层——每会话/子代理注入的 `[gox-code-rules]` 提示(nudge)+ 技能 `description`。设计期(还没动任何文件)同样能触发。frontmatter 的 `paths` 是声明性字段,实测**未观察到**"按文件自动注入"生效,不要把它当成触发保证。

> 触发本质带概率(实测真实编码场景约 2/3 命中)。要保证在场,直接手动调用(见 §4)。

---

## 3. 怎么问(能稳定激活的话术)

句子里**显式带上语言/框架/工具词**,命中率明显更高:

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
