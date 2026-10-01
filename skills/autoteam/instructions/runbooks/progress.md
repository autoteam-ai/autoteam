---
description: 推进：按部署通知、巡检清单或批次屏障，去重后派发、验收、整体验收及换人升级
---
入参为事件 `deploy`（webhook 的 kind、sha、result、repo、run_url、issues 字符串数组、sync_instructions 布尔）、`patrol`（`autoteam next --check` 清单）、`barrier`（父任务）。`<身份>` = `.autoteam/scripts/gh-app-token.sh --run planner`。开工记下本轮开始的 UTC RFC3339 时间；只处理事件指定的任务；每轮按 **派发 → 验收 → 父任务整体验收 → 换人/升级** 排序，不相关步骤跳过。每个动作前重新读取状态和评论：`multica issue get <任务> --output json`；`multica issue comment list <任务> --roots-only --summary --compact --output json` 扫线程，再用 `--thread <id> --tail 30 --compact --output json` 展开相关线程。评论写当前目录 UTF-8 文件，用 `--content-file` 发。

1. **派发**：`barrier` 只检查父任务下一批已放行、前批全 `done` 的子任务；`patrol` 只检查 `dispatchable`。任务已指派 Implementer（含 `todo`）即跳过，不写【派发】；仅 `todo` 且指派 Planner、前批全 `done` 时按 `dispatch` 选人并指派。人已放行的不再请批准或退回 backlog。`deploy` 不派发。
2. **验收**：`deploy` 且 kind=deploy、result=success 只检查 `issues`；`patrol` 只检查 `merged_unaccepted`，先用 `multica issue wakeup list <任务>` 跳过未到期观察期。两者逐条先查任务评论及回复有无 `【验收通过】`：有则不再验收、不评论；无才核对任务状态和 PR 已合并，不符时仅记录原因，不查清单外任务。符合条件再按 `accept` 核对线上结果，成功写一次【验收通过】并设 `done`，失败在原任务返工。规则文件上线时按 `accept` 先同步指令并运行 doctor。`barrier` 不逐条重验子任务。
3. **父任务整体验收**：仅 `barrier` 且最后一批子任务全部 `done` 时执行；部署结果与巡检即使看到最后一个子任务，也不得执行。先查父任务评论及回复是否已有 `【验收通过】`；有就跳过、不评论。没有才按 `accept` 第 6 条在线上验收父任务，成功仅写一次【验收通过】并设 `done`，失败在原任务处理。批次屏障若非最后一批，到派发后结束。
4. **换人/升级**：`patrol` 的 `failed_run` 先查 PR，有 PR 交 Reviewer、无 PR 按 `reassign`；`loop_limit` 按 `escalate`。换人前查任务评论及回复是否已有 `【换人】` 或 `【换人-Reviewer】`：已有同类评论不再换同一角色、不再评论，仍失败按 `escalate`。`pr_remediation` 先核对 PR 审批、检查和 `<身份> .autoteam/scripts/merge-status.sh <PR>`；批准且检查通过但未开自动合并，写【补开自动合并】并提及 Implementer 重跑 `open-pr.sh <PR>`；自动合并中的 PR 冲突，写【需要 rebase】并提及 Implementer。发评论前用 `multica issue comment list <任务> --since <本轮开始时间> --compact --output json` 查该 PR 是否已有对应评论；有则跳过、不再评论。再查完整相关线程：此前一轮已提醒且问题仍在，按 `escalate`。不要以 Planner 身份运行 `merge-mode.sh`。`deploy` 和 `barrier` 不做巡检换人。

`patrol` 中运行 `<身份> bash ./autoteam next --check`：退出码 0 为清单为空，回复「本轮无事可做」，不在任务评论；退出码 2 向人报告读取失败，不当作空清单；退出码 1 只处理清单任务。清单里的范围外发现先查重再按 `release` 处理；因每日名额耗尽留在 backlog 的候选也按 `release`。不全量扫描。

`deploy` 的 kind=deploy、result=failure：不重试；先查任务状态及父任务评论是否已记录相同 run_url 的部署失败，已记录则跳过，否则将 issues 中任务设为 `blocked`，在父任务评论提及人并附 run_url。kind=rollback：先查任务评论有无相同 run_url 的回滚结果，已有则跳过，否则只在 issues 中任务记录结果和 run_url，失败立即提及人。两者不做上述派发或验收。`sync_instructions=true` 表示部署触及规则文件，即使 issues 为空也要同步。任何成功部署若触及 `.autoteam/` 或当前生效的 `skills/autoteam/instructions/**`（eject 后为 `.autoteam/instructions/**`），即使 issues 为空，也须在 main 最新代码运行 `bash ./autoteam multica --apply --only agents,autopilots` 和 `bash ./autoteam doctor`；失败写运营笔记并提及人，不重试。`issues` 为空且无同步工作时仅回复「无待验收任务」。
