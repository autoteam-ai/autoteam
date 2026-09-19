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

没有相关任务，只回复“无待验收任务”。
