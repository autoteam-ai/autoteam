---
title: 文档
slug: /
---

# 文档

按这个顺序读：先看概念弄清楚为什么这么设计，再按搭建步骤装，最后看日常操作。

## 概念

| 文档 | 讲什么 |
|---|---|
| [为什么要自管理](concepts/why.md) | 用 agent 做大型项目卡在哪四个地方，设计原则 |
| [四个角色](concepts/roles.md) | Planner / Implementer / Reviewer / Auditor 各管什么、不能做什么、谁叫醒谁 |
| [任务状态和唤醒](concepts/lifecycle.md) | 状态流转、Multica 的唤醒规则、防止来回打转、升级 |
| [按额度选 agent](concepts/quota-routing.md) | 计费模式、registry.yaml、Planner 的选人流程 |
| [安全边界和保护等级](concepts/guardrails.md) | 哪些是 agent 绕不过的硬约束、哪些只是指令约束；三种保护等级和试用模式 |

## 搭建

| 文档 | 对应研究文档 |
|---|---|
| [前提条件](setup/prerequisites.md) | — |
| [快速上手](setup/quickstart.md) | 全部步骤的最短路径 |
| [第 0 步 准备仓库](setup/repo.md) | make check、make dev、AGENTS.md |
| [第 1–3 步 GitHub](setup/github.md) | 账号隔离、合并规则、自动部署 |
| [第 4–6 步 Multica](setup/multica.md) | 状态、agent 和计费注册表、触发配置 |
| [第 7 步 跑通第一个需求](setup/first-run.md) | 用示例项目完整走一遍 |

## 日常

| 文档 | 讲什么 |
|---|---|
| [日常操作](operations/daily.md) | 提需求、批准、处理升级、改规则文件 |
| [每周指标](operations/metrics.md) | 看哪几个数、怎么看 Auditor 的报告 |
| [常见问题](operations/troubleshooting.md) | 报错和现象对照表 |

## 参考

| 文档 | 讲什么 |
|---|---|
| [autoteam 命令](reference/cli.md) | 每个命令做什么、参数 |
| [配置文件](reference/config.md) | autoteam.conf、registry.yaml、autopilot 的 front matter |
| [生成的文件](reference/files.md) | autoteam init 生成的每个文件、谁能改 |
| [代价和风险](limitations.md) | 这套流程的代价，以及什么时候不该用 |
