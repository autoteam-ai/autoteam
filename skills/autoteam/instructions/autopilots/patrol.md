---
title: 推进巡检
role: planner
mode: run_only
cron_key: AUTOTEAM_CRON_PATROL
---

按 Planner 角色指令做一次推进巡检：

1. 第一步运行 `<身份> bash ./autoteam next --check`（`<身份>` = `.autoteam/scripts/gh-app-token.sh --run planner`）。退出码 0 表示清单为空，直接回复「本轮无事可做」并结束，不在任务下评论；退出码 2 表示读取失败，报告给人，不当作清单为空；退出码 1 只处理输出清单中的任务，不再全量扫描。按清单里的编号读取任务和必要的评论，再按类别处理：
   - `dispatchable`：按 Planner「派发」处理已放行、前置批次全部 done 的任务，不退回 backlog，也不请人再次批准。
   - `failed_run`：按 Planner「换人」处理；先查是否已有 PR，有就交 Reviewer，没有才换人；换过仍失败则升级。
   - `merged_unaccepted`：先看 `multica issue wakeup list <任务>`，跳过设有未到期验收唤醒的观察期任务；其余按 Planner「验收」逐条线上验证。父任务的子任务全 done、父任务仍未 done 且评论里没有【验收通过】时，按「验收」第 6 条补做整体验收。
   - `pr_remediation`：按输出的 PR 原因核对审批、检查及 `<身份> .autoteam/scripts/merge-status.sh <PR>` 的状态；已批准且检查通过却未开自动合并时写【补开自动合并】并提及 Implementer，让它用自己的身份跑 `.autoteam/scripts/open-pr.sh <PR>`；自动合并中的 PR 冲突时写【需要 rebase】并提及 Implementer，让它在原 PR 上解决冲突后推送。同一 PR 已提醒过而问题仍在，就按 Planner「升级」处理。不要用 Planner 身份跑 `merge-mode.sh`。
   - `loop_limit`：按 Planner「升级」处理达到上限的任务。
2. 处理清单中任务评论里的“范围外发现”：先查重，再按 Planner「放行分级」处理；之前因每日名额用完留在 backlog 的候选，出现在清单里时也按该规则放行。
