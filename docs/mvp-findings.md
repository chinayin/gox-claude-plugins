# MVP 验证结论:`go` 技能触发率(2026-06-20)

用 skill-creator 对 `gox-code-rules` 的 `go` 技能做了三轮验证。核心结论:**纯靠 description 的技能自触发,实测不可靠,且无法靠调 description 改善;`paths`(编辑期自动激活)是唯一可能可靠的杠杆,但尚未验证。**

## 方法
- 工具:skill-creator `run_eval.py` / `run_loop.py`,经 `claude -p` 实测。
- 评估集:14 条真实查询(8 条该触发的 Go 任务 + 6 条近似干扰项:Python/React/SQL/README/PRD/k8s)。
- 重要前提:eval 是**纯文本 prompt,没有真实编辑某个 `.go` 文件** → 只测了 **description 触发**,**未测 `paths` 触发**。

## 结果

### 1. 触发率基线(run_eval,2 次/查询)
| 类别 | 结果 |
|---|---|
| 不该触发(干扰项) | **6/6 全对**(无误触发) |
| 该触发(Go 任务) | **1/8 触发**(仅"review 代码"那条,且 0.5) |

写 service / 加 cobra 参数 / goose 迁移 / 搭骨架 / 改 config / 设计 cli / 修 goroutine 超时——**几乎都没调起技能**。

### 2. description 优化(run_loop,2 轮迭代)
- 原 description:train 4/9,test 2/5。
- 优化器迭代版(更激进):train 4/9,**test 2/5(完全一样)**,最终选回原版(`best == original`)。
- **结论:瓶颈不在措辞,调 description 救不回来。**

### 3. 根因
官方文档已述并被实测验证:**Claude 对"自己就能做"的任务不去 consult 技能**(写个 flag、加个迁移它觉得"我会")。这是 description 触发的结构性天花板。

## 结论与影响
- **不会误触发**(负例 6/6),作用域干净。
- **该触发时严重欠触发**,且 description 调优无效。
- **纯技能(description 自触发)不足以保证 Go 规范可靠在场**——尤其设计/意图期(那一档只能靠 description)。
- `paths`(编辑 `.go` 时自动激活)是编码期唯一可能可靠的机制,**eval 测不到,需真实会话手验**(见 §下)。

## 待办决策
1. **手验 `paths`**:真实 repo 里编辑 `.go`,看 `go` 技能是否被 `paths` 自动激活。决定编码期是否成立。
2. 据结果决定是否转**混合**:加一层薄 SessionStart 确定性兜底(只塞"本仓 Go,遵循 go 技能"的指针,推模型用技能),技能仍管深度;真强制仍靠 golangci-lint/CI/PR。

## `paths` 手验步骤(在 Claude Code 里执行)
```
# 1. 本地加 marketplace(用本地路径)
/plugin marketplace add /Users/tian/Sites/github/chinayin/golibs/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/reload-plugins        # 确认 /plugin Installed 里有它、无 Errors

# 2. 进一个含 go.mod 的真实 Go repo,新开会话,实际编辑一个 .go 文件
#    (让 Claude 改/写某个 *.go),观察:
#    - go 技能是否被自动激活(paths 生效)
#    - 模型是否据 references/rules.md 等给出符合团队规范的代码

# 3. 对照:编辑 README.md / 非 Go 文件,确认 go 技能不激活
```
记录三点:① 编辑 `.go` 时 `paths` 是否稳定激活;② 激活后采纳度;③ 非 Go 文件不激活。

---

## 更新:真实场景测试(2026-06-20)——纠正前面的悲观结论

之前的 1/8 是被低估的:run_eval 是**纯文本 prompt、无真实 `.go` 文件、技能用 command 技巧注册**。改用更真实的方法重测:把 `go` 技能装成已注册技能,在一个**有真实 `main.go`** 的干净目录里跑**中性 Go 任务**(不提"规范"),抓 stream-json 看技能是否被调用。

| 中性任务(都没提"规范") | 是否调用 `go` 技能 | 套用情况 |
|---|---|---|
| 加 `--port` 参数 | ✅ | 调技能 → 读 `cli.md` → 用 cobra/gox |
| 读 PORT 环境变量 | ✅ | 调技能 → 读 `config.md` → 用 **gox/config**(正确避开 os.Getenv) |
| 加 `/healthz` handler | ❌ | 任务琐碎,模型直接写了,没查技能 |

**结论:真实编码场景下激活率 ≈ 2/3,且激活时团队约定套用质量高。** 远好于纯文本 eval 的 1/8。漏的那次是琐碎任务(符合"Claude 对简单任务不查技能")。

边界:N=3 方向性;model=sonnet;个人技能装法(机制等价插件装法)。仍有 ~1/3 漏 → 非"保证在场"。

## 据此的决策(已落地)
- **v2 技能方案保留**(真实场景可行 + 套用质量高)。
- **加一层薄 SessionStart 兜底 hook**(`hooks/session-nudge.sh`):每会话注一句"本仓遵循团队规范,写/设计代码用 `gox-code-rules:go` / `:engineering` 技能",把 ~1/3 漏触发与设计期一并兜起来。**只提示、不含规则正文**(正文仍只在技能 references),fail-open、绝不 exit 2。
- **硬强制仍靠 golangci-lint / CI / PR review。**
- 架构由"纯技能(零 hook)"调整为"**技能为主 + 一个薄提示 hook**"。
