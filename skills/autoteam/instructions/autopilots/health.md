---
title: 周度健康报告
role: auditor
mode: create_issue
cron_key: AUTOTEAM_CRON_HEALTH
issue_title: 周度健康报告 {{date}}
---

出一份周度健康报告，写在本任务的评论里。统计窗口从上一份同类报告算起，找不到上一份时取过去 30 天。分下面四节；某节相对上一份没有变化，就只写一句「无变化」，不展开。

## 1. 整合审计

1. 跑 .autoteam/scripts/health-metrics.sh --md，和上一份报告对比，列出变差的指标。
2. 跑 npx --yes jscpd@5 --config .jscpd.json --reporters console .，结合 git log 找出窗口内新增的重复代码块，带文件路径和行号。
3. 找出该复用现有函数或组件、却重新实现的地方。

## 2. agent 成绩单

对 registry.yaml 里每个 role 为 implementer 的 agent 统计，用表格输出：

- 完成任务数：窗口内变成 done、指派人是它的任务；
- 一次通过率：这些任务里 PR 从没被打回的比例（`.autoteam/scripts/gh-app-token.sh --run planner .autoteam/scripts/loop-guard.sh <任务>` 的 review_rejections 为 0）；平均返工轮次、验收不通过次数；
- 用量：按 agent 汇总，不要用按任务加总当总量（挂在 autopilot 名下的运行不在任何任务名下，会少算）。对 `multica agent list` 里的每个 agent 跑 `multica agent tasks <id> --limit 200 --output json`（满页时用 `--before` 翻到窗口之前），取 `created_at` 在窗口内的运行，累加 `usage[]` 里各项 token，得出该 agent 的运行数和 token；其中 `kind == "autopilot"` 的运行另列一行「autopilot」，单独给出运行数和 token。账号总量可用 `multica runtime usage <runtime-id> --days <窗口天数> --output json` 核对。

指出明显偏低的 agent 和可能的原因。铸不出 planner token 时，写「loop-guard 未运行，数字为人工归纳」。

## 3. 老代码巡检

1. 用 git log 找出最后一次修改在 12 个月以前的文件和目录。
2. 对每个模块查引用（import、调用、路由、配置、定时任务），判断：在用、疑似没用、确定没用。
3. 疑似或确定没用的，写成“删除”或“合并”的独立小任务建议，附判断依据。

## 4. 规格对账

1. 列出窗口内变成 done 的任务，读每个任务描述里的验收标准。
2. 对照当前代码和线上行为，找出不一致：标准写了但没做、做了但标准没写、做法和描述不符。
3. 每处不一致写明任务编号、文件路径，以及建议改代码还是改任务描述。

每条建议写成能独立完成、能单独评审的小任务。最后按 Auditor 角色指令提及 Planner 一次，并把本任务设为 done。
