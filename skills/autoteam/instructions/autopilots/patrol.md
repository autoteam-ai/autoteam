---
title: 推进巡检
role: planner
mode: run_only
cron_key: AUTOTEAM_CRON_PATROL
---

按 `autoteam runbook progress` 处理，事件=`patrol`；由 runbook 运行 `autoteam next --check --all`，处理团队全部项目的清单（每项带 repo，逐项切换仓库）。
