---
title: 日常操作
---

# 日常操作

人只跟 Planner 对话，日常只有这几件事。

## 你的闸门在哪

团队跑起来之后，这几个地方只有你能放行，agent 会停在这儿等你。其余的全部自动流转——普通代码 PR 由 Reviewer 批准、检查通过后进合并队列自动合并，部署不需要审批。

| 闸门 | 在哪 | 谁挡住 agent | 什么时候来 |
|---|---|---|---|
| 规则文件 PR 的批准 | GitHub | 规则集要求 Code Owner 审批，而 CODEOWNERS 不支持 GitHub App，只能写人 | agent 每次要改 `.github/`、`.autoteam/`、`Makefile`、`.jscpd.json` |
| 任务从「待审核」改成「已批准」 | Multica，**Backlog 列** | 只有指令约束——agent 技术上改得了，靠每日摘要里的批准核对发现 | 日常最频繁，Planner 每拆一批就提及你 |
| 处理 blocked 的升级 | Multica，**Blocked 列**（任务会指派给你） | 指令约束 | 打回 2 次 / 验收不通过 2 次 / 换人后仍失败 / 线上故障已回滚 |
| `make publish` 发版 | 你的机器 | 不接进任何自动流程，`package.json` 和 `scripts/release.sh` 又受 CODEOWNERS 保护 | 你想发版的时候（仅 autoteam 自己这个仓库） |

看板上你只用管两列：**Backlog**（等你批准）和 **Blocked**（等你决断）。升级的任务会指派给你，所以「指派给我的」这个视图就是你的全部待办清单；每日摘要也会把两类合成一张「今天需要人决定的事」。其余的列都是 agent 之间在流转，不用盯。

中间两行是日常的，另外两行只在特定事件后出现。规则文件合并后同步到 Multica（`autoteam multica --apply`）**不用你管**：Planner 在验收时自己跑，用的是你的 multica 凭据，这条记在[已知的偏离](../concepts/invariants.md#已知的偏离)里。**这张表里的每一项都是"人还要介入"的成本**，「规则复盘」autopilot 每周盯的就是怎么把它变短。

## 提需求

- 在 Multica 的 Chat 里告诉 Planner；或者建任务、写清楚目标，指派给 Planner（状态 todo）。
- 需求不清楚时 Planner 会先在评论里问你，回复时 @Planner。
- 大需求让 Planner 拆，不要自己拆好了直接指派给 Implementer：绕过 Planner 就没人选人、没人验收。

## 批准任务

这是人在日常流转里唯一的操作。

- Planner 拆好的子任务在 backlog（待审核），它会在父任务评论里提及你。
- 看每个子任务的“为什么做 / 不做什么 / 验收标准”，值得做就改成“已批准”（approved），不值得做就改成 cancelled 并写一句原因。
- 可以一次批准多个。Planner 每个都会被叫醒一次，前面批次没完成的会先留着。
- **agent 也有改状态的权限**，平台拦不住它把任务改成已批准。每日摘要里有批准核对，发现 agent 批准的要处理。

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

每天 9:00 Planner 建一个“每日摘要”任务并通知你：进展、待你处理的事项、批准核对、各账号额度和花费。先看“今天需要人决定的事”。

## 修改规则文件

`.github/`、`.autoteam/`、`Makefile`、`.jscpd.json` 受 CODEOWNERS 保护，改动必须由你批准：

- 推荐让 Implementer 改：给 Planner 提需求，走正常流程，最后由你作为 Code Owner 批准 PR；
- 你自己开 PR 改：没有别的 Code Owner 能批准，需要临时把规则集改成 disabled，合并后恢复（会记在审计日志里）；
- 改了 registry、`autoteam.conf`，或 eject 出来的角色指令、autopilot（`.autoteam/instructions/`），合并后要同步到 Multica 才生效；升级 autoteam 版本（角色指令、autopilot 跟着包走）同理——这一步 Planner 在验收时自己做（`autoteam multica --apply` + `autoteam doctor`），你不用管。它跑不起来会在运营笔记里提及你。

## 每周

- 看[每周指标](metrics.md)和 Auditor 的报告；
- 抽读一两个合入的 PR，避免对代码变陌生；
- 每月核对一次 registry.yaml 里各家的额度规则。
