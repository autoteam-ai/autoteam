# 第 7 步：跑通第一个需求

装好之后，先用一个小需求把整条链路走一遍，确认每个角色都能被叫醒、每道闸门都在起作用。

## 演练步骤

1. **提需求**：在 Multica 的 Chat 里告诉 Planner，或者建一个任务指派给 Planner（状态 todo）。需求要小，拆出来两三个子任务，最好有一个依赖另一个（能看到批次推进）。
2. **看拆分**：Planner 会建父任务和子任务（状态 backlog，指派给它自己），并在父任务里提及你。检查每个子任务都有“为什么做 / 要做什么 / 不做什么 / 验收标准”，验收标准写明了在线上怎么验证。
3. **批准**：把子任务改成“已批准”（approved）。每改一个，Planner 就会被叫醒一次，第 1 批立即派发，第 2 批等第 1 批完成。
4. **看派发**：Planner 在评论里写明 Implementer、Reviewer 和选择理由，然后指派 Implementer。
5. **看实现**：Implementer 把任务改为 in_progress，开分支、跑 `make dev` 和 `make check`，开 PR（标题以任务编号开头，没有关闭关键字），平台闸门生效时打开自动合并，把任务改为 code_review 并 @Reviewer。
6. **看评审**：Reviewer 等检查跑完，批准或打回。打回时任务变成 rework，Implementer 被 @ 后修改。
7. **看合并和部署**：检查通过后平台自动合并（降级模式下由 Reviewer 合并），deploy.yml 运行 `make deploy` 并通知 Planner。
8. **看验收**：Planner 在线上验证，贴出证据，评论【验收通过】并设为 done；第 1 批全部完成后，它被叫醒并派发第 2 批。
9. **看 Auditor**：在 Multica 里手动触发一次“整合审计”，确认报告任务生成、Planner 被 @ 后把建议拆进 backlog。

每一步卡住时，先看任务的运行记录（`multica issue runs <任务>`），再查[常见问题](../operations/troubleshooting.md)。

## 示例项目

[ai-workflow-example](https://github.com/songhuangcn/ai-workflow-example) 是用来演练的示例：一个零依赖的 Node 命令行工具，“线上”就是 GitHub Release（`make deploy` 发布新版本，Planner 下载最新版本按验收标准运行）。下面是在这个项目上端到端跑通的记录。

<!-- e2e-report -->
