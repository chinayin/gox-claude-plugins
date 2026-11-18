# 设计：新增独立技能 `bashly`

> 状态：已确认，已在 `gox-code-rules` 0.9.0 落地（2026-11-18）。本文是历史记录，规则以 `plugins/gox-code-rules/skills/bashly/SKILL.md` 为准。初稿把 bashly 并入 `shell` 技能并用 bats 替换 `test.sh`，两点均已放弃。`shell` 技能在同一版本另有几处与 bashly 无关的补充，见 `CHANGELOG.md`。2026-11-19 按真实项目复盘调整了下文的四条规则（框架报错、共用 flag、版本固定、断言库），以技能正文和 `CHANGELOG.md` 为准。

## 结论

1. bashly 规则放进独立技能 `gox-code-rules:bashly`。`shell` 技能只加一行指路，其余一字不动，`test.sh` 保留。
2. 是否用 bashly 由人决定。agent 不按子命令数量自动选型，最多提一句建议。
3. 生成器本机命令优先，docker 兜底，不固定版本。

## 边界

| 场景 | 技能 |
|---|---|
| 任何手写 `.sh`，包括 bashly 项目里的独立脚本（如 `scripts/release.sh`） | `shell` |
| 项目里有 `bashly.yml`，或用户明确要求用 bashly | `bashly` |
| 手写脚本变复杂 | 仍是 `shell`；可建议改用 bashly，不自行切换 |

## 方案对比

| 方案 | 做法 | 取舍 |
|---|---|---|
| A. 独立技能（采用） | 新增 `skills/bashly/SKILL.md` | 短脚本会话完全看不到 bashly 内容；多改几处接线 |
| B. shell 的 reference | `skills/shell/references/bashly.md` | 改动小；但手写解析、`test.sh` 等规则会同时加载，容易混 |
| C. 初稿 | 决策表写进 `shell/SKILL.md`，bats 替换 `test.sh` | 改掉短脚本现有规则，且由 agent 自动选型 |

## `bashly` 技能内容

单文件 `plugins/gox-code-rules/skills/bashly/SKILL.md`，英文，约 150 行，不建 `references/`。frontmatter `paths: "**/bashly.yml"`。

### 与 shell 的关系

按章节名引用 `shell` 技能，不复制内容。

| shell 章节 | bashly 项目里 |
|---|---|
| Output: stdout vs stderr、Status output、花括号规则、密钥权限、`--force` 守卫 | 沿用，约束自己写的 `src/` 代码 |
| Standard flags 的语义（`--json` / `--dry-run` / `--verbose`） | 沿用，改在 `bashly.yml` 里声明 |
| 脚本头 `set -euo pipefail` | 不适用，由 `strict: true` 生成 |
| 手写 `while/case` 解析、未知参数的报错格式 | 不适用，由框架生成 |
| Exit codes | 自己写的代码沿用；框架报错一律是 1，不改 |
| `test.sh` | 不适用，见“测试” |

### 目录

```
src/bashly.yml            # 命令声明
settings.yml
src/<cmd>_command.sh      # 每个子命令一个
src/lib/*.sh              # 可单测的函数
<name>                    # 生成产物，提交入库
tests/*.bats
```

### 工具

- 查找顺序：PATH 里的 `bashly` → `docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/app" dannyben/bashly` → 都没有就停下报告，不自行安装。
- 不固定版本，用本机或镜像的最新版。
- 生成的脚本要求 bash ≥ 4.2，macOS 自带的 `/bin/bash` 3.2 跑不了。

### 配置

```yaml
# settings.yml
strict: true
enable_deps_array: never
enable_env_var_names_array: never
```

- 后两项用于消除 shellcheck SC2034；代码要读 `deps` 或 `env_var_names` 时再去掉。
- 不用 `bashly add colors`，不设 `usage_colors`。

### 生成产物

- 提交 `bashly generate --env production` 的结果，禁止手改。
- 改了 `src/` 就重新生成，产物与源码同一次提交。
- 产物第 2 行记录生成器版本；不用低于该版本的 bashly 重新生成。
- 不设 CI 重新生成比对：版本不固定，比对会误报。

### 代码

- 命令文件只做“取参数 → 调 lib 函数 → 输出”。
- lib 函数用显式参数接收输入，不读全局 `args`。
- 可选参数一律写 `${args[--x]:-}`。
- 多个子命令共用的 flag 用 YAML 锚点（`&json` / `*json`）在每个子命令下各引用一次，不放根级：根级 flag 只能写在子命令前面。

