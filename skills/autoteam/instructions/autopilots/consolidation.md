---
title: 整合审计
role: auditor
mode: create_issue
cron_key: AUTOTEAM_CRON_CONSOLIDATION
issue_title: 整合审计 {{date}}
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

做一次整合审计：

1. 跑 .autoteam/scripts/health-metrics.sh --md，和上一份整合审计对比，列出变差的指标。
2. 跑 npx --yes jscpd@5 --config .jscpd.json --reporters console .，结合 git log 找出过去 7 天新增的重复代码块，带文件路径和行号。
3. 找出该复用现有函数或组件、却重新实现的地方。

每条建议写成能独立完成、能单独评审的小任务，然后按 .autoteam/auditor.md 提及 Planner，并把本任务设为 done。
