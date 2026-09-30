---
title: 第 4–6 步：Multica
---

# 第 4–6 步：Multica

```bash
autoteam multica                   # 预览
autoteam multica --apply           # 执行；加 --paused 让新建的 autopilot 先暂停
autoteam multica --apply --only agents   # 只同步 agent（改了角色指令之后）
autoteam multica --apply --only project  # 补建缺失的运营笔记
```

autoteam 用的 multica profile：先看 `--profile` 或环境变量 `AUTOTEAM_MULTICA_PROFILE`；默认 profile 没配置服务器时，自动用 `~/.multica/profiles` 下唯一的那个（比如桌面端的 `desktop-api.multica.ai`）。工作区取 autoteam.conf 的 `AUTOTEAM_MULTICA_WORKSPACE`。

## 状态

流程使用 Multica 内置状态（`backlog`、`todo`、`in_progress`、`in_review`、`blocked`、`done`、`cancelled`）。升级旧工作区时，`autoteam multica --apply` 会先将现有 `shipping` 任务迁回 `in_review`（不启动 agent），全部成功后归档旧状态。预览只列出待迁移任务和归档动作。`--only statuses` 可单独执行这一步；新工作区没有 `shipping` 时无需处理。

归档状态调用 `/api/issue-statuses` 接口，需要工作区 owner 或 admin；agent、项目、autopilot 和 webhook 同步不要求此角色，可用 `--only agents,project,autopilots` 跳过迁移。token 从 multica profile 读取，通过 stdin 交给 curl，不出现在进程参数里。

## agent 和计费注册表

autoteam 按 `.autoteam/registry.yaml` 的每一行建 agent（已存在就更新）：

- 指令取角色指令的全文：默认是 autoteam 包内的版本（升级 autoteam 就升级了它），要按项目改就 `autoteam eject <角色名>` 到 `.autoteam/instructions/roles/`，修改走 PR。都要合并后重新运行 `autoteam multica --apply` 才生效；`autoteam doctor` 能发现 Multica 里的指令和生效文本不一致（指令漂移）。同步时会在角色指令和 autopilot 正文最前面自动加上包内 `instructions/_preamble.md` 的「开工先检查暂停」前言，eject 出的文件里没有这段。
- `runtime` 写 `provider@设备`（`autoteam runtimes` 列出可选值）或 runtime ID；runtime 不在线时 autoteam 会提醒，任务会排队等它上线。
- `model` 为 default 时用 runtime 的默认模型；Planner 建议写最强的模型。
- `mcp`：Planner 做 Web 项目线上验收时挂浏览器自动化，写 `mcp: planner-mcp.json`。
- `env_file`：按量计费的 agent 需要的 API key 等环境变量（JSON 文件，放 `.autoteam/local/`，不要提交）。
- 调用权限：autoteam.conf 的 `AUTOTEAM_AGENT_ACCESS=private`（默认，只有创建者能触发）或 `workspace`（工作区成员都能触发）。多人一起用时设为 workspace。

agent 名在工作区内唯一。一个工作区里放多个项目时，给名字加前缀（比如 `shop-planner`）。

## 项目

建一个标题为 `AUTOTEAM_MULTICA_PROJECT`（默认仓库名）的项目，挂上 GitHub 仓库资源。项目没有「运营笔记」时，`--apply` 新建一条：先建未指派的 backlog 任务，再用 `assign --no-start` 指派 Planner、`status --no-start` 设为 `in_progress`，不会触发 Planner 运行。再次同步跳过已有笔记，不改其内容或 metadata。`autoteam doctor` 检查本项目恰好有一条运营笔记；缺失时运行 `autoteam multica --apply --only project`。agent 运行时 Multica 会给每个任务一个独立的 worktree，同一仓库上的任务可以并发。

## 触发配置

