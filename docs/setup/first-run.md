---
title: 第 7 步：跑通第一个需求
---

# 第 7 步：跑通第一个需求

运行 `autoteam setup` 并确认，或在非交互终端运行 `autoteam setup --apply`；末尾的 doctor 通过后，先用一个小需求把整条链路走一遍，确认每个角色都能被叫醒、每道闸门都在起作用。

## 演练步骤

1. **提需求**：在 Multica 的 Chat 里告诉 Planner，或者建一个任务指派给 Planner（状态 todo）。需求要小，拆出来两三个子任务，最好有一个依赖另一个（能看到批次推进）。
2. **看拆分**：Planner 会建父任务和子任务（状态 backlog，指派给它自己），并在父任务里提及你。检查每个子任务都有“为什么做 / 要做什么 / 不做什么 / 验收标准”，验收标准写明了在线上怎么验证。
3. **批准**：先跑 `autoteam approve <父任务>` 预览，确认后加 `--apply` 一次放行所有子任务（指派人仍是 Planner）。命令只让第 1 批里的一个任务叫醒 Planner，其余和第 2 批都不唤醒，并自己核对 Planner 的运行已生成，不用逐个检查。第 1 批由 Planner 派发，第 2 批等第 1 批完成。
4. **看派发**：Planner 在评论里写明 Implementer、Reviewer 和选择理由，然后指派 Implementer。
5. **看实现**：Implementer 把任务改为 in_progress，开分支、跑 `make dev` 和 `make check`，开 PR（标题以任务编号开头，没有关闭关键字），平台闸门生效时打开自动合并，把任务改为 in_review 并 @Reviewer。
6. **看评审**：Reviewer 等检查跑完，批准或打回。打回时 Reviewer 在 PR 上要求修改并 @Implementer，Implementer 把任务改回 in_progress 后修改。
7. **看合并和部署**：检查通过后平台自动合并（降级模式下由 Reviewer 合并），deploy.yml 运行 `make deploy` 并通知 Planner。
8. **看验收**：Planner 在线上验证，贴出证据，评论【验收通过】并设为 done；第 1 批全部完成后，它被叫醒并派发第 2 批。
9. **看 Auditor**：在 Multica 里手动触发一次“周度健康报告”，确认报告任务生成、Planner 被 @ 后把建议拆进 backlog。

每一步卡住时，先看任务的运行记录（`multica issue runs <任务>`），再查[常见问题](../operations/troubleshooting.md)。

## 示例项目

[示例项目：团队书架](example.md)记录了官方示例的一次完整交付，包括任务拆分、PR 评审、上线验收和截图。

## 每轮验证怎么不被上一轮干扰

示例项目里有个 `e2e/` 目录，两个工具：

| | 做什么 |
|---|---|
| `e2e/reset.sh` | main 回到 `baseline` tag（只有 orders 的基础功能），关掉旧 PR、删掉旧分支。autoteam 生成的文件全部由这一轮重新生成 |
| `e2e/record.mjs` | 留证据：截 GitHub 的规则集页、PR 概览、PR 检查、Release 列表，同时用 `gh` 和 `multica` CLI 导出文本时间线 |

为什么要这么麻烦：跑完一轮很难凭记忆说清“闸门到底拦住了没有”“这个绿勾是这次的还是上次的”。截图记录当时页面上的样子，文本时间线带 sha 和时间戳，能 grep 能 diff，两样合起来才对得上账。`reset.sh` 不动 `e2e/`，所以历史证据跨轮保留在 `e2e/runs/<版本>/`。
