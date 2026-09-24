---
title: 老代码巡检
role: auditor
mode: create_issue
cron: 0 3 28 1,4,7,10 *
issue_title: 老代码巡检 {{date}}
---
找出一年没动过的模块，判断还有没有在用：

1. 用 git log 找出最后一次修改在 12 个月以前的文件和目录。
2. 对每个模块查引用（import、调用、路由、配置、定时任务），判断：在用、疑似没用、确定没用。
3. 疑似或确定没用的，写成“删除”或“合并”的独立小任务建议，附上判断依据。

按 .autoteam/auditor.md 提及 Planner，并把本任务设为 done。
