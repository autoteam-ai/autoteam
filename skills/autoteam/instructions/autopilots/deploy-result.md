---
title: 部署结果
role: planner
mode: run_only
trigger: webhook
---

按 `autoteam runbook progress` 处理，事件=`deploy`；传入 webhook 的 kind、sha、result、repo、run_url、issues、sync_instructions 原值；团队所有仓库共用这个 webhook，按 repo 定位项目和仓库。只处理本次 issues 清单；sync_instructions=true 时同步指令。
