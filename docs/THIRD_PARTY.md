# 第三方插件

经 `chinayin` marketplace 引用（不拷贝）分发的外部插件。跟随上游默认分支，不钉版本，团队 repo 仍只声明一个 marketplace。
调用名与触发和直接装上游完全一致；需要打补丁时把 `source` 换成我们的 fork，安装句柄不变。

`tests/manifests.bats` 要求每个远程条目都在下面登记。

登记中的版本、功能与审计结论对应当时检查的提交。由于安装跟随上游默认分支，它们不自动覆盖后续版本；升级后的执行行为应重新核查。本文整理于 2026-10-09，本次未重新审计上游。

## 准入

1. 许可证可再分发（MIT / Apache-2.0 / BSD 类）。
2. 上游根目录有 `.claude-plugin/plugin.json`，`claude plugin validate` 通过。
3. 核心功能无需 `npm install` / `pip install`；可选导出能力的额外依赖单独列出。
4. 核心脚本离线运行，不自动改写用户 repo 配置；审计并记录写盘位置，区分用户要求生成的产物与插件自身配置。
5. 上游活跃、有版本管理与合并门禁。

## 启用

不进 `templates/project-settings.json` 默认列表。先用 `/plugin install <name>@chinayin` 安装；需要项目级启用时，将 `"<name>@chinayin": true` 合并到 `.claude/settings.json` 的 `enabledPlugins` 对象。项目配置不代替每位用户安装插件。
不要再从上游自己的 marketplace 装一份。

## 登记

### `diagram-design`

| 项 | 值 |
|---|---|
| 上游 | https://github.com/cathrynlavery/diagram-design（MIT） |
| 用途 | 40 种编辑风格的图出成单文件 HTML/SVG；命令 `import-mermaid` / `import-drawio` / `import-excalidraw` / `export-diagram` / `profile` / `doctor` |
| 依赖 | python3 标准库；PNG 导出可选装 Playwright + Chromium |
| 写盘 | 已登记的画风档位置是 `~/.diagram-design/profiles/`；生成与导出的产物路径需按用户任务确认，不将“不写 repo”作为全部功能的保证 |
| 已知行为 | 新项目首次画图会问一次是否定制品牌色 |
| 接入审计 | 2026-09-13，上游 commit `8d8b299`（2.6.22）：validate 通过，脚本无联网 |

Codex 安装记录：使用 `source: "url"` 和完整 Git URL 引用上游。已有记录确认 Codex CLI 0.155.1 可安装 `diagram-design@chinayin`；`source: "github"` 简写在该版本中未被识别。生成、导入、导出等运行效果未完整验证；安装成功不等同于全部功能兼容。统一验证范围见 [CODEX](CODEX.md)。
