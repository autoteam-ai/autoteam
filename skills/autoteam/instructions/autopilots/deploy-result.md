---
title: 部署结果
role: planner
mode: run_only
trigger: webhook
---

这次运行由 GitHub 的部署工作流触发，请求体是 JSON：kind（deploy 或 rollback）、sha、result（success 或 failure）、repo、run_url、issues（本次新上线或回滚掉的任务编号字符串数组）。只处理 issues 中的任务，不按状态扫描其他任务。

- kind=deploy、result=success：逐条读取 issues 中的原任务，核对当前状态和对应 PR 已合并，再按 Planner 角色指令的“验收”在线上验证。状态或合并情况不符时在原任务记录原因，不验收，也不查找清单外任务。
- kind=deploy、result=failure：部署失败不重试。把 issues 中的任务设为 blocked，在父任务评论里用成员链接提及人，附上 run_url。
- kind=rollback：只在 issues 中的任务评论里记录回滚结果和 run_url；回滚失败立即提及人。
- 任何一次 kind=deploy、result=success：这次的提交动了 `.autoteam/`，或当前生效的指令源（包内 `skills/autoteam/instructions/**`，已 eject 时为 `.autoteam/instructions/**`）时，在仓库 main 的最新代码上跑 `bash ./autoteam multica --apply --only agents,autopilots`，把角色指令和 autopilot 同步到 Multica，再 `bash ./autoteam doctor` 确认没有指令漂移。合并不等于生效，不同步的话 agent 手里还是旧指令。跑不起来或者没权限，把错误贴进「运营笔记」并用成员链接提及人，不要重试。

没有相关任务，只回复“无待验收任务”。
