---
title: 老代码巡检
role: auditor
mode: create_issue
cron_key: AUTOTEAM_CRON_LEGACY_SWEEP
issue_title: 老代码巡检 {{date}}
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

找出一年没动过的模块，判断还有没有在用：

1. 用 git log 找出最后一次修改在 12 个月以前的文件和目录。
2. 对每个模块查引用（import、调用、路由、配置、定时任务），判断：在用、疑似没用、确定没用。
3. 疑似或确定没用的，写成“删除”或“合并”的独立小任务建议，附上判断依据。

按 .autoteam/auditor.md 提及 Planner，并把本任务设为 done。
