---
title: agent 成绩单
role: auditor
mode: create_issue
cron_key: AUTOTEAM_CRON_SCORECARD
issue_title: agent 成绩单 {{date}}
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

出过去 7 天的 agent 成绩单，写在本任务的评论里。

对 registry.yaml 里每个 role 为 implementer 的 agent 统计：

- 完成任务数：过去 7 天变成 done、指派人是它的任务；
- 一次通过率：这些任务里 PR 从没被打回的比例（`.autoteam/scripts/gh-app-token.sh --run planner .autoteam/scripts/loop-guard.sh <任务>` 的 review_rejections 为 0）；
- 平均返工轮次；
- 验收不通过次数；
- 单任务花费：multica issue usage <任务> --output json 的 token 用量平均值。

用表格输出，指出明显偏低的 agent 和可能的原因，然后按 .autoteam/auditor.md 提及 Planner，并把本任务设为 done。
如果铸不出 planner token，在报告里明确写「loop-guard 未运行，数字为人工归纳」。
