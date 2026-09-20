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

[autoteam-example](https://github.com/autoteam-ai/autoteam-example) 是用来演练的示例：一个零依赖的 Node 命令行工具，“线上”就是 GitHub Release（`make deploy` 发布新版本，Planner 下载最新版本按验收标准运行）。

## 每轮验证怎么不被上一轮干扰

示例项目里有个 `e2e/` 目录，两个工具：

| | 做什么 |
|---|---|
| `e2e/reset.sh` | main 回到 `baseline` tag（只有 orders 的基础功能），关掉旧 PR、删掉旧分支。autoteam 生成的文件全部由这一轮重新生成 |
| `e2e/record.mjs` | 留证据：截 GitHub 的规则集页、PR 概览、PR 检查、Release 列表，同时用 `gh` 和 `multica` CLI 导出文本时间线 |

为什么要这么麻烦：跑完一轮很难凭记忆说清“闸门到底拦住了没有”“这个绿勾是这次的还是上次的”。截图记录当时页面上的样子，文本时间线带 sha 和时间戳，能 grep 能 diff，两样合起来才对得上账。`reset.sh` 不动 `e2e/`，所以历史证据跨轮保留在 `e2e/runs/<版本>/`。

## 踩过的坑

下面是两轮端到端验证里发现的问题，都已经修进模板和工具。第一轮（2026-09-19）在 GitHub Free 的个人私有仓库上跑，第二轮（2026-09-20）迁到组织的公开仓库，拿到了完整规则集。

### 第一轮：没有平台闸门时

| # | 问题 | 修正 |
|---|---|---|
| 1 | 接入 PR 新增几百行规则文件，会被 400 行上限和重复代码检查拦下 | 规则文件（由人批准）和 Markdown 不计入这两项检查 |
| 2 | runtime 显示在线，但 agent CLI 的订阅登录已经过期（两台机器各有一个） | `autoteam doctor` 报出每个 agent 最近一次运行失败的原因 |
| 3 | Planner 指令没写所有子任务完成后父任务怎么收尾 | 补上整体验收并关闭父任务 |
| 4 | agent 每次运行都在试探 CLI 参数（比如 `issue search --project`） | 角色指令加常用命令表 |
| 5 | 没有平台闸门时，`gh pr merge --auto` 不报错而是立即合并，绕过评审和检查 | 新增 `merge-mode.sh`：只有规则集生效时 Implementer 才开自动合并，降级模式由 Reviewer 批准后合并 |
| 6 | 升级时 `autoteam init --force` 会覆盖改过的 gate.yml | `autoteam init --force <文件...>` 只处理指定文件 |

问题 5 最值得记住：在降级模式下，“合并只由平台判断”这条原则完全靠指令维持，一条命令的默认行为就能绕过它。正式使用请让规则集生效（仓库改公开、升级 Pro 或迁到 Team 组织）。

### 需要人处理的环境问题（第一轮）

- devcontainer-cloud 上 Claude Code 的登录、devcontainer.local 上 Codex 的登录都已过期，要到机器上重新登录；在此之前 Claude 系 agent 放本地、Codex 系 agent 放云端。
- 所有 Claude 系 agent 共用一个 Pro 订阅，一个小需求就撞到了 5 小时会话上限。额度紧张时加其他厂商或按量计费的 agent 分担。

<!-- e2e-report -->
