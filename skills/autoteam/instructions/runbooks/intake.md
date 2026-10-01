---
description: 收到需求、人在原任务上回复，或 Auditor 报告 / 范围外发现要拆任务时：拆父任务和子任务
---
需求可能来自 Chat，也可能是人建好任务指派给你。

| 要做的事 | 命令 |
|---|---|
| 本项目的 ID | `multica project list --output json`，按 autoteam.conf 的 `AUTOTEAM_MULTICA_PROJECT` 找 title |
| 列任务 | `multica issue list --project <项目 ID> --output json` |
| 看任务、评论、子任务 | `multica issue get <任务> --output json`、`multica issue comment list <任务> --output json`、`multica issue children <父任务> --output json` |
| 查重 | `multica issue search "<关键词>" --output json`（没有 `--project` 参数） |

**先判断能否在原任务上继续**：人对已有任务发表评论、补充说明、回答问题或改变状态后，先读原任务的描述、验收标准和评论。描述和验收标准仍然成立，就在原任务上继续推进（重新派发、改为 `in_progress`、继续验收等），不新建子任务；仍遵守派发的批准要求和升级次数上限。只有目标或范围确实变化、无法在原任务上继续时，才新建子任务，并在描述里明确写出「为什么不能在原任务上继续」。这不改变首次拆分大需求为多个可独立验证子任务的规则。

1. 读 `AGENTS.md` 和相关代码；需求不清楚，先在评论里问人，然后停下。
2. 父任务写清目标和验收标准，每条都要能在线上验证，并写明怎么验证（访问哪个页面、调哪个接口、下载哪个发布包后跑什么命令）。父任务指派给你自己：
   - 人建的任务：`multica issue status <父任务> in_progress --no-start`；
   - 在 Chat 里收到的需求：`multica issue create --assignee <你> --status backlog --project <项目 ID> ...` 建父任务先停车，拆完后再 `multica issue status <父任务> in_progress --no-start`。
3. 拆成子任务，每个都能单独验证，改动不超过 autoteam.conf 的 `AUTOTEAM_PR_MAX_LINES` 行：

   ```bash
   multica issue create --parent <父任务> --stage <批次> --project <项目 ID> \
     --assignee <你> --status backlog --priority <优先级> --title "..." --description-file <文件>
   ```

   - `--priority` 必须设（`urgent` / `high` / `medium` / `low`），放行分级按它决定放行和派发的先后；
   - 描述包含四节：为什么做、要做什么、不做什么、验收标准（能在线上验证）；
   - **改 `.autoteam/` 或当前生效的指令源（包内 `skills/autoteam/instructions/**`，已 eject 时为 `.autoteam/instructions/**`）的任务，验收标准里必须有一条「已 `autoteam multica --apply` 同步、`autoteam doctor` 无指令漂移」**；
   - 建之前用 `multica issue search` 查重，还要检查原任务及已有子任务是否可以直接推进；能继续原任务就不重复建；
   - 批次按依赖排，先做的是第 1 批；互不依赖的放同一批。 跨需求依赖必须写入 metadata `autoteam.depends_on`，不能只写在描述里：`multica issue metadata set <任务 ID> --key autoteam.depends_on --type string --value "HDGCS-125,HDGCS-126"`。编号逗号分隔，全部 `done` 才可派发；编号不存在、读取失败或解析失败时不派发，先修正前提。 派发前运行 `<身份> bash ./autoteam next --output json`，仅派发其中 `dispatchable` 的任务；放行不代表前提已经满足。
4. 读 `bash ./autoteam runbook release`，逐个判断子任务：符合条件的由你自主放行；其余留在 `backlog`，在父任务评论里列出这些子任务和批次，用成员链接提及人，请他批准。全部自主放行时不用提及人。

## 处理 Auditor 的报告

Auditor 在报告任务里提及你时，把值得做的建议拆成独立任务放进 `backlog`（指派给你自己，描述里引用报告任务），先查重，再按 `release` 处理：符合条件的自主放行（优先级最高 `medium`），其余请人批准；不值得做的在报告任务里用 `/note` 说明理由。
