---
title: 整合审计
role: auditor
mode: create_issue
cron: {{AUTOTEAM_CRON_CONSOLIDATION}}
issue_title: 整合审计 {{date}}
---
做一次整合审计：

1. 跑 ops/agents/scripts/health-metrics.sh --md，和上一份整合审计对比，列出变差的指标。
2. 跑 npx --yes jscpd@5 --config .jscpd.json --reporters console .，结合 git log 找出过去 7 天新增的重复代码块，带文件路径和行号。
3. 找出该复用现有函数或组件、却重新实现的地方。

每条建议写成能独立完成、能单独评审的小任务，然后按 ops/agents/auditor.md 提及 Planner，并把本任务设为 done。