### 静态检查

- shellcheck 跑生成产物；`src/` 片段单独检查会报 SC2154。
- 花括号检查（见 `shell` 技能）跑 `src/`。

### 测试

- 用 bats，目录 `tests/`，不引入 bats-assert / bats-support。
- 用到 `run --separate-stderr` 或 `run -N` 的文件写 `bats_require_minimum_version 1.5.0`。
- 单元层：`source src/lib/*.sh`，测函数。
- 契约层：运行生成产物。必测：
  - `--help` 退出码 0；
  - 未知参数退出码 1；
  - stdout 只有数据；
  - `--json` 能过 `jq -e .`；
  - `--dry-run` 不产生变更；
  - 破坏性操作不带 `--force` 时拒绝。
- 隔离：`HOME`、`TMPDIR` 指向 `$BATS_TEST_TMPDIR`；外部命令用 PATH 最前面的桩脚本替代；不访问网络。

## 接线改动

1. `skills/shell/SKILL.md`：加一行，“项目含 `bashly.yml` 或用户要求 bashly 时改用 `bashly` 技能”。
2. `hooks/session-nudge.sh`：SessionStart、SubagentStart 两段文案各加一条 bashly 路由。
3. `tests/session-nudge.bats`、`tests/paths.bats`：补对应断言。
4. `.pi/extensions/gox-code-rules.ts`：pi 版提醒单独维护，同步加一条。
5. `USAGE.md`、`docs/DESIGN.md`、`docs/PI.md`：技能列表加一项。
6. 两个 `plugin.json` 升到 0.9.0，`CHANGELOG.md` 记一条。

## 不做

- 不改 `shell` 技能的现有规则，不迁移 `test.sh`。
- 不写“子命令 ≥3 用 bashly”“何时改用 Go + cobra”这类选型门槛。
- 不统一 shell 与 Go CLI 的退出码定义。

## 试点结果

bashly 2.0.0，3 个子命令，`strict: true`。本机 Homebrew 版与 docker 镜像生成的产物字节级一致。

| 项目 | 实测 |
|---|---|
| 框架报错（未知命令或参数、缺参数、不带子命令） | stderr，退出码 1 |
| `dependencies` 缺失 | `missing dependency: <name>`，stderr，退出码 1 |
| `--help` / `--version` | stdout，退出码 0 |
| `/bin/bash` 3.2 运行 | `bash version 4.2 or higher is required`，退出码 1 |
| strict 下访问未设置的键 | `args[--force]: unbound variable`，退出码 1 |
| 根级 flag | `pilot --verbose list` 可以，`pilot list --verbose` 报 invalid option |
| YAML 锚点共用 flag | 可用 |
| `--env production` 重复生成 | 字节级一致；与开发模式产物差 161 行 |
| 1.4.0 与 2.0.0 同源码的产物 | 差 70 行，含行为变化（2.0.0 新增 `--` 处理） |
| shellcheck 0.11.0 跑产物 | 默认 2 条 SC2034；按“配置”一节设置后干净，依赖检查仍生效 |
| bats 1.14.0 | 单元层与契约层共 6 条通过；不写最低版本声明时报 BW02 |
| 耗时 | 本机 0.2 秒，docker 0.5 秒；镜像 850MB |

## 验证范围

- **已核实**：上表全部；Homebrew 有 `bashly` 2.0.0，依赖 brew 的 `ruby` 和 `bash`；bashly 的库列表不含测试脚手架。
- **未核实**：Linux 上的本机安装方式（CI 可直接用 docker 镜像）；`shfmt` 对生成产物的结果；除 `strict` 和两个 `enable_*_array` 之外的配置项。

## 已确认的决定

| # | 问题 | 决定 |
|---|---|---|
| 1 | CI 重新生成比对 | 去掉，改用“生成产物”一节的规则 |
| 2 | bashly 项目的测试 | bats；`shell` 技能的 `test.sh` 不变 |

## 落地步骤

1. 同步 `origin/main`（本地落后 5 个提交，均不涉及 `shell` 技能）。
2. 加载 `gox-code-rules:skill`，按上文写 `skills/bashly/SKILL.md`；正文与脚本输出用英文。
3. 完成“接线改动”。
4. 跑 `bats plugins/gox-code-rules/tests/`、`bats tests/` 和仓库现有检查，全部通过。
