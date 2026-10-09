# Codex 兼容范围与待验证事项

文档整理于 2026-10-09。下表汇总仓库在 Codex CLI 0.155.1 上的已有验证记录；本次整理没有重新运行安装或模型会话测试，不代表其他版本已获同等验证。

## 直接复用

Codex 使用同一个 `chinayin` marketplace，直接读取现有 Claude 格式插件。规范、脚本和版本保持一份，不新增独立 marketplace、构建产物或仅为安装而增加的覆盖清单。安装命令见 [中文 README](../README.zh-CN.md#在-codex-中使用) / [English README](../README.md#use-with-codex)。

Codex 的 marketplace 与启用配置独立于 Claude。`templates/project-settings.json` 是 Claude 模板，不用于 Codex；在 Claude 中安装插件也不会替 Codex 完成安装。

| 插件 | 已有验证 | 未完成的验证 / 限制 |
|---|---|---|
| `gox-code-rules` | 可直接安装，能发现五个技能和 SessionStart / SubagentStart hooks | 受信任会话中的提醒执行、技能触发和规则采纳未完成端到端验证；frontend 仍是占位内容 |
| `gox-guard` | 可直接安装，能发现依赖检查与 PreToolUse hooks | 真实 Codex 会话中的 push 阻断未完成端到端验证；脚本测试不等同于运行时拦截验证 |
| `diagram-design` | 通过完整 Git URL 可安装 | 生成、导入、导出等运行效果未完整验证；上游审计对应特定提交，见 [第三方登记](THIRD_PARTY.md) |
| `token-thrift` | 只读 `plugin/read` 能发现 delegate 技能 | 尚未完成适配；技能发现不证明 Claude 代理已注册、可调用或能选择低成本模型 |

## Hooks 与技能边界

安装或启用插件不会自动信任 hooks。在 Codex 的 `/hooks` 中审阅并信任当前定义，再开启新会话。hooks 需要 Bash、jq；`gox-guard` 还需要 Git、betterleaks。Codex 兼容 `CLAUDE_PLUGIN_ROOT`，但环境变量和协议兼容不能代替实际执行验证。参见[官方插件文档](https://developers.openai.com/plugins/build/plugins)与 [hook 信任说明](https://learn.chatgpt.com/docs/hooks)。

规范提醒仍包含 Claude Skill 工具和调用方式的措辞，并在 Skill 工具不可用时回退到任务说明。能发现该 hook，不代表它在 Codex 中能同样有效地引导技能加载。当前不通过 `"hooks": {}` 关闭提醒；若实际出现兼容问题，先复现，再做针对性修改。

guard 只检查匹配到的工具调用。不要将安装成功或一次阻断成功描述为覆盖所有 shell 执行方式；间接脚本、别名和后续交互输入等还需单独考虑。仓库 CI 继续负责其自身的检查。

## token-thrift：尚未实施的适配方向

当前 delegate 技能使用 Claude 的 `Task/Agent`、`subagent_type` 和 Haiku / Sonnet，两个 `agents/*.md` 也使用 Claude 模型别名及工具列表。这些声明不能直接视为 Codex 的模型路由和权限配置。

若后续适配，优先修改同一个 delegate 技能：保留 Claude 路径，按 Codex 当时可用的代理接口传递任务与摘要要求；仅在能明确选择低成本模型时宣称低成本路由。代理不可用、模型不可选或任务过小时应有明确处理方式，不新增独立打包系统。

“只返回结论、减少主上下文重复读取”仍有复用价值，但不保证总 token 或费用下降。文字上的只读要求不等于只读沙箱；现有 cheap-reader 允许 Bash，也不能仅凭未列出 Write/Edit 就声称不能写盘。只有需要强制角色权限时，再评估客户端的代理配置能力。

## 下一次验收

1. 记录目标 Codex 版本、插件版本及源提交，确认安装副本中的技能和 hooks 可发现。
2. 在已审阅信任的主会话与子代理会话中，验证提醒注入、技能读取和 references 加载。
3. 在临时 Git 仓库与本地 remote 上验证 guard：干净提交、模拟扫描命中、依赖缺失与扫描器报错；确认目标 push 是否实际发生，无需向外部仓库推送。
4. 若适配 token-thrift，验证实际代理、模型、权限及摘要返回；记录费用与质量后再评估收益。

原兼容评估中的 YAML 和缺失 Python 技能声明问题已由 `gox-code-rules` 0.8.1 修复，见 [CHANGELOG](../CHANGELOG.md)。独立打包 [#12](https://github.com/chinayin/gox-claude-plugins/pull/12) 与关闭规则 hooks 的覆盖清单 [#13](https://github.com/chinayin/gox-claude-plugins/pull/13) 已于 2026-10-09 关闭，不属于待合入方案。
