---
description: 推进：按部署通知、巡检清单或批次屏障，去重后派发、验收、整体验收及换人升级
---
按任务所属项目定位仓库；巡检清单每项带 `repo`，逐项切换到对应仓库，所有 `autoteam ...` 都在那里执行。入参为事件 `deploy`（webhook 的 kind、sha、result、repo、run_url、issues 字符串数组、sync_instructions 布尔）、`patrol`（`autoteam next --check --all` 清单，覆盖团队全部项目）、`barrier`（父任务）。`<身份>` = `autoteam token --run planner`。开工记下本轮开始的 UTC RFC3339 时间；只处理事件指定的任务；每轮按 **派发 → 验收 → 父任务整体验收 → 换人/升级** 排序，不相关步骤跳过。每个动作前重新读取状态和评论：`multica issue get <任务> --output json`；`multica issue comment list <任务> --roots-only --summary --compact --output json` 扫线程，再用 `--thread <id> --tail 30 --compact --output json` 展开相关线程。评论写当前目录 UTF-8 文件，用 `--content-file` 发。

1. **派发**：`barrier` 只检查父任务下一批已放行、前批全 `done` 的子任务；`patrol` 只检查 `dispatchable`。任务已指派 Implementer（含 `todo`）即跳过，不写【派发】；仅 `todo` 且指派 Planner、前批全 `done` 时按 `dispatch` 选人并指派。人已放行的不再请批准或退回 backlog。`deploy` 不派发。 跨需求依赖必须写入 metadata `autoteam.depends_on`，不能只写在描述里：`multica issue metadata set <任务 ID> --key autoteam.depends_on --type string --value "HDGCS-125,HDGCS-126"`。编号逗号分隔，全部 `done` 才可派发；编号不存在、读取失败或解析失败时不派发，先修正前提。 派发前运行 `<身份> autoteam next --output json`，仅派发其中 `dispatchable` 的任务；放行不代表前提已经满足。
2. **验收**：`deploy` 且 kind=deploy、result=success 只检查 `issues`；`patrol` 只检查 `merged_unaccepted`，先用 `multica issue wakeup list <任务>` 跳过未到期观察期。两者逐条先查任务评论及回复有无 `【验收通过】`：有则不再验收、不评论；无才核对任务状态和 PR 已合并，不符时仅记录原因，不查清单外任务。符合条件再按 `accept` 核对线上结果，成功写一次【验收通过】并设 `done`，失败在原任务返工。规则文件上线时按 `accept` 先同步指令并运行 doctor。`barrier` 不逐条重验子任务。
3. **父任务整体验收**：仅 `barrier` 且最后一批子任务全部 `done` 时执行；部署结果与巡检即使看到最后一个子任务，也不得执行。先查父任务评论及回复是否已有 `【验收通过】`；有就跳过、不评论。没有才按 `accept` 第 6 条在线上验收父任务，成功仅写一次【验收通过】并设 `done`，失败在原任务处理。批次屏障若非最后一批，到派发后结束。
4. **换人/升级**：`patrol` 的 `failed_run` 先查 PR，有 PR 交 Reviewer、无 PR 按 `reassign`；`loop_limit` 按 `escalate`。换人前查任务评论及回复是否已有 `【换人】` 或 `【换人-Reviewer】`：已有同类评论不再换同一角色、不再评论，仍失败按 `escalate`。`pr_remediation` 先核对 PR 审批、检查和 `<身份> autoteam merge-status <PR>`；批准且检查通过但未开自动合并，写【补开自动合并】并提及 Implementer 重跑 `autoteam open-pr <PR>`；自动合并中的 PR 冲突，写【需要 rebase】并提及 Implementer。发评论前用 `multica issue comment list <任务> --since <本轮开始时间> --compact --output json` 查该 PR 是否已有对应评论；有则跳过、不再评论。再查完整相关线程：此前一轮已提醒且问题仍在，按 `escalate`。不要以 Planner 身份运行 `autoteam merge-mode`。`deploy` 和 `barrier` 不做巡检换人。

5. **卡住任务**（仅 `patrol`，按 `reason` 处理；每步先重读任务和评论，已有同类痕迹不重复）：
   - `stalled`：先复核前提（依赖、PR、描述是否仍成立，不成立就在原任务改说明）；成立则评论 `【推进-停滞】` 提及当前指派人（agent）说明要继续的具体动作，指派给 Planner 的 `todo` 按 `dispatch`；已有 `【推进-停滞】` 且之后仍无活动，按 `reassign` 换人，换过仍无进展按 `escalate`；
   - `missing_wakeup` / `wakeup_overdue` 先分归属：Reviewer 的 PR 检查等待（原线程、head、2h 期限）交 Reviewer 按原线程、head 和原期限处理，Planner 不代注册、不续期、不换 agent，只在原线程提及 Reviewer 一次；仅 Planner 自己的等待走下面两条。
   - `missing_wakeup`：按 `reason` 的等待项用 `dispatch` 的「依赖方唤醒」补注册，写一条 `/note【补注册唤醒】`，不另提醒；
   - `wakeup_overdue`：复核 `reason` 的前提，已满足就直接推进（派发、验收或叫醒指派人）；未满足则重注册一次并 `/note【重注册唤醒】`，已有此痕迹仍逾期则换人或按外部前提处理；
   - `merged_unaccepted`：超过观察上限不再续期，按 `accept` 直接验收；前提仍缺的按外部前提处理。
   **外部前提**（集成、人工配置等 agent 自己补不了的）：先看任务评论有无 `【前提升级】`，没有才升级一次——`blocked` 并指派给人（按 `escalate`），评论 `【前提升级】` 写明要什么、怎么给；再注册 `--event comment.created --filter-actor-type member --filter-actor-id <人> --expires-in 72h --on-timeout wake`。期满被叫醒：前提已满足则推进；未满足且只有一条 `【前提升级】`，评论 `【前提再次升级】` 并不再注册唤醒；两条都有则静默。人在期间回复则按 `intake` 处理。
   巡检动作之外无事可做时不评论。

`patrol` 中运行 `<身份> autoteam next --check --all`：退出码 0 为清单为空，回复「本轮无事可做」，不在任务评论；退出码 2 向人报告读取失败，不当作空清单；退出码 1 只处理清单任务。清单里的范围外发现先查重再按 `release` 处理；因每日名额耗尽留在 backlog 的候选也按 `release`。不全量扫描。

`deploy` 的 kind=deploy、result=failure：不重试；先查任务状态及父任务评论是否已记录相同 run_url 的部署失败，已记录则跳过，否则将 issues 中任务设为 `blocked`，在父任务评论提及人并附 run_url。kind=rollback：先查任务评论有无相同 run_url 的回滚结果，已有则跳过，否则只在 issues 中任务记录结果和 run_url，失败立即提及人。两者不做上述派发或验收。`sync_instructions=true` 表示部署触及规则文件，即使 issues 为空也要同步。任何成功部署若触及团队仓库的 `.autoteam/` 或当前生效的 `skills/autoteam/instructions/**`（eject 后为 `.autoteam/instructions/**`），即使 issues 为空，也须在 main 最新代码运行 `autoteam multica --apply --only agents,autopilots` 和 `autoteam doctor`；失败写运营笔记并提及人，不重试。`issues` 为空且无同步工作时仅回复「无待验收任务」。
