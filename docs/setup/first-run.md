---
title: 第 7 步：跑通第一个需求
---

# 第 7 步：跑通第一个需求

装好之后，先用一个小需求把整条链路走一遍，确认每个角色都能被叫醒、每道闸门都在起作用。

## 演练步骤

1. **提需求**：在 Multica 的 Chat 里告诉 Planner，或者建一个任务指派给 Planner（状态 todo）。需求要小，拆出来两三个子任务，最好有一个依赖另一个（能看到批次推进）。
2. **看拆分**：Planner 会建父任务和子任务（状态 backlog，指派给它自己），并在父任务里提及你。检查每个子任务都有“为什么做 / 要做什么 / 不做什么 / 验收标准”，验收标准写明了在线上怎么验证。
3. **批准**：把子任务从 backlog 改成 todo（指派人仍是 Planner）。每改一个，用 `multica issue runs <任务>` 确认 Planner 的运行已生成；界面批准并非每次都成功唤醒，见[界面批准后的唤醒核对](../concepts/lifecycle.md#界面批准后的唤醒核对)。第 1 批由 Planner 派发，第 2 批等第 1 批完成。
4. **看派发**：Planner 在评论里写明 Implementer、Reviewer 和选择理由，然后指派 Implementer。
5. **看实现**：Implementer 把任务改为 in_progress，开分支、跑 `make dev` 和 `make check`，开 PR（标题以任务编号开头，没有关闭关键字），平台闸门生效时打开自动合并，把任务改为 in_review 并 @Reviewer。
6. **看评审**：Reviewer 等检查跑完，批准或打回。打回时 Reviewer 在 PR 上要求修改并 @Implementer，Implementer 把任务改回 in_progress 后修改。
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

### 第二轮：拿到完整闸门之后

迁到组织的公开仓库，规则集、自动合并、合并队列全部可用。新问题都出在"配置看起来成功了，链路其实断着"这一类：

| # | 问题 | 修正 |
|---|---|---|
| 1 | 规则集生效了，但单账号下审批数只能设 0，检查一绿平台就合并，Reviewer 来不及看 | 新增 `staged` 模式：Implementer 开 draft PR（draft 不能开自动合并），Reviewer 批准后 `gh pr ready` 放行 |
| 2 | 项目改名后 autopilot 还绑着旧 `project_id`，照常运行、照常成功，只是在旧项目里找任务，Planner 一直报"无待验收任务" | apply 时比对 `project_id`，doctor 把绑错项目当错误报 |
| 3 | 给 Reviewer 配了机器账号的 `env_file`，apply 却报"已是最新"——env 读不回来没法比对，判断里又漏了它，token 一次都没同步 | 和 MCP 配置一样：registry 里写了就每次重写 |
| 4 | 人改规则文件时合不了，GitHub 说"最后推送的人不能当批准人"，换机器账号重推当场也没生效 | 两件事叠在一起：换身份推送要先清空凭据助手（否则系统钥匙串的凭据优先），而且 GitHub 更新"最后推送者"有延迟。正确做法是机器账号推、人批准，当场没生效就等几分钟重试 |
| 5 | Implementer 开完 PR 才撞到额度上限，巡检只看到"运行失败"就改派，新 Implementer 把同一个功能重做了一遍，留下两个 PR | Planner 换人前先查 `gh pr list --search "<任务编号> in:title"`，有 PR 就转 `in_review` 交给 Reviewer，不重做 |

2 和 3 是同一类错误，都是**比对不全面导致"已是最新"撒谎**。这类问题最难发现：命令返回成功，doctor 全绿，只有跑到那一步才发现链路是断的。现在两条都有回归测试。

两个用得上的技术细节：

- 开了合并队列后，`gh pr merge` 不能带 `--delete-branch`（直接报错），分支由仓库设置 `delete_branch_on_merge` 自动删；`mergeStateStatus` 也会一直是 `BLOCKED`，那是"只能走队列"的意思，不代表缺审批。
- 要让 git push 换成机器账号的身份，得先清空凭据助手列表再加自己的，否则系统钥匙串里的凭据优先：
  `git -c credential.helper= -c credential.helper='!f() { echo username=x-access-token; echo password=$BOT_TOKEN; }; f' push`

### 需要人处理的环境问题

- agent CLI 的订阅登录会过期（两台机器上各踩过一次）。runtime 显示在线不代表 CLI 能用，`autoteam doctor` 会报出每个 agent 最近一次运行失败的原因和时间。
- 所有 Claude 系 agent 共用一个 Pro 订阅，一个小需求就撞到了 5 小时会话上限。额度紧张时加其他厂商或按量计费的 agent 分担。
- 要用上完整闸门，需要一个独立的机器账号当 Reviewer：GitHub 不允许作者批准自己的 PR，没有第二个账号，规则集的审批数只能设 0。

<!-- e2e-report -->
