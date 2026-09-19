# 配置文件

三类配置都在目标仓库的 `ops/agents/` 下，受 CODEOWNERS 保护，修改走 PR。

## aiwf.conf

每行 `KEY=VALUE`，`#` 开头是注释，不支持行尾注释和变量展开。环境变量优先于文件（例如 `AIWF_REPO=acme/shop aiwf github`）。aiwf 和 agent 都会读它（gate.yml、loop-guard.sh 在运行时读取）。

| 键 | 默认 | 说明 |
|---|---|---|
| `AIWF_REPO` | 从 git remote 识别 | GitHub 仓库 owner/name |
| `AIWF_DEFAULT_BRANCH` | 仓库默认分支 | deploy.yml 监听的分支 |
| `AIWF_OWNER` | 当前 gh 用户 | 规则文件的负责人，写进 CODEOWNERS |
| `AIWF_IMPL_BOT` / `AIWF_REVIEW_BOT` / `AIWF_PLANNER_BOT` | 空 | 机器账号，`aiwf github --apply` 邀请为协作者 |
| `AIWF_MULTICA_WORKSPACE` | 空 | Multica 工作区 slug |
| `AIWF_MULTICA_PROJECT` | 仓库名 | Multica 项目标题 |
| `AIWF_HUMAN` | 空（运行 aiwf 的人） | 负责批准、接收升级的成员名；每日摘要的订阅人 |
| `AIWF_AGENT_ACCESS` | private | agent 调用权限：private 或 workspace |
| `AIWF_ISSUE_PREFIX` | 工作区前缀或 MUL | 任务编号前缀，用在 AGENTS.md 和 PR 模板的例子里 |
| `AIWF_CHECK_NAME` | check | 必需检查的名字，要和 gate.yml 的 job 名一致 |
| `AIWF_PR_MAX_LINES` | 400 | 单个 PR 改动行数上限 |
| `AIWF_MAX_REVIEW_REJECTIONS` | 2 | 同一个 PR 打回上限 |
| `AIWF_MAX_ACCEPTANCE_FAILURES` | 2 | 同一个任务验收不通过上限 |
| `AIWF_DEPLOY_ENVIRONMENT` | production（Free 私有仓库为空） | 部署用的 GitHub environment |
| `AIWF_TIMEZONE` | Asia/Shanghai | autopilot 定时触发的时区 |

## registry.yaml

计费注册表和团队清单。`accounts` 段只给 Planner 读，写法自由；`agents` 段 aiwf 按行解析，**每个 agent 必须写成一行 flow 映射**。

```yaml
agents:
  impl-claude: { role: implementer, account: claude-max, runtime: claude@machine-a, model: default, max_tasks: 2 }
```

| 字段 | 必填 | 说明 |
|---|---|---|
| 名字（冒号前） | 是 | Multica 里的 agent 名，工作区内唯一 |
| `role` | 是 | planner（正好 1 个）、implementer（至少 1 个）、reviewer（至少 1 个）、auditor（最多 1 个） |
| `account` | 是 | accounts 里的账号，同一账号下的 agent 共用额度 |
| `runtime` | 是 | `provider@设备`（`aiwf runtimes` 查）或 runtime ID |
| `model` | 否 | default 用 runtime 默认模型 |
| `max_tasks` | 否 | 并发上限 1–50 |
| `mcp` | 否 | MCP 配置文件，相对 `ops/agents/` |
| `env_file` | 否 | 环境变量 JSON 文件，相对仓库根目录；放 `ops/agents/local/`，不要提交 |

## autopilots/*.md

每个文件是一个 autopilot：front matter 是触发配置，正文是每次运行时 agent 读到的 runbook。

```markdown
---
title: 每日摘要
role: planner
mode: create_issue
cron: 0 9 * * *
issue_title: 每日摘要 {{date}}
subscriber: human
---
写今天的每日摘要……
```

| 字段 | 说明 |
|---|---|
| `title` | autopilot 标题，aiwf 按它查找已有的 autopilot |
| `role` | 由哪个角色执行（registry 里唯一的 planner 或 auditor） |
| `mode` | `run_only`：直接运行，结果在运行历史里，runtime 离线时跳过；`create_issue`：先建任务再运行，适合要留档的报告 |
| `cron` | 定时触发（五段 cron），时区取 `AIWF_TIMEZONE` |
| `trigger` | 默认 schedule；写 `webhook` 表示 webhook 触发，地址写进 GitHub secret `MULTICA_DEPLOY_HOOK` |
| `issue_title` | create_issue 模式的任务标题，只支持 `{{date}}` |
| `subscriber` | create_issue 模式下通知谁；`human` 表示 `AIWF_HUMAN`（为空时是运行 aiwf 的人） |

加一个新的 autopilot：新建一个 md 文件，合并后 `aiwf multica --apply`。删除一个：删文件后到 Multica 界面里删掉对应的 autopilot（aiwf 不会删除任何东西）。

## 角色指令

`planner.md`、`implementer.md`、`reviewer.md`、`auditor.md` 的全文就是 Multica agent 的指令。改完合并后 `aiwf multica --apply --only agents` 同步；`aiwf doctor` 会报告指令漂移。
