---
title: 每日摘要
role: planner
mode: create_issue
cron: {{AUTOTEAM_CRON_DAILY_DIGEST}}
issue_title: 每日摘要 {{date}}
subscriber: human
---
写今天的每日摘要，写在本任务的评论里，然后把本任务设为 done。

1. 进展：过去 24 小时完成的任务，正在进行的任务和各自状态。
2. 待人处理：backlog 里等批准的任务数；blocked 的任务、卡点和你的建议。
3. 批准核对：过去 24 小时从 backlog 变成 approved 的任务，确认是人操作的（multica issue get 的活动记录或评论）。agent 不能批准任务，发现 agent 批准的单独列出来。
4. 额度和花费：registry.yaml 里每个账号下的 agent，用 multica runtime usage <runtime-id> --days 1 --output json 汇总 token 用量；按量计费的账号对照当日预算。
5. 今天需要人决定的事，每条一句话。
