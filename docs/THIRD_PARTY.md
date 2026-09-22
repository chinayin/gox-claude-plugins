# 第三方插件

经 `chinayin` marketplace 引用（不拷贝）分发的外部插件。跟随上游默认分支，不钉版本，团队 repo 仍只声明一个 marketplace。
调用名与触发和直接装上游完全一致；需要打补丁时把 `source` 换成我们的 fork，安装句柄不变。

`tests/manifests.bats` 要求每个远程条目都在下面登记。

## 准入

1. 许可证可再分发（MIT / Apache-2.0 / BSD 类）。
2. 上游根目录有 `.claude-plugin/plugin.json`，`claude plugin validate` 通过。
3. 无需 `npm install` / `pip install` 即可工作。
4. 不联网，不写用户 repo。
5. 上游活跃、有版本管理与合并门禁。

## 启用

不进 `templates/project-settings.json` 默认列表。按需在 repo 的 `.claude/settings.json` 加 `"<name>@chinayin"`，或 `/plugin install <name>@chinayin`。
不要再从上游自己的 marketplace 装一份。

## 登记

### `diagram-design`

| 项 | 值 |
|---|---|
| 上游 | https://github.com/cathrynlavery/diagram-design（MIT） |
| 用途 | 40 种编辑风格的图出成单文件 HTML/SVG；命令 `import-mermaid` / `import-drawio` / `import-excalidraw` / `export-diagram` / `profile` / `doctor` |
| 依赖 | python3 标准库；PNG 导出可选装 Playwright + Chromium |
| 写盘 | 画风档写 `~/.diagram-design/profiles/`，不写 repo |
| 已知行为 | 新项目首次画图会问一次是否定制品牌色 |
| 接入审计 | 2026-09-13，上游 commit `8d8b299`（2.6.22）：validate 通过，脚本无联网 |

Codex 兼容：使用 `source: "url"` 和完整 Git URL 引用上游，Claude 与 Codex 均支持。已验证 Codex CLI 0.155.1 可安装 `diagram-design@chinayin`；`source: "github"` 简写在该版本中未被识别。
