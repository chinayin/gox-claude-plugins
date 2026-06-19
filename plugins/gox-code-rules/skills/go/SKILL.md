---
name: go
description: 团队 Go 微服务架构与编码规范。设计或编写本仓 Go 代码、CLI 命令(cobra)、配置(gox/config)、数据库迁移(goose)、项目脚手架(Makefile/CI)时务必使用——只要在动 Go 代码或规划 Go 模块就该参考,即使用户没明说"规范"。
paths: "**/*.go, go.mod, go.work, go.sum"
---

# 团队 Go 规范

写或设计本仓 Go 代码时遵循团队约定。**回复与代码注释用中文。** 详规按下面索引**按需读取** `references/` 对应文件——不要一次性全读,只读与当前任务相关的。

## 何时读哪份(索引)

| 当前在做 | 读这份 |
|---|---|
| 写**任何** Go 代码(基线:版本、日志、错误、并发、命名…) | `references/rules.md` ← 默认先读 |
| 设计/编写 `cmd/**` 下的 CLI 命令(cobra + gox/cli) | `references/cli.md` |
| 配置加载(`config/**`、`main.go`/`config.go`、`bootstrap/`,gox/config) | `references/config.md` |
| 数据库迁移 / schema(`migrations/`、`*migrate*`、`store.go`,goose) | `references/db-migrations.md` |
| 项目脚手架(`Makefile`、`.golangci`、`.github/workflows/*`、`.editorconfig`) | `references/scaffold.md` |

## 核心铁律(最高优先级,细节见 rules.md)

- Go 1.26+;JSON/protobuf 字段 snake_case。
- 日志:入口用 gox/log 初始化,业务代码用 log/slog;**不要用 fmt 打日志**。
- 配置:统一用 gox/config,**禁止**业务代码直接用 viper 或裸 `os.Getenv`。
- 所有外部调用必须设超时(内部 10s、外部 30s)。
- 不使用包级可变全局状态;错误用包前缀包装。

> 这些是会话内的**软引导**;最终强制以仓库的 `golangci-lint` / CI / PR review 为准。
