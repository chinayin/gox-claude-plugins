# pi 兼容范围与待验证事项

文档整理于 2026-10-10，验证环境为 pi 1.1.0（`@earendil-works/pi-coding-agent`）、Node 24。

## 布局：pi 与 Claude / Codex 互不影响

pi 不读 `.claude-plugin/`。仓库根的 `package.json` 用 `pi` 字段声明 pi 包（`keywords` 含 `pi-package`），pi 以整个仓库为一个包安装。pi 专属文件只放在仓库根：

```text
package.json                      # pi 包声明（版本独立，见 CHANGELOG「pi 包」）
.pi/extensions/gox-code-rules.ts  # 提醒文案写在这里，技能取自 plugins/gox-code-rules/skills
.pi/extensions/gox-guard.ts       # 调用 plugins/gox-guard/hooks/secrets.sh
tests/pi/*.test.mjs               # node --test，make test 在 bats 之后一起运行
```

- `plugins/` 下没有任何 pi 文件。Claude / Codex 安装时把整个插件目录复制进各自的缓存，根目录的 `.pi/` 不在其中；它只出现在 marketplace 的仓库克隆里，与 README、docs 一样不被加载。
- 共享只有两处，且都是 pi 单向读取、插件侧不感知 pi：`gox-code-rules` 的 `skills/`（Agent Skills 规范，原样复用），`gox-guard` 的 `hooks/secrets.sh`（按 Claude hook 的输入输出约定调用）。插件侧改动若破坏了约定或删改了被点名的技能，`tests/pi/` 会失败。
- 在本仓库目录里运行 pi 并信任项目时，pi 会把 `.pi/extensions/` 当作项目扩展自动加载；若同时全局安装了本包，同一扩展会加载两次（guard 扫两遍、提醒段写同一个键），不影响结果。

```bash
pi install git:github.com/chinayin/gox-claude-plugins          # 个人安装，写入 ~/.pi/agent/settings.json
pi install git:github.com/chinayin/gox-claude-plugins --local  # 项目安装，写入 .pi/settings.json
pi -e ./                                                       # 本地调试：仅本次加载，不写配置
```

只要其中一部分时，在 settings 的 `packages` 里用对象形式筛选，参见 pi 文档 `packages.md` 的 Select package resources。

## 各插件状态

| 插件 | pi 中的形态 | 状态 |
|---|---|---|
| `gox-code-rules` | `pi.skills` 交出插件的 `skills/`；`.pi/extensions/gox-code-rules.ts` 把提醒写入 system prompt | 已实现 |
| `gox-guard` | `.pi/extensions/gox-guard.ts`：`tool_call`（bash）与 `session_start` 转给插件的 `secrets.sh` | 已实现 |
| `token-thrift` | 依赖 Claude 的子代理与模型别名 | 未适配 |
| `diagram-design` | 第三方仓库，不进本包；需要时单独 `pi install` 其仓库 | 不处理 |

## gox-code-rules

- 技能：pi 实现 Agent Skills 规范，`skills/` 原样加载，SKILL.md 与 `references/` 不做 pi 专用改写。
- 提醒：扩展在 `before_agent_start` 把文案写入 `systemPromptOptions.sections["gox-code-rules"]`。不用 superpowers 那种 `context` 事件插 user 消息：`context` 的改动只对单次请求生效，pi 随后会还原；system prompt 段跨轮次、跨压缩保留，文案不变时 pi 不重发。
- 文案只属于 pi，与插件的 `hooks/session-nudge.sh`（Claude / Codex 共用）互不引用。pi 的技能没有插件命名空间，也没有 Skill 工具，所以用裸名（`go` / `shell` / `skill` / `engineering`），加载方式写作"读 `SKILL.md`，再只读它指向的 `references/`"。改提醒的路由规则时，Claude 版与 pi 版需各改一处。

## gox-guard

扩展把 pi 事件转成 Claude hook 的 stdin 形状调用 `secrets.sh`，再把输出翻译回 pi：

- `tool_call` 且工具为 `bash`：脚本给出 `permissionDecision=deny` 时返回 `{ block: true, reason }`，模型收到与 Claude 中相同的拦截说明。
- `session_start`：缺 jq / betterleaks 时用 `ctx.ui.notify` 提示用户（无 UI 的模式下不提示，push 时仍会被拦）。
- 脚本调用失败（超时、bash 不可用）时不吞错误，由 pi 按 handler 出错拦下这次调用，与脚本的 fail-closed 一致。

扫描逻辑不在 TS 里另写一份：安全闸门的正则与 fail-closed 规则两处维护容易漂移。依赖与 Claude 相同：Bash、jq、Git、betterleaks；逃生口仍是 `GOX_GUARD_SKIP=1`。扩展只看 `bash` 工具，不覆盖用户在 pi 中用 `!` 直接执行的命令（那是用户自己的操作），也不覆盖 `powershell` 工具。

## 已做的验证

- `make test`：bats 与 `tests/pi/`（翻译层、接线、提醒点名的技能均存在）。
- 真实 pi 会话，guard：临时仓库 + 本地 bare remote，待推送提交含伪造的 GitHub token，`pi -ne -e <仓库> -t bash -p '…git push origin main'`；bash 调用被拦下（`isError: true`，原因含 `github-pat config.py:1`），remote 未更新。另以 `pi -e git:github.com/chinayin/gox-claude-plugins@<分支>` 从 git 源单次加载，结果一致。
- 真实 pi 会话，code-rules：默认模型，`pi -ne -e <仓库> -t read,write,edit,bash -p '写一个读 PORT 环境变量的 HTTP 服务 main.go'`，两次运行都先读 `skills/go/SKILL.md`，再读 `references/` 下的 rules / config / http 后写代码。样本只有两次，不代表命中率；也未与"无提醒、只有技能"的基线对比。

## 待验证 / 后续

1. 技能重名：pi 技能没有插件命名空间，同名时只保留先发现的一个并告警。`go`、`shell`、`skill` 较通用，与其他 pi 包冲突时需改名或在 settings 里筛选。
2. pi-subagents 的子会话是否加载本包扩展（决定子代理能否收到提醒、guard 是否覆盖子代理的 bash）。
3. `pi install git:` 的持久安装（写入 settings）未验证。
4. 提醒的触发率：需按 Claude 侧 eval 的方式，对比有无提醒的基线后再下结论。
