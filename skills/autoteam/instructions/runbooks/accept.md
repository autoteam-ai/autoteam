---
description: 验收：部署通知、巡检补查或父任务整体验收时，在线上逐条验证并给出结论
---
先按待验收任务所属项目定位仓库；所有 `bash ./autoteam ...`、`.autoteam/scripts/...`、PR 和部署均在该项目仓库核对。验收不通过、评审打回、人给出反馈，一律回到原任务处理，不另开任务；先核对原描述和验收标准，仍成立就继续返工或验收。只有目标或范围确实变化且无法在原任务继续，才按 `intake` 的规则新建子任务并说明原因。

部署通知或巡检时，验收部署通知 `issues` 里的任务，或巡检补查到的已合并未 `done` 的任务。人批准并合并 PR 后，若人回复 @Planner，先确认 PR 已合并，再按下面流程直接验收（`AUTOTEAM_CODEOWNERS_GATE=off` 时不会出现这种任务）。

| 要做的事 | 命令 |
|---|---|
| PR | `<身份> gh pr list --search "<任务编号> in:title" --state all`、`<身份> gh pr view <PR> --json mergedAt,mergeCommit`。`<身份>` = `.autoteam/scripts/gh-app-token.sh --run planner` |
| PR 为什么没合并 | `<身份> gh pr view <PR> --json state,reviewDecision,statusCheckRollup` |

**先看它改了什么**：只要这个任务碰了 `.autoteam/`，或当前生效的指令源（包内 `skills/autoteam/instructions/**`，已 eject 时为 `.autoteam/instructions/**`），先跑 `bash ./autoteam multica --apply --only agents,autopilots` 同步，再 `bash ./autoteam doctor` 确认没有指令漂移。**合并到 main 不等于生效**——没同步的话 agent 手里还是旧指令，这一步不做验收就不算通过。跑不起来或者没权限，把错误贴进任务评论、用成员链接提及人，任务保持当前状态。

1. 确认它的 PR 已合并，而且合并提交已经部署（部署通知里的 sha 包含它：`git merge-base --is-ancestor <合并提交> <sha>`）。
   PR 还是 OPEN：先不验收。已批准、检查通过却没开自动合并的，由推进巡检的 `pr_remediation` 处理（提及 Implementer 重跑交付脚本），这里不重复处理。
2. 按验收标准逐条在线上验证，把截图、接口返回或命令输出贴进评论。只看线上真实结果，不看代码、不看 PR 描述。
3. 通过：评论 `【验收通过】<部署的 sha>` 加证据，状态设为 `done`。
4. 不通过：评论 `【验收不通过】` 加实际结果和预期的差异，在原任务上把状态设为 `in_progress`，提及该任务的 Implementer（任务的指派人）让它修，不另开任务。
   需要观察期、攒样本才能验完的：不靠每次部署重验，用 `multica issue wakeup create <任务> --kind at --at <到期时间> --instruction-file <文件>` 设一个任务级唤醒，到期时验收一次。
5. 线上故障（功能坏了，或者影响了已有功能）：先回滚 `<身份> gh workflow run rollback.yml -f sha=<最近一条【验收通过】里的 sha>`，再按 `escalate` 升级给人。不要重试。
6. 父任务整体验收由 `progress` 的 `barrier` 事件独占触发。按父任务验收标准在线上做一次整体验收：通过就评论 `【验收通过】<sha>` 加证据，把父任务设为 `done`，并用成员链接提及人告知完成；不通过就在父任务记录差异，回到对应的原子任务按上述返工流程处理，并遵守升级次数上限；不因整体验收失败另拆补充子任务。
