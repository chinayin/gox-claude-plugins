# Codex 插件

同仓库独立打包。`plugins/` 保持 Claude 入口，`codex/` 维护 Codex 清单、提醒和构建；构建产物包含完整规范与脚本，安装后不依赖源码仓库。

## 首批范围

| 插件 | 内容 |
|---|---|
| `gox-code-rules` | engineering、go、shell、skill；复用现有正文与 references，使用 Codex 专属会话/子代理提醒 |
| `gox-guard` | 复用 secrets 扫描脚本，在受支持的 Bash / exec_command `git push` 调用前检查待推送提交 |

frontend 仍是骨架，Python 未交付；token-thrift 的模型委派和第三方 diagram-design 不在本次适配范围。

## 构建

已有 `python3`、PyYAML（根目录 `requirements-dev.txt`）。在仓库根目录执行：

```bash
python3 codex/build.py
```

输出为 `codex/dist/`：

```text
.agents/plugins/marketplace.json
plugins/gox-code-rules/.codex-plugin/plugin.json
plugins/gox-code-rules/skills/...
plugins/gox-code-rules/hooks/...
plugins/gox-guard/.codex-plugin/plugin.json
plugins/gox-guard/hooks/...
BUILD.json
```

每个插件包含 LICENSE。BUILD.json 记录源提交和每个输入文件的 SHA-256；工作区存在未提交修改时，以文件哈希标识实际输入。

构建不覆盖已有目录。重建时指定新的路径，例如：

```bash
python3 codex/build.py --output /tmp/chinayin-codex-next
```

整个输出目录可以搬走、归档或独立分发。不要仅复制 marketplace.json，也不要把源码 `codex/plugins/` 当作完整安装包。

## 安装

下面以默认输出目录为例。先在源码仓库根目录执行：

```bash
codex plugin marketplace add "$PWD/codex/dist"
codex plugin add gox-code-rules@chinayin-codex
codex plugin add gox-guard@chinayin-codex
```

打开新会话，在 `/hooks` 中审阅并信任插件 Hooks；还需本机已有 `bash`、`jq` 和 `betterleaks`。构建和安装不会代替 Hook 信任，也不会自动安装扫描器。

`gox-code-rules` 提醒模型使用文件读取工具读取当前安装包中的 SKILL.md。技能属于软引导，无法保证每次自动触发。`gox-guard` 只有 Hook 已启用、已信任且对应工具路径受支持时才提供拦截；shell 别名、脚本间接 push、交互式 stdin 等不属于完整覆盖承诺，CI 仍应保留自身检查。

升级时更新 Codex 清单版本、重新构建。若更换输出目录，先通过 `codex plugin marketplace remove chinayin-codex` 移除旧的市场注册，再用上面的 marketplace add 指向新目录，然后再次 plugin add 安装；最后打开新会话并重新检查 Hook 信任。源目录须保留供后续安装使用。不要同时注册多个同名市场。

本仓库 GitHub 根目录仍是 Claude marketplace。Codex 当前使用上述本地构建安装流程；如需直接从 Git 分发，发布完整产物到具有该根目录布局的分支/仓库。本构建器不发布或修改远端。

## 验证

```bash
python3 -m unittest discover -s codex/tests -v
python3 codex/tests/probe_runtime.py codex/dist
make validate
make test
```

`probe_runtime.py` 需要本机 Codex CLI，使用只读 plugin/read 接口解析指定包；不安装、启用或信任插件，不调用模型。Codex app-server 需能访问自身状态目录。

本次在 `codex-cli 0.155.1` 验证：两个包都能被真实运行时识别，规范包有 4 个 Skill，两个包各有 2 个 Hook 事件。包级测试实际运行搬离源码后的提醒脚本与扫描 Hook，覆盖扫描干净、发现、异常、缺失和脱敏。

尚未验证已安装插件在真实模型会话中的自动技能触发、子代理注入及工具拦截。上线验收应安装并信任 Hooks，在临时 Git 仓库和本地 remote 上测试；勿将只读解析或脚本测试称为完整会话端到端验收。

参考：[插件打包](https://developers.openai.com/plugins/build/plugins)、[Codex Hooks](https://learn.chatgpt.com/docs/hooks)。
