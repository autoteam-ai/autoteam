---
title: 推进巡检
role: planner
mode: run_only
cron_key: AUTOTEAM_CRON_PATROL
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

按 .autoteam/planner.md 做一次推进巡检：

1. 派发已放行且前面批次已经全部 done 的任务：`todo` 且指派给 Planner 自己（人改到 `todo` 即放行，按 .autoteam/planner.md 的「派发」推进，不要退回 backlog，也不要评论请人批准）。
2. 处理失败和卡住的任务：todo 或 in_progress 状态但最近一次运行失败的，按 .autoteam/planner.md 的「换人」处理——先查任务有没有已经开好的 PR，有就交给 Reviewer 评审，没有才换人。换过仍失败的升级。
3. 补查 shipping 超过 `AUTOTEAM_SHIPPING_RECHECK_HOURS` 小时（读 .autoteam/autoteam.conf，默认 1）还没验收的任务，逐条线上验收（部署通知可能因为你的 runtime 离线被跳过）。
   PR 还是 OPEN 的，按 .autoteam/planner.md「验收」第 1 步查：已批准、检查通过、但 `.autoteam/scripts/merge-status.sh <PR>` 输出 none，就提及该任务的 Implementer 补开自动合并；补开过一次仍是 none 就升级给人。不要用你的身份跑 `merge-mode.sh` 判断合并模式（planner App 读不到 `allow_auto_merge`，会误判成 reviewer）。
4. 把各任务评论里的“范围外发现”拆进 backlog，先查重。
5. 对 in_progress、in_review 的任务跑 .autoteam/scripts/loop-guard.sh，到上限的升级给人。

没有要处理的事，只回复“本轮无事可做”，不要在任何任务下评论。