常规实时触发不需要配置，靠内置状态、指派、人对已指派任务的普通评论和 @提及（见[唤醒规则](../concepts/lifecycle.md#唤醒规则multica-051-起)）：

| 设计中的触发 | 实现 |
|---|---|
| 人下发需求 | 在 Chat 里和 Planner 对话，或建任务指派给 Planner |
| 人批准 | 把子任务从 `backlog` 改成 `todo`，指派人仍是 Planner；界面批准后用 `multica issue runs <任务>` 确认 Planner 的运行已生成，见[界面批准后的唤醒核对](../concepts/lifecycle.md#界面批准后的唤醒核对) |
| Planner 派发 | `multica issue status X todo --no-start` 再 `multica issue assign X --to <Implementer>` |
| 人补充任务意见 | 对已指派任务发普通评论，平台默认叫醒指派 agent；以 `/note` 开头可抑制默认唤醒 |
| 唤醒 Reviewer | Implementer 在评论里 `[@rev-xxx](mention://agent/<UUID>)` |
| 退回返工 | Reviewer 在评论里提及 Implementer，Implementer 把状态改回 `in_progress` |
| 批次推进 | 子任务带 `--parent` 和 `--stage`，最早一批完成时叫醒父任务的指派人 Planner |
| 部署通知 | “部署结果” autopilot 的 webhook，请求里的 JSON 交给 Planner |
| 升级 | Reviewer @Planner；Planner 设为 `blocked` 并提及人 |

Multica 0.5.1 起还可在单个任务上用 `multica issue wakeup create <任务> --agent-id <agent_id> --kind event --event comment.created --filter-actor-type member --filter-actor-id <user_id> --instruction-file <文件>` 监听指定人的评论。安排定时复查时，保留 `--agent-id` 和 `--instruction-file`，去掉作者过滤参数，并把事件参数换成 `--kind at --after 10m`、`--kind every --every 1h` 或 `--kind cron --cron '0 * * * *' --timezone Asia/Shanghai`。以成员凭据创建规则时要指定 `--agent-id`，否则没有默认 agent。先用 `multica issue wakeup events` 查看可监听的事件，再用 `wakeup list/get/disable` 管理规则。事件规则未加作者过滤时会匹配 agent 评论，多个连续规则可能互相唤醒。autoteam 不在 `multica --apply` 中自动创建这些任务级规则；角色交接仍用明确的 @提及。

定时触发和部署通知由 autoteam 包内的 autopilot 指令定义（想改某一个，`autoteam eject <名字>` 落到 `.autoteam/instructions/autopilots/`），autoteam 按 front matter 建 autopilot 和触发器，正文是每次运行的 runbook：

| 名称 | 指派 | 触发 | 模式 |
|---|---|---|---|
| 推进巡检 | Planner | `0 */2 * * *` | run_only |
| 每日摘要 | Planner | `0 9 * * *` | create_issue，订阅人是 AUTOTEAM_HUMAN |
| 周度健康报告 | Auditor | `0 9 * * 1` | create_issue，整合审计、agent 成绩单、老代码巡检、规格对账四节 |
| 月度方向报告 | Auditor | `0 11 1 * *` | create_issue，订阅人是 AUTOTEAM_HUMAN，前沿扫描、路线图对账两节 |
| 规则复盘 | Planner | `0 12 * * 1` | run_only |
| 部署结果 | Planner | webhook | run_only |

- run_only 在 runtime 离线时会跳过本次运行，所以巡检要补查超过一小时还没验收的“待上线”任务。
- Auditor 的报告要留档，所以用 create_issue。每日摘要也用 create_issue（研究文档里是 run_only），因为 run_only 的结果只在运行历史里，人收不到通知。
- 时区取 autoteam.conf 的 `AUTOTEAM_TIMEZONE`（默认 Asia/Shanghai）。
- webhook 触发器新建时，autoteam 把地址直接写进 GitHub secret `MULTICA_DEPLOY_HOOK`，不在终端显示；已经有触发器时不会重复创建。地址泄露了用 `--rotate-webhook` 重新生成。
- autopilot 按「标题 + 项目」认领：只创建、更新绑在 `AUTOTEAM_MULTICA_PROJECT` 项目上的，工作区里别的项目的同名 autopilot（Multica 允许重名）预览和 `--apply` 都不动，预览会提示一句；`autoteam doctor` 也只检查本项目的。所以一个工作区可以放多个 autoteam 项目，各自一套 autopilot。项目改名或重建后，旧项目上的 autopilot 不会被改到新项目，`--apply` 会给新项目另建一套，旧的请在 Multica 界面里暂停或删除。

## GitHub 集成（可选）

Settings → GitHub 连接仓库后，Multica 会按任务编号把 PR 关联到任务（分支名或 PR 标题里写 `XXX-123`），在卡片上显示 CI 状态和能否合并。它只读仓库，从不推代码、写评论或状态检查，所以闸门仍然在 GitHub 上。PR 正文写 `Closes XXX-123` 这类关闭关键字，合并时会直接把任务设为完成，所以角色指令要求不写。

## 同步失败与超时

同步读取失败最多尝试 3 次；写操作不自动重试。失败时会以非零退出码结束，输出“同步不完整”，按所选部分列出已完成、失败或部分完成、未执行的清单；已写入的改动不回滚，修复后可重新运行。重复挂载同一个仓库视为已是最新。`--only statuses` 不读取 runtime。

CLI 和状态 API 的 curl 请求都受 `MULTICA_HTTP_TIMEOUT` 控制，默认 30 秒，支持正秒数或 Go duration（如 `45`、`45s`、`2m`、`1m30s`）；无效或非正值会在同步前报错。格式依据 [Multica CLI 官方说明](https://github.com/multica-ai/multica/blob/main/CLI_AND_DAEMON.md)。

## 检查

```bash
autoteam doctor
```
