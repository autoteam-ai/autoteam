---
title: 配置文件
---

# 配置文件

三类配置都在目标仓库的 `ops/agents/` 下，受 CODEOWNERS 保护，修改走 PR。

## autoteam.conf

每行 `KEY=VALUE`，`#` 开头是注释，不支持行尾注释和变量展开。环境变量优先于文件（例如 `AUTOTEAM_REPO=acme/shop autoteam github`）。autoteam 和 agent 都会读它（gate.yml、loop-guard.sh 在运行时读取）。

| 键 | 默认 | 说明 |
|---|---|---|
| `AUTOTEAM_REPO` | 从 git remote 识别 | GitHub 仓库 owner/name |
| `AUTOTEAM_DEFAULT_BRANCH` | 仓库默认分支 | deploy.yml 监听的分支 |
| `AUTOTEAM_OWNER` | 当前 gh 用户 | 规则文件的负责人，写进 CODEOWNERS |
| `AUTOTEAM_IMPLEMENTER_APP_ID` / `AUTOTEAM_REVIEWER_APP_ID` / `AUTOTEAM_PLANNER_APP_ID` | 空 | 三个角色各自的 GitHub App ID。impl 和 review 必须不同，否则作者要批准自己的 PR，GitHub 会拒。私钥放 `ops/agents/local/<角色>.pem` |
| `AUTOTEAM_MULTICA_WORKSPACE` | 空 | Multica 工作区 slug |
| `AUTOTEAM_MULTICA_PROJECT` | 仓库名 | Multica 项目标题 |
| `AUTOTEAM_HUMAN` | 空（运行 autoteam 的人） | 负责批准、接收升级的成员名；每日摘要的订阅人 |
| `AUTOTEAM_AGENT_ACCESS` | private | agent 调用权限：private 或 workspace |
| `AUTOTEAM_ISSUE_PREFIX` | 工作区前缀或 MUL | 任务编号前缀，用在 AGENTS.md 和 PR 模板的例子里 |
| `AUTOTEAM_CHECK_NAME` | check | 必需检查的名字，要和 gate.yml 的 job 名一致 |
| `AUTOTEAM_PR_MAX_LINES` | 400 | 单个 PR 改动行数上限 |
| `AUTOTEAM_MAX_REVIEW_REJECTIONS` | 2 | 同一个 PR 打回上限 |
| `AUTOTEAM_MAX_ACCEPTANCE_FAILURES` | 2 | 同一个任务验收不通过上限 |
| `AUTOTEAM_MAX_IMPLEMENTER_SWITCHES` | 1 | 同一个任务换几次 Implementer 之后升级 |
| `AUTOTEAM_SHIPPING_RECHECK_HOURS` | 1 | shipping 超过几小时没验收，巡检补查 |
| `AUTOTEAM_METRICS_DAYS` | 30 | health-metrics 默认窗口 |
| `AUTOTEAM_PR_SIZE_EXCLUDE` | lock 文件、Markdown、`.github/**`、`ops/agents/**` | 不计入 PR 行数上限的路径，逗号分隔。上限管的是**代码**改动量，文档和由人批准的规则文件不占 agent 的预算 |
| `AUTOTEAM_DIFF_IGNORE` | 空 | `autoteam diff --check` 跳过的文件，逗号分隔：按本项目需要改过、不打算跟模板一致的 |
| `AUTOTEAM_CRON_*` | 见模板 | 9 个 autopilot 各自的 cron，见下 |
| `AUTOTEAM_DEPLOY_ENVIRONMENT` | production（Free 私有仓库为空） | 部署用的 GitHub environment |
| `AUTOTEAM_TIMEZONE` | Asia/Shanghai | autopilot 定时触发的时区 |

## registry.yaml

计费注册表和团队清单。`accounts` 段只给 Planner 读，写法自由；`agents` 段 autoteam 按行解析，**每个 agent 必须写成一行 flow 映射**。

```yaml
agents:
  impl-claude: { role: implementer, account: claude-max, runtime: claude@machine-a, model: default, max_tasks: 2 }
```

| 字段 | 必填 | 说明 |
|---|---|---|
| 名字（冒号前） | 是 | Multica 里的 agent 名，工作区内唯一 |
| `role` | 是 | planner（正好 1 个）、implementer（至少 1 个）、reviewer（至少 1 个）、auditor（最多 1 个） |
| `account` | 是 | accounts 里的账号，同一账号下的 agent 共用额度 |
| `runtime` | 是 | `provider@设备`（`autoteam runtimes` 查）或 runtime ID |
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
| `title` | autopilot 标题，autoteam 按它查找已有的 autopilot |
| `role` | 由哪个角色执行（registry 里唯一的 planner 或 auditor） |
| `mode` | `run_only`：直接运行，结果在运行历史里，runtime 离线时跳过；`create_issue`：先建任务再运行，适合要留档的报告 |
| `cron` | 定时触发（五段 cron），时区取 `AUTOTEAM_TIMEZONE` |
| `trigger` | 默认 schedule；写 `webhook` 表示 webhook 触发，地址写进 GitHub secret `MULTICA_DEPLOY_HOOK` |
| `issue_title` | create_issue 模式的任务标题，只支持 `{{date}}` |
| `subscriber` | create_issue 模式下通知谁；`human` 表示 `AUTOTEAM_HUMAN`（为空时是运行 autoteam 的人） |

**阈值和 cron 的区别**：正文里的阈值写成“读 autoteam.conf 的 X”，改完 conf 立即生效；front matter 的 `cron` 必须是具体值（Multica 要），所以写成 `{{AUTOTEAM_CRON_*}}` 占位符，改完 conf 要重新渲染：

```bash
autoteam init --force ops/agents/autopilots/patrol.md   # 重新渲染
autoteam multica --apply --only autopilots              # 同步到 Multica
```

| conf 键 | 对应 autopilot | 默认 |
|---|---|---|
| `AUTOTEAM_CRON_PATROL` | 推进巡检 | `0 */2 * * *` |
| `AUTOTEAM_CRON_DAILY_DIGEST` | 每日摘要 | `0 9 * * *` |
| `AUTOTEAM_CRON_SCORECARD` | agent 成绩单 | `0 8 * * 1` |
| `AUTOTEAM_CRON_CONSOLIDATION` | 整合审计 | `0 9 * * 1` |
| `AUTOTEAM_CRON_ROADMAP` | 路线图对账 | `0 10 * * 1` |
| `AUTOTEAM_CRON_FRONTIER` | 前沿扫描 | `0 11 * * 1` |
| `AUTOTEAM_CRON_RULE_REVIEW` | 规则复盘 | `0 12 * * 1` |
| `AUTOTEAM_CRON_SPEC_RECONCILE` | 规格对账 | `0 9 * * 5` |
| `AUTOTEAM_CRON_LEGACY_SWEEP` | 老代码巡检 | `0 3 1 * *` |

加一个新的 autopilot：新建一个 md 文件，合并后 `autoteam multica --apply`。删除一个：删文件后到 Multica 界面里删掉对应的 autopilot（autoteam 不会删除任何东西）。

## 角色指令

`planner.md`、`implementer.md`、`reviewer.md`、`auditor.md` 的全文就是 Multica agent 的指令。改完合并后 `autoteam multica --apply --only agents` 同步；`autoteam doctor` 会报告指令漂移。
