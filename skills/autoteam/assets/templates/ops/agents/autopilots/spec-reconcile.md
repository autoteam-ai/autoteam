---
title: 规格对账
role: auditor
mode: create_issue
cron: 0 9 * * 5
issue_title: 规格对账 {{date}}
---
对账本周完成任务的验收标准和实际代码：

1. 列出过去 7 天变成 done 的任务，读每个任务描述里的验收标准。
2. 对照当前代码和线上行为，找出不一致：标准写了但没做、做了但标准没写、做法和描述不符。
3. 每处不一致写明任务编号、文件路径，以及建议改代码还是改任务描述。

按 ops/agents/auditor.md 提及 Planner，并把本任务设为 done。
