---
title: 任务状态和唤醒
---

# 任务状态和唤醒

## 状态

Multica 的状态有内置的 7 个，另外 `autoteam multica --apply` 会建 1 个自定义状态 `shipping`。命令里写的是 key，看板上显示的是名称。

| 设计中的状态 | key | 类型 | 类别 | 谁设置 | 下一步怎么被叫醒 |
|---|---|---|---|---|---|
| 待审核 | `backlog` | 内置 | unstarted | Planner 建子任务时，指派给自己 | 不启动运行，等人批准 |
| 待办 | `todo` | 内置 | unstarted | **人批准**：把 `backlog` 改成 `todo`，指派人仍是 Planner；Planner 派发时改指派为 Implementer | 离开 backlog 会叫醒指派人 Planner，立即派发；指派给 Implementer 即启动它 |
| 实现中 | `in_progress` | 内置 | started | Implementer 开工时，被打回或验收不通过后重新开工时 | 运行失败时平台回滚到 `todo`，巡检兜底 |
| 审核中 | `in_review` | 内置 | started | Implementer 提交 PR 后 | 评论里 @Reviewer |
| 待上线 | `shipping` | 自定义 | started | Reviewer | 部署 webhook 叫醒 Planner；巡检补查超过 1 小时没验收的 |
| 完成 | `done` | 内置 | done | Planner 验收通过后 | — |
| 升级 | `blocked` | 内置 | started | Planner | 在父任务评论里提及人 |
| 取消 | `cancelled` | 内置 | closed | 人或 Planner | — |

几点注意：

1. **人批准就是把 `backlog` 改成 `todo`**。不需要单独的“已批准”状态：任务离开 backlog 本来就会叫醒指派人，指派人仍是 Planner，所以 Planner 醒来看到 `todo` 就知道已经批准。
2. **打回和返工不占状态**。Reviewer 在 PR 上要求修改，并在评论里 @Implementer；Implementer 被 @ 后第一步把任务改回 `in_progress`。Planner 验收不通过时同样把任务改回 `in_progress` 并 @Implementer。打回次数由 `loop-guard.sh` 从 GitHub 评审记录和评论里统计，不依赖任何状态。
3. **为什么保留 `shipping`**：它表示“已合并、等线上验收”。部署通知和巡检补查都靠它找任务；如果和 `in_review` 合并，就只能逐个查 PR，看板上也看不出哪些已经合进 main。
4. **类别创建后不能改**。建错了只能在界面里归档，再重新运行 `autoteam multica --apply`。
5. **平台自己改状态时只写内置状态**：运行失败回滚到 `todo`；PR 带关闭关键字合并会直接设为 `done`。所以 PR 标题只写任务编号（建立关联），不写 `Closes XXX-123`。
6. **“批准”agent 也能做**。平台拦不住 agent 把任务从 `backlog` 改成 `todo`，靠指令约束加每日摘要里的批准核对来发现；代码仍然要过检查和独立评审才能合入。

## 唤醒规则（Multica 0.5.1 起）

研究文档的第 4、6 步假设“自定义状态继承类别的行为”，例如把任务改成一个 todo 类别的自定义状态就会重新唤醒 Implementer。Multica 0.5（2026-09-18）改了状态模型：自定义状态只继承生命周期（unstarted / started / done / closed），**不再继承**停车、唤醒、失败回滚这些行为。Multica 0.5.1 又加入任务级 wakeup rule，可按事件或时间重新运行指定 agent。唤醒来源如下：

| 动作 | 结果 |
|---|---|
| 把任务指派给 agent（新建时指派也算），并且任务不在 `backlog` | 被指派的 agent 开始运行 |
| 把已指派的任务从 `backlog` 移到非终态 | 叫醒当前指派人 |
| 评论里提及 agent：`[@名字](mention://agent/<UUID>)` | 叫醒被提及的 agent（任何状态都生效） |
| 人对已指派任务发普通评论 | 默认叫醒指派的 agent；`/note` 抑制这条默认唤醒 |
| 在任务上显式创建 wakeup rule | `comment.created` 等事件，或 `at`、`every`、`cron` 到时，按规则重新运行指定 agent |
| 一批子任务（同一个 `--stage`）全部完成 | 平台在父任务上发系统评论，叫醒父任务的指派人 |
| agent 派出去的运行最终失败（没有待执行的自动重试） | 平台在父任务上发系统评论，叫醒派活的 agent（Planner）去改派、跳过或结束 |
| autopilot 定时或 webhook 触发 | 叫醒 autopilot 指派的 agent |

