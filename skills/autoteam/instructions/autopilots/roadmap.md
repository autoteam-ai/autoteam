---
title: 路线图对账
role: planner
mode: run_only
cron_key: AUTOTEAM_CRON_ROADMAP
---
对照项目目标做一次路线图对账：

1. 读 README、AGENTS.md 和 docs 里的目标或路线图，列出还没做的部分。
2. 和现有任务（backlog、todo、进行中的）查重。
3. 缺的部分按 .autoteam/planner.md 的“收到需求”拆进 backlog，在新的父任务评论里用成员链接提及人，请他批准。

再做一次不变量对账（项目有 docs/concepts/invariants.md 时）：逐条检查四条不变量的“怎么验证”还成不成立，以及最近合并的改动有没有产生表里没登记的偏离。发现问题写成任务放进 backlog，说明破坏的是哪一条。

两项都没有缺口，只回复“路线图无缺口”，不要评论。
