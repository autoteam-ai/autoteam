---
description: 放行分级：判断 backlog 子任务能否自主放行，每日名额怎么数，怎么放行
---
放行就是把任务从 `backlog` 改成 `todo`。`.autoteam/autoteam.conf` 的 `AUTOTEAM_AUTO_APPROVE=on` 时，符合下面**全部**条件的任务由你自主放行，其余仍由人放行。

**自主放行的条件**（缺一条都不行）：

1. 不碰受保护路径：把预计改动文件传给 `.autoteam/scripts/protected-paths.sh --files <文件...>`，输出命中路径且退出码为 0 就不能自主放行；退出码 2 是判断出错，也不能自主放行。预计会改到哪些文件说不清的，按碰了处理；
2. 不涉及凭据、权限、部署、回滚、数据删除、对外发布；
3. 单个子任务不超过 `AUTOTEAM_PR_MAX_LINES`，整个需求不超过 3 个子任务；
4. 不是新功能，也不改变方向——新功能和方向性需求值不值得做，由人决定。

Auditor 报告和前沿扫描的建议满足以上条件也可以自主放行，但优先级最高只能设为 `medium`。拿不准是否满足的，按不满足处理：留在 `backlog` 请人批准。

**不自主放行**：`AUTOTEAM_AUTO_APPROVE` 不是 `on`；或 `bash ./autoteam status --check` 显示已暂停（Chat 对话里也要查）；或当日名额已用完。

**每日上限**：放行前数过去 24 小时里你发过 `【自主放行】` 评论的任务数：

1. 用 `multica issue list --project <项目 ID> --limit 100 --offset <N> --fields id,last_activity_at --output json` 翻完全部页（`has_more` 为 false 为止，包括已关闭的任务），留下 `last_activity_at` 在 24 小时内的任务；
2. 对每个留下的任务跑 `multica issue comment list <任务> --since <24 小时前的 RFC3339 时间> --output json`，数作者是你、正文以 `【自主放行】` 开头的评论，一个任务只算一次。

任何一步报错、翻页没翻完，或者结果不确定，就当名额已用完，本次不自主放行。达到 `AUTOTEAM_AUTO_APPROVE_MAX_PER_DAY` 就不再自主放行。候选多于剩余名额时按优先级从高到低放行，剩下的留在 `backlog`，不请人批准，下次有名额再放。

**放行动作**：任务建的时候已设好 `--priority`。在任务上评论 `【自主放行】`，逐条写明满足哪几条条件和优先级，然后 `multica issue status <任务> todo --no-start`（`--no-start` 避免叫醒你自己，派发按 `dispatch` 里的优先级来）。 跨需求依赖必须写入 metadata `autoteam.depends_on`，不能只写在描述里：`multica issue metadata set <任务 ID> --key autoteam.depends_on --type string --value "HDGCS-125,HDGCS-126"`。编号逗号分隔，全部 `done` 才可派发；编号不存在、读取失败或解析失败时不派发，先修正前提。 派发前运行 `<身份> bash ./autoteam next --output json`，仅派发其中 `dispatchable` 的任务；放行不代表前提已经满足。
