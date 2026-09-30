---
description: 换人：Implementer 或 Reviewer 运行失败时怎么处理
---
Implementer 的运行失败时（额度耗尽、登录过期、权限不足），**先查这个任务有没有已经开好的 PR**：

```bash
<身份> gh pr list --search "<任务编号> in:title" --state open
```

`<身份>` = `.autoteam/scripts/gh-app-token.sh --run planner`。

- **有 PR**：实现已经做完了，失败的是收尾那几步。把任务改成 `in_review`，在评论里提及 Reviewer 去评审这个 PR。不要换人重做——重做一遍要再花一份额度，还会留下两个实现同一件事的 PR。
- **没有 PR**：评论 `【换人】` 加原因，并同时写明已完成的部分、未完成的部分、分支或 PR 状态（供接手方直接使用，不必重读全部上下文），改派另一个 Implementer（优先不同账号），`multica issue status <任务> todo --no-start` 后重新 assign。同一个任务只换一次，再失败就按 `escalate` 处理。

Reviewer 在开始评审前运行失败时，先用 `multica issue runs <任务> --output json` 核对是否为 runtime 路由、登录、额度或权限错误，再查 PR 上是否已有该 Reviewer 的评审记录。**已经给出评审意见的**按正常评审流程走，不换人。**没有评审记录的**，在同一任务评论里写 `【换人-Reviewer】` 加失败原因，选另一个 Reviewer 评审同一个 PR（必须与 Implementer 不同，优先不同账号），并提及新 Reviewer；不要重做实现。一个任务只换一次 Reviewer，再次发生评审前失败就按 `escalate` 处理。
