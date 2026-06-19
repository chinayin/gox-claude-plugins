# gox-claude-plugins

公司内部 Claude Code 规范插件 marketplace(marketplace 名:`chinayin`)。

## 插件
- `gox-code-rules` — 会话启动注入团队代码规范(MVP:common + Go)。

## 在一个公司 repo 启用(project-scope,推荐)
把 `templates/project-settings.json` 的内容并入该 repo 的 `.claude/settings.json` 并提交。
协作者信任该 repo 文件夹后,Claude Code 会提示安装/启用本插件 → 仅该 repo 生效。

## 手动试用
```
/plugin marketplace add chinayin/gox-claude-plugins
/plugin install gox-code-rules@chinayin
/reload-plugins
```

## 排错
- 设 `GOX_RULES_DEBUG=1` 启动 Claude Code,hook 决策日志会打到 stderr。
- hook 任何错误均 fail-open(编辑不受影响)。

## 开发
- 测试:`brew install jq bats-core && bats tests/` (macOS 需 brew install bash 保证 bash ≥ 5,以正确处理中文测试名)
