---
title: 每日摘要
role: planner
mode: create_issue
cron_key: AUTOTEAM_CRON_DAILY_DIGEST
issue_title: 每日摘要 {{date}}
subscriber: human
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

写今天的每日摘要，写在本任务的评论里，然后把本任务设为 done。摘要开头先写 `bash ./autoteam status --check` 的结果（运行中或已暂停）。暂停时遵守上面的停机规则，不继续生成摘要。

1. 进展：过去 24 小时完成的任务，正在进行的任务和各自状态。
2. 待人处理：backlog 里等批准的任务数；blocked 的任务、卡点和你的建议。
3. 批准核对：用 `multica issue timeline <任务> --activity-only --output json` 核对过去 24 小时的 backlog→todo 记录，再读相应评论。分成下面两节，空节写「无」：
   - **自主放行**：Planner 操作且有他写的 `【自主放行】` 评论的任务。逐条列任务链接、优先级、评论中的一句话理由、当前状态，注明人可以直接取消。不要把 `【人工授权放行】` 当成自主放行。
   - **违规**：agent 操作却既没有 `【自主放行】` 评论、也没有 `【人工授权放行】` 等可核实的人授权记录；或自主放行的任务触及受保护路径。核对任务描述和 PR 改动文件（如已有 PR）：`.github/`、`.autoteam/`、`skills/autoteam/instructions/`、`skills/autoteam/templates/`、`Makefile`、`.jscpd.json`、包版本号和 lock 文件都受保护。不确定是否触及就标为待核实，不能默认为合规。逐条给证据和建议，并用 `[@名字](mention://member/<user_id>)` 提及人。
   人直接操作或有明确人授权记录的放行不算违规，必要时简述核对数量。
4. 额度和花费：registry.yaml 里每个账号下的 agent，用 multica runtime usage <runtime-id> --days 1 --output json 汇总 token 用量；按量计费的账号对照当日预算。
5. 今天需要人决定的事，每条一句话。
