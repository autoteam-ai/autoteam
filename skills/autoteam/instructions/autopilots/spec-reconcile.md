---
title: 规格对账
role: auditor
mode: create_issue
cron_key: AUTOTEAM_CRON_SPEC_RECONCILE
issue_title: 规格对账 {{date}}
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

对账上一份同类报告以来完成任务的验收标准和实际代码；找不到上一份时取过去 30 天：

1. 列出统计窗口内变成 done 的任务，读每个任务描述里的验收标准。
2. 对照当前代码和线上行为，找出不一致：标准写了但没做、做了但标准没写、做法和描述不符。
3. 每处不一致写明任务编号、文件路径，以及建议改代码还是改任务描述。

按 Auditor 角色指令提及 Planner，并把本任务设为 done。
