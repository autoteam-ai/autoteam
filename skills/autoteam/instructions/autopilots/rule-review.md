---
title: 规则复盘
role: planner
mode: create_issue
cron_key: AUTOTEAM_CRON_RULE_REVIEW
issue_title: 规则复盘 {{date}}
subscriber: human
---

做一次规则复盘，写在本任务的评论里，然后把本任务设为 done。

这是复盘经验和规则的地方：agent 团队跑得好不好，最终看**人还要介入多少次**。

## 读这些

1. 本周的 Auditor 报告：周度健康报告、月度方向报告（有新的一份时）。
2. `autoteam metrics --md`，重点看 `human_7d`（人自己提交和评审了多少次）和一次通过率的趋势。
3. 本周所有 `blocked` 过的任务，以及人在任务里留的评论——**每一条人工介入都是一次规则缺失的证据**。
4. 各项目的「运营笔记」任务（`autoteam projects` 列出的每个项目一条），只读最近 7 天：`multica issue comment list <运营笔记任务> --since <7 天前的 RFC3339 时间> --compact --output json`，不读更早的评论。
5. `autoteam playbook` 现在有什么。

## 产出

只提**能落成一个独立小任务**的建议，每条要有证据（哪个任务、哪次失败、哪个数字）和具体改法：

| 类型 | 改哪里 |
|---|---|
| 删除 / 合并 | 删除失效规则或合并重复规则，写明证据与替代关系 |
| 经验固化 | 团队仓库 `.autoteam/playbook.md`（跨项目通用）或 `.autoteam/projects/<仓库>/playbook.md`（单个项目）加一条 |
| 参数调整 | 团队仓库 `.autoteam/autoteam.conf` 或项目的 `project.conf` 里某个 `AUTOTEAM_*`，写明从多少改到多少、依据是什么 |
| 指令修订 | 当前生效的角色指令（已 eject 时为 `.autoteam/instructions/<角色>.md`，否则为包内指令）的具体段落 |
| 流程缺口 | 需要新脚本或新检查的，说明它要挡住什么 |

新增规则须说明替换或删掉哪条旧规则；说不出来时优先放进 playbook。把建议按 Planner 的“收到需求”拆进 backlog，再按「放行分级」处理。规则文件的改动走 PR 评审，对应任务按放行分级由人或你放行。判断标准：能删的规则优先于新增的规则；建议能否减少下一周的人工介入？不能就不提。

本周人工介入为零、指标没有恶化时，只回复“本周无需调整”，不要为了有产出而提建议。
