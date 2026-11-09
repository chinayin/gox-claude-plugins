# Codex 兼容范围与待验证事项

更新于 2026-11-09。安装发现记录来自 Codex CLI 0.155.1；token-thrift 的原生调度策略已补充，验证范围单列于下文。不同层面的验证不能相互替代。

## 直接复用

Codex 使用同一个 `chinayin` marketplace，直接读取现有 Claude 格式插件。规范、脚本和版本保持一份，不新增独立 marketplace、构建产物或仅为安装而增加的覆盖清单。安装命令见 [中文 README](../README.zh-CN.md#安装到-codex) / [English README](../README.md#install-in-codex)。

Codex 的 marketplace 与启用配置独立于 Claude。`templates/project-settings.json` 是 Claude 模板，不用于 Codex；在 Claude 中安装插件也不会替 Codex 完成安装。

| 插件 | 已有验证 | 未完成的验证 / 限制 |
|---|---|---|
| `gox-code-rules` | 可直接安装，能发现五个技能和 SessionStart / SubagentStart hooks | 受信任会话中的提醒执行、技能触发和规则采纳未完成端到端验证；frontend 仍是占位内容 |
| `gox-guard` | 可直接安装，能发现依赖检查与 PreToolUse hooks | 真实 Codex 会话中的 push 阻断未完成端到端验证；脚本测试不等同于运行时拦截验证 |
| `diagram-design` | 通过完整 Git URL 可安装 | 生成、导入、导出等运行效果未完整验证；上游审计对应特定提交，见 [第三方登记](THIRD_PARTY.md) |
| `token-thrift` | 只读 `plugin/read` 能发现 delegate 技能；0.1.3 在共享技能中增加原生子代理与模型选择规则 | 需要客户端暴露子代理与模型选择能力；不依赖 Claude 代理注册；安装发现不证明模型路由已执行 |

## Hooks 与技能边界

安装或启用插件不会自动信任 hooks。在 Codex 的 `/hooks` 中审阅并信任当前定义，再开启新会话。hooks 需要 Bash、jq；`gox-guard` 还需要 Git、betterleaks。Codex 兼容 `CLAUDE_PLUGIN_ROOT`，但环境变量和协议兼容不能代替实际执行验证。参见[官方插件文档](https://developers.openai.com/plugins/build/plugins)与 [hook 信任说明](https://learn.chatgpt.com/docs/hooks)。

规范提醒使用共享技能名；无 Skill 工具时要求读取已安装的 SKILL.md 与相关 references，宿主省略插件前缀时用裸名。技能不可用时再遵循任务说明。能发现该 hook，不代表它在 Codex 中能同样有效地引导技能加载。当前不通过 `"hooks": {}` 关闭提醒；若实际出现兼容问题，先复现，再做针对性修改。

guard 只检查匹配到的工具调用。不要将安装成功或一次阻断成功描述为覆盖所有 shell 执行方式；间接脚本、别名和后续交互输入等还需单独考虑。仓库 CI 继续负责其自身的检查。

## token-thrift：原生子代理调度

安装同一个 `token-thrift` 插件后，Codex 读取共享 `delegate` 技能，使用原生子代理接口并显式选择模型。Claude 的 `agents/*.md` 和 Cursor 的 `agents-cursor/*.md` 仍分别服务各自平台；Codex 的角色通过任务说明传递，不新增代理文件或打包入口。

模型选择先尊重用户对委派任务的指定，否则按经济读取 / 可靠写入的任务档位，从当前工具或客户端暴露的模型中选择足够胜任且价格较低的模型。Luna / Sol 是类别示例，不是 Haiku / Sonnet 的能力等价物，也不是可直接传入的别名；技能不维护固定模型 ID 或自动升级“最新版本”的映射表。

原生调用按实际 schema 传递模型参数；支持 `fork_turns` 的工具使用 `"none"` 和独立任务说明，避免复制整个主会话，也满足该接口的模型覆盖条件。任务说明包含源文件、工作目录、规范位置、权限边界和返回要求；没有 Skill 工具时直接读取相关 SKILL.md。未指定模型可能继承父模型，因此“成功创建子代理”不等于“使用低价模型”。接口不可用、无合适低价模型或模型请求被拒绝时退回主线程，不写用户配置、不另起 CLI。

模型最终选择与配置优先级参见 [OpenAI 子代理文档](https://learn.chatgpt.com/docs/agent-configuration/subagents)，当前模型定位参见[模型选择](https://learn.chatgpt.com/docs/model-selection)。实际模型以宿主元数据为准，无法观测时应说明，不能用代理自报代替。订阅额度与 API 费用也不能直接换算，见[用量说明](https://learn.chatgpt.com/docs/pricing)。

“只返回结论、减少主上下文重复读取”不保证总 token 或费用下降。文字上的只读要求不等于只读沙箱；Codex 的权限来自宿主，现有 Claude cheap-reader 的 Bash 也不能仅凭未列出 Write/Edit 就声称不能写盘。

场景评估见 [delegate-eval](../plugins/token-thrift/tests/delegate-eval.md)，与 Bats 结构检查分开记录。尚需在从 marketplace 安装的干净客户端中验证自动触发与完整模型路由，并测量真实任务的质量和费用。

## 下一次验收

1. 记录目标 Codex 版本、插件版本及源提交，确认安装副本中的技能和 hooks 可发现。
2. 在已审阅信任的主会话与子代理会话中，验证提醒注入、技能读取和 references 加载。
3. 在临时 Git 仓库与本地 remote 上验证 guard：干净提交、模拟扫描命中、依赖缺失与扫描器报错；确认目标 push 是否实际发生，无需向外部仓库推送。
4. 对 token-thrift 验证安装副本的技能触发、实际模型、权限及摘要返回；记录费用与质量后再评估收益。

原兼容评估中的 YAML 和缺失 Python 技能声明问题已由 `gox-code-rules` 0.8.1 修复，见 [CHANGELOG](../CHANGELOG.md)。独立打包 [#12](https://github.com/chinayin/gox-claude-plugins/pull/12) 与关闭规则 hooks 的覆盖清单 [#13](https://github.com/chinayin/gox-claude-plugins/pull/13) 已于 2026-10-09 关闭，不属于待合入方案。
