---
title: 任务状态和唤醒
---

# 任务状态和唤醒

## 状态

Multica 的流程使用 7 个内置状态。旧工作区的 `shipping` 已退出流转；`autoteam multica --apply` 会将其中的任务迁回 `in_review`，再归档这个旧状态。命令里写的是 key，看板上显示的是名称。

| 设计中的状态 | key | 类型 | 类别 | 谁设置 | 下一步怎么被叫醒 |
|---|---|---|---|---|---|
| 待审核 | `backlog` | 内置 | unstarted | Planner 建子任务时，指派给自己 | 不启动运行；符合「放行分级」的由 Planner 自主放行，其余等人批准 |
| 待办 | `todo` | 内置 | unstarted | **放行**：人把 `backlog` 改成 `todo`，或 Planner 按「放行分级」自主放行（带 `【自主放行】` 评论，`AUTOTEAM_AUTO_APPROVE=on` 且未超每日上限），指派人仍是 Planner；Planner 派发时改指派为 Implementer | 人用 `autoteam approve <父任务> --apply` 时只叫醒 Planner 一次，后续批次用 `--no-start` 等批次屏障；界面批准后核对运行（见[界面批准后的唤醒核对](#界面批准后的唤醒核对)）；自主放行的 `urgent` / `high` 当次派发，`medium` / `low` 等下次巡检；人批准或批次解锁的任务被叫醒时直接派发；指派给 Implementer 即启动它 |
| 实现中 | `in_progress` | 内置 | started | Implementer 开工时，被打回或验收不通过后重新开工时 | 运行失败时平台回滚到 `todo`，巡检兜底 |
| 审核中 | `in_review` | 内置 | started | Implementer 提交 PR 后；Reviewer 批准后也不改，停在这里直到合并 | 评论里 @Reviewer；合并部署后部署 webhook 叫醒 Planner，巡检补查已合并超过 `AUTOTEAM_ACCEPT_RECHECK_HOURS` 小时没验收的 |
| 完成 | `done` | 内置 | done | Planner 验收通过后 | — |
| 升级 | `blocked` | 内置 | started | Planner | 在父任务评论里提及人 |
| 取消 | `cancelled` | 内置 | closed | 人或 Planner | — |

几点注意：

1. **放行就是把 `backlog` 改成 `todo`**，由人批准，或由 Planner 按「放行分级」自主放行（开关见[配置文件](../reference/config.md#autoteamconf)的 `AUTOTEAM_AUTO_APPROVE`）。不需要单独的“已批准”状态。人批准整个拆分时用 `autoteam approve <父任务> --apply`：前置批次已完成时只叫醒 Planner 一次并核对运行已生成，后续批次一律 `--no-start`；前置批次未完成时所有放行都用 `--no-start`，等批次屏障叫醒 Planner。手工在界面批准时见[界面批准后的唤醒核对](#界面批准后的唤醒核对)。
2. **打回和返工不占状态**。Reviewer 在 PR 上要求修改，并在评论里 @Implementer；Implementer 被 @ 后第一步把任务改回 `in_progress`。Planner 验收不通过时同样把任务改回 `in_progress` 并 @Implementer。打回次数由 `loop-guard.sh` 从 GitHub 评审记录和评论里统计，不依赖任何状态。
3. **评审通过不改状态**。部署通知按上次成功部署到本次提交间的 PR 生成 `issues` 清单，Planner 只验收清单内任务；巡检先运行 `autoteam next --check`，只补查清单里的已合并未 `done` 任务。两者共用 `progress` 推进 runbook，动作前查状态和评论，已有【验收通过】就跳过、不重复评论。需要观察期的任务由 Planner 设任务级 `multica issue wakeup create <任务> --kind at --at <到期时间>`，到期验收一次。
4. **旧状态迁移**。`shipping` 中的任务迁回 `in_review` 时使用 `--no-start`，不会因迁移叫醒 agent；全部迁移成功才归档状态。
5. **平台自己改状态时只写内置状态**：运行失败回滚到 `todo`；PR 带关闭关键字合并会直接设为 `done`。所以 PR 标题只写任务编号（建立关联），不写 `Closes XXX-123`。
6. **“批准”agent 也能做**。平台拦不住 agent 把任务从 `backlog` 改成 `todo`；除了按「放行分级」留下 `【自主放行】` 评论的，其余靠指令约束加每日摘要里的批准核对来发现；代码仍然要过检查和独立评审才能合入。

## 唤醒规则（Multica 0.5.1 起）

研究文档的第 4、6 步假设“自定义状态继承类别的行为”，例如把任务改成一个 todo 类别的自定义状态就会重新唤醒 Implementer。Multica 0.5（2026-09-18）改了状态模型：自定义状态只继承生命周期（unstarted / started / done / closed），**不再继承**停车、唤醒、失败回滚这些行为。Multica 0.5.1 又加入任务级 wakeup rule，可按事件或时间重新运行指定 agent。唤醒来源如下：

| 动作 | 结果 |
|---|---|
| 把任务指派给 agent（新建时指派也算），并且任务不在 `backlog` | 被指派的 agent 开始运行 |
| 把已指派的任务从 `backlog` 移到非终态 | 叫醒当前指派人 |
| 评论里提及 agent：`[@名字](mention://agent/<UUID>)` | 叫醒被提及的 agent（任何状态都生效） |
| 人对已指派任务发普通评论 | 按平台原有规则默认叫醒指派的 agent；`/note` 抑制这条默认唤醒（这两项未在 0.5.1+ 上复测） |
| 在任务上显式创建 wakeup rule | `comment.created` 等事件，或 `at`、`every`、`cron` 到时，按规则重新运行指定 agent |
| 一批子任务（同一个 `--stage`）全部完成 | 平台在父任务上发系统评论，叫醒父任务的指派人 |
| agent 派出去的运行最终失败（没有待执行的自动重试） | 平台在父任务上发系统评论，叫醒派活的 agent（Planner）去改派、跳过或结束 |
| autopilot 定时或 webhook 触发 | 叫醒 autopilot 指派的 agent |

Reviewer 等 CI 时用有期限、绑定原线程的 `--until-pr checks` 条件唤醒结束运行；唤醒后复核当前 PR head 和检查结果，失败仍打回。参见 [Reviewer 条件唤醒验收](../operations/reviewer-wakeup.md)。

### 界面批准后的唤醒核对

`backlog` → `todo` 这一行以**不带 `--no-start` 的 CLI 状态变更**为准；带 `--no-start` 不会启动运行。2026-09-26 本工作区里，人通过界面把 HDGCS-80、84、85 从 `backlog` 改为 `todo` 后都没有生成指派人的运行，原因仍待确认。依赖界面批准推进时，需用 `multica issue runs <任务>` 检查运行记录；这三个实例不能当作「界面改状态必然唤醒」的证据。

autoteam 的选择是：**让人对已指派任务的普通评论使用平台默认唤醒；角色之间交接继续显式指派或 @提及**。自定义状态只表示看板进度。`autoteam multica --apply` 不创建任务级 wakeup rule；需要单个任务定时复查或监听特定事件时，用 `multica issue wakeup create` 明确设置。

- agent 发的普通评论不会触发默认的指派人唤醒；人只想留个记录时，评论以 `/note` 开头以抑制默认唤醒。显式 `comment.created` 规则可按 `--filter-actor-type member|agent` 和 `--filter-actor-id` 限定作者；不要假定 `/note` 也会被显式事件规则忽略。规则会排除注册它的运行和由同一规则启动的运行所产生的事件（有来源标识时），但**不同规则互相触发仍可能循环**，监听人的回复时应过滤到那个人。
- `--no-start` 用于状态或指派变更时抑制自动启动，不能作为通用的唤醒规则开关。定时规则的触发不要求有人再次评论。
- 提及人要用成员链接 `[@名字](mention://member/<user_id>)`，它不会启动任何 agent；只写 `@名字` 不会被识别。

## 批次

Planner 拆分时用 `--stage` 标批次，先做的是第 1 批。后续批次提前批准时一律用 `--no-start` 放行；第 1 批全部完成后，批次屏障叫醒父任务的指派人（Planner），它按 `progress` 的 `barrier` 事件派发第 2 批里已批准的任务。第 1 批没全部完成，第 2 批就算被批准了，Planner 也不会派发。最后一批全 `done` 后，只有批次屏障负责父任务整体验收；部署结果和巡检均不做。已派发或已有【验收通过】的任务会跳过，不再发评论。

## 防止来回打转

| 情况 | 上限（autoteam.conf） | 到上限后 |
|---|---|---|
| 同一个 PR 被打回 | 2 次（`AUTOTEAM_MAX_REVIEW_REJECTIONS`） | Reviewer 不再打回，@Planner；Planner 升级给人 |
| 同一个任务验收不通过 | 2 次（`AUTOTEAM_MAX_ACCEPTANCE_FAILURES`） | Planner 升级给人 |
| 因额度或权限运行失败 | 换 1 次 Implementer | 仍失败则升级给人 |
| 线上故障 | 不重试 | 先回滚，再升级给人 |

次数由 `.autoteam/scripts/loop-guard.sh <任务编号>` 统计：打回次数来自 GitHub 上的 `CHANGES_REQUESTED` 评审，以及单账号试用模式下以【阻塞】开头的评审；验收不通过和换人次数来自 Planner 写的【验收不通过】【换人】评论。Planner 每次巡检重新计算，不依赖 agent 自己上报。

## 一个需求的完整走向

任务流转始终以任务所属项目为边界：Chat intake 先确定目标项目，父任务和子任务创建时显式传 `--project`；跨仓库需求按仓库拆子任务并放在各自项目中。自主放行的过去 24 小时名额按项目分别统计，使用各项目自己的配置。派发、巡检和验收的命令均在对应项目资源指向的仓库执行。

以“按日期导出订单”为例：

1. 人在 Chat 里告诉 Planner（或者建任务指派给 Planner）。Planner 拆出：查询接口、生成 CSV（第 1 批），导出页面（第 2 批），放进 `backlog`，提及人请他批准。
2. 人跑 `autoteam approve <父任务> --apply` 把三个任务从 `backlog` 改为 `todo`（指派人仍是 Planner），命令核对 Planner 的运行已生成。Planner 收到第 1 批的运行后立即派发；第 2 批先不动。
3. Planner 按额度选人，比如查询接口派给 `impl-claude`、评审给 `rev-codex`，生成 CSV 派给 `impl-codex`、评审给 `rev-claude`，在评论里写明理由。
4. Implementer 提交 PR、打开自动合并、把任务改为 `in_review` 并 @Reviewer；被打回一次后改回 `in_progress` 修改，再回到 `in_review`，第二次批准，检查通过后自动合并并部署。
5. 部署工作流仅在有新上线任务时，通过带 `issues` 字符串数组的 webhook 叫醒 Planner。Planner 只验收清单内任务，在线上验证通过后设为 `done`；第 1 批全部完成后被叫醒，派发导出页面。
