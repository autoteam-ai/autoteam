---
title: 每周指标
---

# 每周指标

这套流程有没有用，要看数字，而且看趋势比看绝对值重要。

## 每周关注的五个数

| 指标 | 从哪里来 | 说明 |
|---|---|---|
| Reviewer 一次通过率 | 周度健康报告的成绩单一节；`health-metrics.sh` 的 `first_pass_pct` | 太低：任务拆得太大，或 Implementer 不行；太高（接近 100%）：Reviewer 可能在放水 |
| 验收一次通过率 | 周度健康报告的成绩单一节（【验收不通过】次数） | 低说明验收标准没写清，或实现和需求有偏差 |
| 升级到人的次数 | 每日摘要里的 blocked | 越来越多：流程在空转，要看是哪类升级 |
| 各 agent 用量 | 周度健康报告的成绩单一节（按 agent 汇总，单列 autopilot 用量） | 突然变高：任务变大了，或某个 agent 在打转；autopilot 那一行变高：某个定时任务太频繁 |
| 重复代码占比趋势 | 周度健康报告的整合审计一节（`duplication_pct`） | 只降不升；涨了就是“向外长而不向内整合” |
| **人工介入次数** | `health-metrics.sh` 的 `human_7d`；规则复盘 | 人自己提交和评审代码的次数。**这是判断规则有没有在变好的唯一客观指标，目标是下降**；连续两周上升就该人工复盘 |

## health-metrics.sh

Auditor 每周跑，你也可以随时在仓库里跑：

```bash
.autoteam/scripts/health-metrics.sh          # Markdown 表格
.autoteam/scripts/health-metrics.sh --json   # JSON
```

| 字段 | 含义 |
|---|---|
| `duplication_pct` | 重复代码占比（jscpd，配置在 .jscpd.json） |
| `legacy_touch_pct` | 近 30 天改过的文件里，上一次改动在一年以前的比例：老代码有没有人维护 |
| `rework_14d_pct` | 近 14 天改过的文件里，前 14 天也改过的比例：两周内返工 |
| `prs_7d.merged` | 近 7 天合并的 PR 数 |
| `prs_7d.size_p50` / `size_p75` | PR 改动行数的中位数和 75 分位 |
| `prs_7d.first_pass_pct` | 近 7 天合并的 PR 里，从没被打回的比例 |
| `prs_7d.avg_rejections` | 平均打回次数 |
| `human_7d.commits` / `human_7d.reviews` | 近 7 天人（`AUTOTEAM_OWNER`）自己提交、评审 PR 的次数 |
| `approvals_7d.auto.count` / `approvals_7d.human.count` | 近 7 天自主放行 / 人批准的任务数；以 backlog→todo 活动记录为准，Planner 代人操作需有 `【人工授权放行】` 评论 |
| `approvals_7d.auto.cancelled_pct` / `approvals_7d.human.cancelled_pct` | 各组批准任务后来被成员取消的比例 |
| `approvals_7d.auto.review_rejected_pct` / `approvals_7d.human.review_rejected_pct` | 各组有 PR 被要求修改（`CHANGES_REQUESTED` 或 `【阻塞】`）的任务比例 |
| `approvals_7d.auto.acceptance_failed_pct` / `approvals_7d.human.acceptance_failed_pct` | 各组出现 `【验收不通过】` 评论的任务比例 |

比例的分母是相应组的批准任务数，同一任务多次打回只计一次；分母为零时是 `null`。Multica 不可用时整个 `approvals_7d` 为 `null`；GitHub 不可用时评审打回率为 `null`。脚本需要当前身份能读取本项目任务及其历史、评论。任务历史、完整评论和 PR 评审数据通过临时文件传入 jq，避免超过命令行单参数大小上限；退出时清理临时文件。

**收紧阈值：**任意连续 7 天，自主放行任务被人取消的比例 **超过 20%**，Planner 就提任务请人把 `AUTOTEAM_AUTO_APPROVE_MAX_PER_DAY` 调小，或关闭自主放行。对照同窗口人批准任务的取消率、打回率和验收失败率，查清偏差后再决定改动。

跨文件调用数这类指标和语言强相关，脚本没有内置；需要的话在 Auditor 的 runbook 里加上你项目的计算方法。

## 看 Auditor 的报告

两份报告都会建成任务（create_issue），并 @Planner 把值得做的拆进 backlog；某一节相对上一份没有变化时只写一句「无变化」：

- **周度健康报告**（`AUTOTEAM_CRON_HEALTH`）：四节。整合审计——新增的重复实现、该复用却重写的地方；agent 成绩单——哪个 Implementer 该多派、哪个该少派，Planner 选人时会参考，用量按 agent 汇总（`multica agent tasks`），挂在 autopilot 名下的运行不在任何任务名下，所以单列一行，不再用按任务加总当总量；老代码巡检——一年没动、可能已经没用的模块；规格对账——任务的验收标准和实际代码不一致的地方。
- **月度方向报告**（`AUTOTEAM_CRON_DIRECTION`）：两节。前沿扫描——扫描 A 类流程前提、B 类 AI 工程实践和 C 类项目技术栈方向，指出需调整的文件或参数及 B、C 类结论的时机；路线图对账——还没做的目标，以及不变量的偏离。

Planner 拆出来的整改任务一样要你批准。业界经验是固定拿出 15–25% 的容量做整合和偿债，作为常态而不是一次性冲刺。

统计窗口从上一份同类报告算起；没有上一份时取过去 30 天。运行频率由 `AUTOTEAM_CRON_HEALTH` 和 `AUTOTEAM_CRON_DIRECTION` 决定。

## 规则复盘（周一 12:00）

Planner 每周读这一周的 Auditor 报告、人工介入记录和自己的运营笔记，产出四类建议：往 `playbook.md` 加一条经验、调一个 `autoteam.conf` 参数、改一段角色指令、补一个流程缺口。每条都要有证据和具体改法，拆成任务等你批准。

判断标准只有一个：**这一条能不能减少下一周的人工介入。** 这是整套流程"越来越符合人工期望"的实现方式——不是靠 agent 自觉，是靠把每次介入的原因变成规则。
