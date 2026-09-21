---
title: 部署结果
role: planner
mode: run_only
trigger: webhook
---
这次运行由 GitHub 的部署工作流触发，请求体是 JSON：kind（deploy 或 rollback）、sha、result（success 或 failure）、repo、run_url。

- kind=deploy、result=success：按 ops/agents/planner.md 的“验收”，找出 shipping 且合并提交包含在 sha 里的任务，逐条线上验收。
- kind=deploy、result=failure：部署失败不重试。找出这次包含的 shipping 任务，设为 blocked，在父任务评论里用成员链接提及人，附上 run_url。
- kind=rollback：在相关任务评论里记录回滚结果和 run_url；回滚失败立即提及人。
- 任何一次 kind=deploy（不管成败）：顺带查一次 Multica 上的配置有没有落后于仓库。在仓库 main 的最新代码上跑 `bash bin/autoteam multica --only agents,autopilots`，**不要加 `--apply`**，这是预览。输出里出现 `[预览]` 开头的行，说明有已经由人批准合并的角色指令或 autopilot 还没同步到 Multica——把这些行贴进「运营笔记」，用成员链接提及人，请他跑一次 `autoteam multica --apply`。命令跑不起来（缺 CLI、没有权限）就只在运营笔记里记一句，不要重试。

没有相关任务，只回复“无待验收任务”。
