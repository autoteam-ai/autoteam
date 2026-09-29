---
title: 日常操作
---

# 日常操作

人只跟 Planner 对话，日常只有这几件事。

## 紧急停止

在 Multica Chat 对 Planner 说「停止 autoteam」或「暂停 autoteam」。Planner 会运行 `autoteam stop --apply --keep-run <当前 Chat run ID>`，暂停本项目 autopilot、取消 registry agent 正在运行和排队的任务，并回复清单；它自己的这次 Chat 不被取消。你也可在项目仓库先运行 `autoteam stop` 预览，再运行 `autoteam stop --apply`。用 `autoteam status` 查看状态。

恢复时在 Chat 说「恢复 autoteam」，或运行 `autoteam resume --apply`。只有停止前 active 的 autopilot 会恢复；取消的运行不会自动重跑，下次巡检照常推进。暂停期间被手动触发的 autopilot 仍可能叫醒 agent，agent 开工检查会让它立即结束。

## 你的闸门在哪

团队跑起来之后，下面这些地方仍需要你参与。`AUTOTEAM_AUTO_APPROVE=on` 时，Planner 可按[放行分级](../concepts/guardrails.md#哪些只是指令约束)自主放行部分任务，每日有上限；不符合条件的任务仍由你批准，名额用完的候选等下次放行。普通代码 PR 由 Reviewer 批准、检查通过后进合并队列自动合并，部署不需要审批。

| 闸门 | 在哪 | 谁挡住 agent | 什么时候来 |
|---|---|---|---|
| 规则文件 PR 的批准 | GitHub | 规则集要求 Code Owner 审批，而 CODEOWNERS 不支持 GitHub App，只能写人 | agent 每次要改 `.github/`、`.autoteam/`、`Makefile`、`.jscpd.json` |
| 任务从「待审核」（backlog）改成「待办」（todo） | Multica，**Backlog 列** | [放行分级](../concepts/guardrails.md#哪些只是指令约束)：符合条件的由 Planner 自主放行并留评论；受保护路径、新功能等仍由你批准。平台不能限制 agent 改状态，靠指令约束和每日摘要的放行核对发现违规 | Planner 只为需你批准的任务提及你；名额用完的候选留在 backlog 等下次放行 |
| 处理 blocked 的升级 | Multica，**Blocked 列**（任务会指派给你） | 指令约束 | 打回 2 次 / 验收不通过 2 次 / 换人后仍失败 / 线上故障已回滚 |
| `make publish` 发版 | 你的机器 | 不接进任何自动流程，`package.json` 和 `scripts/release.sh` 又受 CODEOWNERS 保护 | 你想发版的时候（仅 autoteam 自己这个仓库） |

看板上主要看两列：**Backlog**（需你批准的任务，以及等自主放行名额的候选）和 **Blocked**（等你决断）。升级的任务会指派给你；每日摘要会把需要你处理的事列在「今天需要人决定的事」，并单列已经自主放行的任务供你核对。其余的列都是 agent 之间在流转，不用盯。

中间两行是日常的，另外两行只在特定事件后出现。规则文件合并后同步到 Multica（`autoteam multica --apply`）**不用你管**：Planner 在验收时自己跑，用的是你的 multica 凭据，这条记在[已知的偏离](../concepts/invariants.md#已知的偏离)里。**这张表里的每一项都是"人还要介入"的成本**，「规则复盘」autopilot 每周盯的就是怎么把它变短。

## 提需求

- 在 Multica 的 Chat 里告诉 Planner；或者建任务、写清楚目标，指派给 Planner（状态 todo）。
- 需求不清楚时 Planner 会先在评论里问你，回复时 @Planner。
- 大需求让 Planner 拆，不要自己拆好了直接指派给 Implementer：绕过 Planner 就没人选人、没人验收。

## 批准任务

这是人在日常流转里需要处理的放行操作；符合[放行分级](../concepts/guardrails.md#哪些只是指令约束)的任务可由 Planner 自主放行。

- Planner 拆好的子任务先进入 backlog（待审核）。开启 `AUTOTEAM_AUTO_APPROVE` 后，符合条件的由 Planner 自主放行并留 `【自主放行】` 评论；需你批准的任务才会在父任务评论里提及你。每日名额用完的候选留在 backlog 等下次放行。
- 看每个子任务的“为什么做 / 不做什么 / 验收标准”，值得做就改成“待办”（todo，指派人保持 Planner），不值得做就改成 cancelled 并写一句原因。
- 可以一次批准多个。逐个用 `multica issue runs <任务>` 确认 Planner 的运行已生成；界面批准的实测边界见[界面批准后的唤醒核对](../concepts/lifecycle.md#界面批准后的唤醒核对)。前面批次没完成的任务会先留着。
- **agent 也有改状态的权限**，平台拦不住它把任务从 backlog 改成 todo。每日摘要的批准核对会把带 `【自主放行】` 评论的任务列在「自主放行」一栏，供你查看理由和当前状态；你可以直接取消不该做的任务。没有可核实放行依据、或自主放行了受保护路径的任务会列为「违规」，需要处理。

## 评论的讲究

- 你发的普通评论会叫醒任务当前的指派 agent。只想留个记录，评论以 `/note` 开头。
- 想让某个 agent 处理，在评论里 @它（Multica 的输入框会自动生成提及链接）。
- 对 Planner 说话就在父任务或 Chat 里 @Planner，不要直接指挥 Implementer 改需求：改需求要回到 Planner，由它更新任务和验收标准。

## 处理升级

Planner 把任务设为 blocked 时，会在父任务评论里提及你，说明卡点、选项和建议。常见的几种：

| 升级原因 | 你要决定 |
|---|---|
| 同一个 PR 被打回两次（Implementer 和 Reviewer 有分歧） | 谁对；必要时自己看一眼 PR |
| 验收不通过两次 | 需求是不是没说清、验收标准是否合理 |
| 换人后仍失败 | 额度、权限或环境问题，可能要你去机器上看 |
| 线上故障（已回滚） | 怎么修，是否要人接手 |

决定后在评论里 @Planner 回复，它会把任务改回合适的状态继续。

## 看每日摘要

每天 9:00 Planner 建一个“每日摘要”任务并通知你：进展、待你处理的事项、批准核对、各账号额度和花费。先看“今天需要人决定的事”，再看批准核对中的「自主放行」和「违规」：前者是 Planner 按分级放行、可由你直接取消的任务，后者需要核查处理。

## 修改规则文件

`.github/`、`.autoteam/`、`Makefile`、`.jscpd.json` 受 CODEOWNERS 保护，改动必须由你批准：

- 推荐让 Implementer 改：给 Planner 提需求，走正常流程，最后由你作为 Code Owner 批准 PR；
- 你自己改：在本地改好（可以不提交），跑 `autoteam propose` 预览，确认后 `autoteam propose --apply`（标题要带任务编号就加 `--title`）。PR 由 Implementer App 身份开出，你只是批准人，不会撞上「最后推送者不能批准」，也不用临时关规则集；
- 改了 `.autoteam/`，或当前生效的指令源（包内 `skills/autoteam/instructions/**`，已 eject 时为 `.autoteam/instructions/**`），合并后要同步到 Multica 才生效；升级 autoteam 版本（角色指令、autopilot 跟着包走）同理——这一步 Planner 在验收时自己做（`autoteam multica --apply` + `autoteam doctor`），你不用管。它跑不起来会在运营笔记里提及你。

## 每周

- 看[每周指标](metrics.md)和 Auditor 的报告；
- 抽读一两个合入的 PR，避免对代码变陌生；
- 每月核对一次 registry.yaml 里各家的额度规则。
