---
title: 每日摘要
role: planner
mode: create_issue
cron_key: AUTOTEAM_CRON_DAILY_DIGEST
issue_title: 每日摘要 {{date}}
subscriber: human
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

写今天的每日摘要，写在本任务的评论里，然后把本任务设为 done。

1. 进展：过去 24 小时完成的任务，正在进行的任务和各自状态。
2. 待人处理：backlog 里等批准的任务数；blocked 的任务、卡点和你的建议。
3. 批准核对：过去 24 小时从 backlog 变成 todo、且当时指派给 Planner 的任务，确认是人操作的（multica issue get 的活动记录或评论）。agent 不能批准任务，发现 agent 批准的单独列出来。
4. 额度和花费：registry.yaml 里每个账号下的 agent，用 multica runtime usage <runtime-id> --days 1 --output json 汇总 token 用量；按量计费的账号对照当日预算。
5. 今天需要人决定的事，每条一句话。
