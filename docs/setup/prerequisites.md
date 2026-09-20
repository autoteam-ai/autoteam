---
title: 前提条件
---

# 前提条件

## 工具

| 工具 | 版本 | 用途 |
|---|---|---|
| bash | 3.2 以上（macOS 自带的就行） | 运行 autoteam |
| git | 任意近期版本 | |
| gh | 2.40 以上，已登录，对目标仓库有 admin 权限 | 配置仓库、规则集、secret |
| jq | 1.6 以上 | 处理 JSON |
| curl | 任意 | 调 Multica 的状态接口 |
| multica | 0.5 以上 | 配置 Multica；`brew install multica-ai/tap/multica`，或装桌面端（自带 CLI） |

Windows 请在 WSL 里运行。

## GitHub

- 目标仓库在 GitHub 上，你是 admin。
- 套餐决定平台闸门能做到什么程度，见[保护等级](../concepts/guardrails.md#保护等级)。GitHub Free 的私有仓库没有规则集和自动合并，只能用降级模式。
- 要建 GitHub App：至少 impl、review 两个（planner 推荐），见[三个 GitHub App](github.md#三个-github-app)。没有就先用单身份试用模式。

## Multica

- 有一个工作区，运行 `autoteam multica` 的人是 owner 或 admin（自定义状态只有他们能建）。
- 至少一台机器跑着 Multica daemon（桌面端会自动起；服务器上用 `multica setup cloud` 或 `multica daemon start`），机器上的 agent CLI（Claude Code、Codex、Copilot 等）已经登录对应的订阅账号。`autoteam runtimes` 能列出在线的 runtime。
- 推荐三台机器（或三个隔离的环境）：A 跑 Implementer、B 跑 Reviewer、C 跑 Planner 和 Auditor，每台只放对应角色的 App 私钥。
- agent 运行时要能访问仓库：daemon 会用机器上的 git 凭据克隆，确认那台机器能 `git clone` 你的仓库。

## 仓库本身

这三件事 Multica 管不到，不做好，后面的编排全部白搭：

1. `make check` 一条命令跑完全部检查；
2. `make dev` 一条命令起环境，可以重复执行；
3. 分层的 AGENTS.md，只写从代码里看不出来、或者容易搞错的规则。

见[第 0 步 准备仓库](repo.md)。
