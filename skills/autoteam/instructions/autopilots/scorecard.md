---
title: agent 成绩单
role: auditor
mode: create_issue
cron: {{AUTOTEAM_CRON_SCORECARD}}
issue_title: agent 成绩单 {{date}}
---
出过去 7 天的 agent 成绩单，写在本任务的评论里。

对 registry.yaml 里每个 role 为 implementer 的 agent 统计：

- 完成任务数：过去 7 天变成 done、指派人是它的任务；
- 一次通过率：这些任务里 PR 从没被打回的比例（.autoteam/scripts/loop-guard.sh <任务> 的 review_rejections 为 0）；
- 平均返工轮次；
- 验收不通过次数；
- 单任务花费：multica issue usage <任务> --output json 的 token 用量平均值。

用表格输出，指出明显偏低的 agent 和可能的原因，然后按 .autoteam/auditor.md 提及 Planner，并把本任务设为 done。