`backlog` → `todo` 这一行以**不带 `--no-start` 的 CLI 状态变更**为准；带 `--no-start` 不会启动运行。2026-09-26 本工作区里，人通过界面把 HDGCS-80、84、85 从 `backlog` 改为 `todo` 后都没有生成指派人的运行，原因仍待确认。依赖界面批准推进时，需检查运行记录；这三个实例不能当作「界面改状态必然唤醒」的证据。

autoteam 的选择是：**让人对已指派任务的普通评论使用平台默认唤醒；角色之间交接继续显式指派或 @提及**。自定义状态只表示看板进度。`autoteam multica --apply` 不创建任务级 wakeup rule；需要单个任务定时复查或监听特定事件时，用 `multica issue wakeup create` 明确设置。

- agent 发的普通评论不会触发默认的指派人唤醒；人只想留个记录时，评论以 `/note` 开头以抑制默认唤醒。显式 `comment.created` 规则可按 `--filter-actor-type member|agent` 和 `--filter-actor-id` 限定作者；不要假定 `/note` 也会被显式事件规则忽略。规则会排除注册它的运行和由同一规则启动的运行所产生的事件（有来源标识时），但**不同规则互相触发仍可能循环**，监听人的回复时应过滤到那个人。
- `--no-start` 用于状态或指派变更时抑制自动启动，不能作为通用的唤醒规则开关。定时规则的触发不要求有人再次评论。
- 提及人要用成员链接 `[@名字](mention://member/<user_id>)`，它不会启动任何 agent；只写 `@名字` 不会被识别。

## 批次

Planner 拆分时用 `--stage` 标批次，先做的是第 1 批。第 1 批全部完成后平台会叫醒父任务的指派人（Planner），它再派发第 2 批里已批准（人已改为 `todo`）的任务。第 1 批没全部完成，第 2 批就算被批准了，Planner 也不会派发。

## 防止来回打转

| 情况 | 上限（autoteam.conf） | 到上限后 |
|---|---|---|
| 同一个 PR 被打回 | 2 次（`AUTOTEAM_MAX_REVIEW_REJECTIONS`） | Reviewer 不再打回，@Planner；Planner 升级给人 |
| 同一个任务验收不通过 | 2 次（`AUTOTEAM_MAX_ACCEPTANCE_FAILURES`） | Planner 升级给人 |
| 因额度或权限运行失败 | 换 1 次 Implementer | 仍失败则升级给人 |
| 线上故障 | 不重试 | 先回滚，再升级给人 |

次数由 `.autoteam/scripts/loop-guard.sh <任务编号>` 统计：打回次数来自 GitHub 上的 `CHANGES_REQUESTED` 评审，以及单账号试用模式下以【阻塞】开头的评审；验收不通过和换人次数来自 Planner 写的【验收不通过】【换人】评论。Planner 每次巡检重新计算，不依赖 agent 自己上报。

## 一个需求的完整走向

以“按日期导出订单”为例：

1. 人在 Chat 里告诉 Planner（或者建任务指派给 Planner）。Planner 拆出：查询接口、生成 CSV（第 1 批），导出页面（第 2 批），放进 `backlog`，提及人请他批准。
2. 人把三个任务从 `backlog` 改为 `todo`（指派人仍是 Planner）。每改一个，Planner 就被叫醒一次：第 1 批的两个立即派发，第 2 批的先不动。
3. Planner 按额度选人，比如查询接口派给 `impl-claude`、评审给 `rev-codex`，生成 CSV 派给 `impl-codex`、评审给 `rev-claude`，在评论里写明理由。
4. Implementer 提交 PR、打开自动合并、把任务改为 `in_review` 并 @Reviewer；被打回一次后改回 `in_progress` 修改，再回到 `in_review`，第二次批准，检查通过后自动合并并部署。
5. 部署工作流通过 webhook 叫醒 Planner，它在线上验证通过后设为 `done`；第 1 批全部完成后被叫醒，派发导出页面。
