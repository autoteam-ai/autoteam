---
title: 配置文件
---

# 配置文件

三类配置都在目标仓库的 `.autoteam/` 下，受 CODEOWNERS 保护，修改走 PR。

## autoteam.conf

每行 `KEY=VALUE`，`#` 开头是注释，不支持行尾注释和变量展开。环境变量优先于文件（例如 `AUTOTEAM_REPO=acme/shop autoteam github`）。autoteam 和 agent 都会读它（gate.yml、loop-guard.sh 在运行时读取）。

| 键 | 默认 | 说明 |
|---|---|---|
| `AUTOTEAM_REPO` | 从 git remote 识别 | GitHub 仓库 owner/name |
| `AUTOTEAM_DEFAULT_BRANCH` | 仓库默认分支 | deploy.yml 监听的分支 |
| `AUTOTEAM_OWNER` | 当前 gh 用户 | 规则文件的负责人，写进 CODEOWNERS |
| `AUTOTEAM_IMPLEMENTER_APP_ID` / `AUTOTEAM_REVIEWER_APP_ID` / `AUTOTEAM_PLANNER_APP_ID` | 空 | 三个角色各自的 GitHub App ID。impl 和 review 必须不同，否则作者要批准自己的 PR，GitHub 会拒 |
| `AUTOTEAM_KEYS_DIR` | `~/.autoteam` | App 私钥的机器级目录，`~` 按运行的那台机器展开。查找顺序：`AUTOTEAM_<角色大写>_APP_KEY` 指的路径 > 仓库的 `.autoteam/local/` > 这里。**跑 agent 的机器要用这个**——agent 每次 checkout 都是新目录，放仓库里的私钥不会跟过去 |
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
| `AUTOTEAM_PR_SIZE_EXCLUDE` | lock 文件、Markdown、`.github/**`、`.autoteam/**` | 不计入 PR 行数上限的路径，逗号分隔。上限管的是**代码**改动量，文档和由人批准的规则文件不占 agent 的预算 |
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
| `mcp` | 否 | MCP 配置文件名，目前只有 `planner-mcp.json`：取 autoteam 包内的，`autoteam eject planner-mcp.json` 后取 `.autoteam/instructions/` 下的 |
| `env_file` | 否 | 环境变量 JSON 文件，相对仓库根目录；放 `.autoteam/local/`，不要提交 |

## autopilot 指令

每个 autopilot 是 autoteam 包内 `instructions/autopilots/` 下的一个文件（要改就 `autoteam eject <名字>`，落到 `.autoteam/instructions/autopilots/`，同名以落盘的为准）：front matter 是触发配置，正文是每次运行时 agent 读到的 runbook。

```markdown
---
title: 每日摘要
role: planner
mode: create_issue
cron_key: AUTOTEAM_CRON_DAILY_DIGEST
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
| `cron_key` | 定时触发：指向 `autoteam.conf` 里的 `AUTOTEAM_CRON_*` 配置项（五段 cron），时区取 `AUTOTEAM_TIMEZONE` |
| `trigger` | 默认 schedule；写 `webhook` 表示 webhook 触发，地址写进 GitHub secret `MULTICA_DEPLOY_HOOK` |
| `issue_title` | create_issue 模式的任务标题，只支持 `{{date}}` |
| `subscriber` | create_issue 模式下通知谁；`human` 表示 `AUTOTEAM_HUMAN`（为空时是运行 autoteam 的人） |

**阈值和 cron 的区别**：正文里的阈值写成“读 autoteam.conf 的 X”，改完 conf 立即生效；front matter 用 `cron_key` 指向 conf 里的键，同步时才把值取出来交给 Multica，所以改完 conf 只要同步，不用重新渲染任何文件：

```bash
autoteam multica --apply --only autopilots   # 同步到 Multica
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

**刚开始跑的项目先降频**。默认值是团队稳定后的节奏，新装的项目按它跑有两个问题：空转消耗 token，以及每周一挤进 4 份报告，人一次看不完就会积压。建议按优先级分级——流转心跳（推进巡检）减半、人了解全局的窗口（每日摘要）和把人工介入变成规则的一条（规则复盘）不降、审计和方向类（成绩单、整合审计、规格对账、路线图、前沿扫描）改成每月并分散到不同日子。本仓库自己的 `.autoteam/autoteam.conf` 末尾就是一份这样的配置，可以照抄。

什么时候改回来：连续 4 周 `health-metrics.sh` 的 `human_7d` 不上升、也没有因为降频漏掉的问题。这件事由 Planner 在「规则复盘」里提任务、人批准，不用你盯着。

加一个新的 autopilot：在 `.autoteam/instructions/autopilots/` 新建一个 md 文件，合并后由 Planner 在验收时同步（`autoteam multica --apply`）。删除一个：删文件后到 Multica 界面里删掉对应的 autopilot（autoteam 不会删除任何东西）。

## 角色指令

planner、implementer、reviewer、auditor 四个角色指令的全文就是 Multica agent 的指令。默认不落盘，取 autoteam 包内的版本；要按本项目改，`autoteam eject <角色名>` 复制到 `.autoteam/instructions/roles/` 后再改，此后以这份为准，升级不会覆盖。同步后才生效，Planner 验收时自己跑 `autoteam multica --apply`；`autoteam doctor` 会拿 Multica 里的指令和生效文本比对，报告指令漂移。
