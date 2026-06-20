# gox-claude-plugins

团队内部 Claude Code 规范插件 marketplace(marketplace 名:`chinayin`)。
采用 **Agent Skills** 方案:规范以技能形式按需加载,写代码时自动激活,对你的 repo 零写入。

> **怎么用 / 怎么问 / 没触发怎么办** → 见 [`USAGE.md`](USAGE.md)。

## 插件
- `gox-code-rules` — 团队代码规范:
  - `engineering` 技能:通用工程行为准则(Karpathy)。
  - `go` 技能:Go 架构与编码规范;`paths` 限定在处理 Go 文件时自动激活,
    细节按 `references/`(rules/cli/config/db-migrations/scaffold)渐进加载。
  - 薄 `SessionStart` 提示:每会话提示模型"写/设计代码用上述技能"(只提示、不含规则正文),
    兜住技能偶尔欠触发与设计期。fail-open,绝不阻断会话。

## 在一个团队 repo 启用(project-scope,推荐)
把 `templates/project-settings.json` 的内容并入该 repo 的 `.claude/settings.json` 并提交。
协作者信任该 repo 文件夹后,Claude Code 会提示安装/启用本插件 → 仅该 repo 生效。

## 手动试用
```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/reload-plugins
```
在含 `.go` 的项目里编辑 Go 文件或规划 Go 模块,`go` 技能会被自动调用。

## 强制力说明
技能是会话内的**软引导**(模型按需加载,可能不触发);**真正的强制以 `golangci-lint` / CI / PR review 为准**。

## 开发
- 校验清单(JSON):`brew install jq bats-core && bats tests/`
- 技能触发率:用 skill-creator 的 eval 流程评估 `go` 技能在真实 Go 任务下的自动激活率。
