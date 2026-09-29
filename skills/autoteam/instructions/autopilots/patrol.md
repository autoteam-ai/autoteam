---
title: 推进巡检
role: planner
mode: run_only
cron_key: AUTOTEAM_CRON_PATROL
---

按 Planner 角色指令做一次推进巡检：

1. 派发已放行且前面批次已经全部 done 的任务：`todo` 且指派给 Planner 自己（人或你自主放行到 `todo` 即放行，按 Planner 角色指令的「派发」推进，多个任务时按「放行分级」的优先级排先后，不要退回 backlog，也不要评论请人批准）。
2. 处理失败和卡住的任务：todo 或 in_progress 状态但最近一次运行失败的，按 Planner 角色指令的「换人」处理——先查任务有没有已经开好的 PR，有就交给 Reviewer 评审，没有才换人。换过仍失败的升级。
3. 用 `<身份> gh pr list --state merged` 查最近合并的 PR，对上还没 `done` 的任务，合并后超过 `AUTOTEAM_ACCEPT_RECHECK_HOURS` 小时（读 .autoteam/autoteam.conf，默认 1）的逐条线上验收（部署通知可能因为你的 runtime 离线被跳过），只验收任务本身。父任务的子任务全 `done`、父任务仍未 `done` 且评论里没有【验收通过】的，才按 Planner「验收」第 6 条补做整体验收。
   `in_review` 且 PR 还是 OPEN 的，这里是自动合并漏开的唯一兜底：用 `<身份> gh pr view <PR> --json state,reviewDecision,statusCheckRollup` 看审批和检查，`reviewDecision` 是 APPROVED、检查全部通过，但 `<身份> .autoteam/scripts/merge-status.sh <PR>` 输出 none，就在任务评论里写 `【补开自动合并】<PR 链接>` 并提及该任务的 Implementer，让它用自己的身份跑 `.autoteam/scripts/open-pr.sh <PR>`（你的 App 没有开自动合并的权限）。这个 PR 已经有过一条【补开自动合并】评论、仍然是 none，就按 Planner 角色指令「升级」升级给人，不再提及。输出 queued / auto 时再用 `<身份> gh pr view <PR> --json mergeable` 看冲突：是 CONFLICTING 就在任务评论里写 `【需要 rebase】<PR 链接>` 并提及该任务的 Implementer，让它在原 PR 上同步 main、解决冲突（保留双方规则）后重新推送（合并队列会移出冲突的 PR，不处理就永远合并不了）；这个 PR 已经有过一条【需要 rebase】评论、仍然是 CONFLICTING，就按 Planner 角色指令「升级」升级给人，不再提及。输出 merged，输出 queued / auto 且不冲突，或者审批、检查还没满足，就等下一轮，不催。不要用你的身份跑 `merge-mode.sh` 判断合并模式（planner App 读不到 `allow_auto_merge`，会误判成 reviewer）。
4. 把各任务评论里的“范围外发现”拆进 backlog，先查重，再按 Planner 角色指令的「放行分级」处理：符合条件的自主放行，其余请人批准。之前因每日名额用完留在 backlog 的候选，有名额了也在这一步放行。
5. 对 in_progress、in_review 的任务跑 .autoteam/scripts/loop-guard.sh，到上限的升级给人。

没有要处理的事，只回复“本轮无事可做”，不要在任何任务下评论。
