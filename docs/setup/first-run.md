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

[autoteam-example](https://github.com/autoteam-ai/autoteam-example) 是用来演练的示例：一个零依赖的 Node 命令行工具，“线上”就是 GitHub Release（`make deploy` 发布新版本，Planner 下载最新版本按验收标准运行）。下面是 2026-09-19 在这个项目上端到端跑通的记录。

### 环境

| 项 | 情况 |
|---|---|
| GitHub | 个人账号的私有仓库，GitHub Free → 保护等级 none（降级模式），单账号试用模式 |
| Multica | 工作区 HDGCS，CLI 0.5.0；两台机器 devcontainer.local、devcontainer-cloud |
| agent | Planner、2 个 Implementer（Claude、Codex）、2 个 Reviewer（Claude、Codex）、Auditor；Claude 是 Pro 订阅 |
| 需求 | 给 orders 加 `export` 命令，按日期范围导出 CSV，带 4 条线上验收标准 |

### 装配（约 5 分钟）

1. `npx skills add autoteam-ai/autoteam --skill autoteam` 从私有仓库装好 skill，按 SKILL.md 执行 `autoteam init --workspace hdgcs --human Song`：自动识别出任务前缀 HDGCS，识别出 Free 私有仓库、不声明 environment。
2. gate.yml 加上 Node 22，registry.yaml 填 6 个 agent，开 PR #1。gate 在真实 PR 上通过：规则文件不计入行数，本 PR 只算 41 行。合并后第一次部署发布了 Release。
3. `autoteam github --apply --trial`：判定为 none 级，合并方式和删分支设置生效，自动合并因套餐限制没生效（如实报出）。
4. `autoteam multica --apply`：建了 4 个状态、6 个 agent、1 个项目、8 个 autopilot，部署 webhook 地址写进 GitHub secret。再跑一次没有任何改动；`autoteam doctor` 没有错误，3 个提醒都是降级和单账号带来的。

### 跑需求（约 15 分钟，不含等额度恢复）

| 时间（UTC） | 发生了什么 |
|---|---|
| 16:12 | 以人的身份建需求 HDGCS-15 指派给 Planner |
| 16:13 | Planner 读代码、查重，拆出 HDGCS-16（改动预计不到 400 行，只拆一个），描述有“为什么做 / 要做什么 / 不做什么 / 验收标准”，并用成员链接提及人请求批准 |
| 16:15 | 人把 HDGCS-16 改为已批准，平台立即叫醒 Planner；这次运行撞上 Claude Pro 的会话额度上限，任务停在已批准 |
| 17:13 | 额度恢复后触发推进巡检：Planner 看了两个账号的用量，派给 ex-impl-codex、评审 ex-rev-claude，在评论里写明理由（Reviewer 只写名字，没提前叫醒它） |
| 17:14 | Implementer 启动即失败：devcontainer.local 上 Codex 的登录过期。平台在父任务上发系统评论叫醒 Planner |
| 17:17 | Planner 评论【换人】，改派 ex-impl-claude |
| 17:19 | Implementer 实现、`make check` 14/14、开 PR #5；执行 `gh pr merge --auto` 后 PR 7 秒内被直接合并（见下文问题 5） |
| 17:21 | Reviewer 事后复核：逐条核对正确性、重复实现、边界数据，用样例数据跑了 4 条验收标准；同账号不能批准，改用【批准】评审评论；任务改为待上线 |
| 17:25 | 修复合并的 PR #6 部署完成，webhook 叫醒 Planner：确认 PR #5 的合并提交在部署 sha 里，下载对应 Release 逐条验收，评论【验收通过】27fa44c，HDGCS-16 完成 |
| 17:27 | 唯一一批完成，平台叫醒 Planner 做父任务整体验收，HDGCS-15 完成并提及人 |
| 17:28 | 触发回滚工作流，Release 重新发布，webhook 以 kind=rollback 叫醒 Planner |
| 17:29 | 手动触发“整合审计”：平台建出任务“整合审计 2026-09-19”交给 Auditor |
| 17:31 | Auditor 跑了 health-metrics 和 jscpd（0 重复），又人工比对出两处低于 jscpd 阈值的重复实现（带文件和行号），各写成一个独立小任务建议，@Planner 后把报告任务设为完成 |
| 17:32 | Planner 把两条建议拆成两个待审核任务（查过重、引用了审计任务、写了不做什么），提及人请求批准 |

演练结束后暂停了 7 个定时 autopilot，只保留“部署结果”（只在部署时触发）。要恢复：`multica autopilot update <autopilot-id> --status active`，或在 Multica 界面里打开。

### 发现的问题和修正

| # | 问题 | 修正 |
|---|---|---|
| 1 | 接入 PR 新增几百行规则文件，会被 400 行上限和重复代码检查拦下 | 规则文件（由人批准）和 Markdown 不计入这两项检查 |
| 2 | runtime 显示在线，但 agent CLI 的订阅登录已经过期（两台机器各有一个） | `autoteam doctor` 报出每个 agent 最近一次运行失败的原因 |
| 3 | Planner 指令没写所有子任务完成后父任务怎么收尾 | 补上整体验收并关闭父任务 |
| 4 | agent 每次运行都在试探 CLI 参数（比如 `issue search --project`） | 角色指令加常用命令表 |
| 5 | 没有平台闸门时，`gh pr merge --auto` 不报错而是立即合并，绕过评审和检查 | 新增 `merge-mode.sh`：只有规则集生效时 Implementer 才开自动合并，降级模式由 Reviewer 批准后合并 |
| 6 | 升级时 `autoteam init --force` 会覆盖改过的 gate.yml | `autoteam init --force <文件...>` 只处理指定文件 |

问题 5 最值得记住：在降级模式下，“合并只由平台判断”这条原则完全靠指令维持，一条命令的默认行为就能绕过它。正式使用请让规则集生效（仓库改公开、升级 Pro 或迁到 Team 组织）。

### 需要人处理的环境问题

- devcontainer-cloud 上 Claude Code 的登录、devcontainer.local 上 Codex 的登录都已过期，要到机器上重新登录；在此之前 Claude 系 agent 放本地、Codex 系 agent 放云端。
- 所有 Claude 系 agent 共用一个 Pro 订阅，一个小需求就撞到了 5 小时会话上限。额度紧张时加其他厂商或按量计费的 agent 分担。

<!-- e2e-report -->
