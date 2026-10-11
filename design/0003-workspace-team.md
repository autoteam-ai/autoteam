# 0003 工作区级团队：一处维护，服务所有仓库

- 状态：实施中（2026-10-11，HDGCS-237）
- 前置：[0002 共享 agent 团队](0002-shared-team.md)（成员仓库不同步 agent、「本项目」的定义、stop 只作用于本项目、按仓库核对 App 安装，这些结论沿用）
- 影响：成员仓库不再安装 `.autoteam/`；autopilot 从按项目改为按团队；**breaking**（0002 的成员仓库要迁移）

## 1. 问题

0002 让一套 agent 服务多个仓库，但只共享了 Multica 上的 agent，其余仍按仓库复制。devcontainer 试点（HDGCS-220，`songhuangcn/devcontainer` PR #6）实测：

| 项 | 数字 |
|---|---|
| 接入 PR 新增 | 25 个文件、1596 行 |
| 其中项目自己的 | 2 个文件、137 行（Makefile 的三个目标、`scripts/wait-build.sh`） |
| 其中 autoteam 的副本 | 23 个文件、1459 行（91%）：9 个脚本 924 行、3 个工作流、34 个键的 conf（10 个团队级键抄自团队仓库）、整份 registry、`.lock.json`、写死 `AUTOTEAM_REF` 的 `./autoteam` 入口 |
| Multica | 每个项目 5 个 autopilot、1 条运营笔记、1 个 webhook；两个项目已有 11 个启用的 autopilot，每天 2 份每日摘要 |

由此带来三个随仓库数线性增长的成本：

1. **升级 = N 个 PR**，哪个仓库没跟上，它的 CLI 就和 agent 指令（全工作区一份）版本不一致。
2. **团队规则会分叉**：HDGCS-232（解除 blocked 后要显式叫醒 Implementer）是团队级规则，却被 eject 进了 devcontainer（PR #8），合并后只有 devcontainer 上的 Planner 会这么做。devcontainer 的巡检也停在模板默认的每 2 小时，团队定的是每 5 小时。
3. **团队不知道自己管着哪些仓库**，「给所有仓库升级」「一份摘要覆盖所有项目」无从做起。

根因：指令和 runbook 里 17 个文件写死了在项目仓库里跑 `bash ./autoteam` 和 `.autoteam/scripts/*.sh`，agent 在哪个仓库干活，哪个仓库就得带着整套工具。

## 2. 人的决定（2026-10-11）

1. 团队仓库就是 `autoteam-ai/autoteam`，团队配置就是它的 `.autoteam/`（默认配置）。不另建团队仓库。
2. autopilot 合并成团队级。
3. agent 自己管理规则（指令、配置、GitHub 规则集），人只守待办需求闸口（backlog → todo）。
4. devcontainer PR #8 不批准；那条规则改在包内 `dispatch` runbook。
5. 第一期只处理 autoteam-ai、songhuangcn 两个账号下的仓库。
6. 由 Claude Code 直接实现，迁移期间暂停团队。

## 3. 每类东西放哪

| 东西 | 运行时谁读 | 去处 |
|---|---|---|
| `make check/dev/deploy` | CI、Implementer | 成员仓库（项目代码） |
| 合并闸门、上线通知 | GitHub Actions | 成员仓库只放约 20 行的 `.github/workflows/autoteam.yml`，调用团队仓库的可复用工作流 `member.yml@main` |
| 规则集、auto-merge、secret | GitHub | 远端设置，由团队仓库里的命令写 |
| 运行时脚本 | agent、工作流 | CLI 子命令（`autoteam token`、`open-pr` 等），包内的脚本 |
| CLI 版本 | agent | runtime 上的启动器跑团队仓库 main 最新提交的快照 |
| 团队配置、registry、团队 playbook、eject 的指令 | CLI、agent | 团队仓库 `.autoteam/` |
| 成员项目配置和经验 | CLI、agent | 团队仓库 `.autoteam/projects/<owner>/<repo>/{project.conf,playbook.md}` |
| AGENTS.md 的 autoteam 受管块、`.lock.json`、PR 模板、`.jscpd.json` | — | 成员仓库不再下发 |

## 4. 决策

**D1 团队仓库 = autoteam 仓库。** 它的 `.autoteam/autoteam.conf` 是全部项目的默认配置；成员项目在 `projects/` 下登记，`project.conf` 只写不同的键。描述项目自己的键（仓库、默认分支、Multica 项目名、检查名、PR 排除路径、部署 environment、autopilot）不继承团队的值。代价：autoteam 是公开仓库，成员项目清单和经验公开；当前成员都是公开仓库，可以接受。团队仓库自己也是一个项目，团队级 autopilot 挂在它上面。

**D2 版本只有一处：团队仓库 main。** 启动器（`bin/autoteam-launcher`，装在 runtime 机器上）在成员仓库里取团队仓库默认分支最新提交的快照运行，CLI 和配置同一提交；在团队仓库自己的 checkout 里跑 checkout 里的 CLI，和团队仓库的项目一直以来的做法一样。这样不需要单独的版本号或发版节奏，代价是 main 上的回归立即影响所有仓库，由 autoteam 自己的 gate 和部署验收挡住。独立项目（如 autoteam-example）保留固定版本的 `./autoteam`，启动器优先用它。

**D3 CLI 认识成员项目。** 当前仓库有 `.autoteam/autoteam.conf` 是 local 模式（行为不变）；团队仓库登记过的是 member 模式，配置、registry、eject 的指令都取团队仓库的。全局选项 `-P <owner/repo>` 不需要 clone 就能操作某个项目。运行时脚本读 `AUTOTEAM_CONF_FILE`（合并后的配置）。

**D4 工作流放在公开的 autoteam 仓库。** 可复用工作流从私有仓库只能被同一 owner 调用，个人账号也没有组织级 required workflows；放在公开的团队仓库里，所有 owner 都能用。调用文件写 `@main`，和 D2 一致。CI 用 `-P` 从团队仓库读本项目的行数上限。

**D5 autopilot 按团队。** 巡检用 `autoteam next --check --all` 跨项目出一份清单（跳过暂停的项目）；每日摘要、健康报告、规则复盘按项目分节；「部署结果」一个 webhook，所有仓库共用（payload 带 repo）。运营笔记和暂停标记仍按项目，stop / resume 用 `-P` 按项目执行。

**D6 规则由 agent 管。** 改团队规则（指令、runbook、配置、项目登记）的任务照常由人放行，PR 由 Reviewer 评审合并，不再要求人在 GitHub 上批准（`AUTOTEAM_CODEOWNERS_GATE=off` 已是现状）。成员仓库的 GitHub 设置由 Planner 用自己的 App 身份 `autoteam github --apply`，planner App 需要 Administration、Secrets 写权限。接入新仓库按 `onboard` runbook。

## 5. 前后对比

| 场景 | 0002 | 0003 |
|---|---|---|
| 接入新仓库 | 约 1600 行的 PR；按项目建 5 个 autopilot、1 个 webhook | 团队仓库登记两个小文件；成员仓库加 Makefile 目标和调用文件 |
| 升级 autoteam | 每个仓库一个 upgrade PR | 团队仓库 main 合并即生效，成员仓库零改动 |
| 改一条团队规则 | eject 到哪个仓库就只对哪个仓库生效 | 团队仓库一个 PR，所有项目生效 |

## 6. 实施

代码分三个 PR（#145 成员配置和脚本子命令；#146 登记命令、启动器、成员仓库的 init/doctor 和可复用工作流；第三个是团队级 Multica 同步和跨项目巡检），规则和文档一个 PR。之后：

1. devcontainer 镜像装启动器；devcontainer 仓库删掉 0002 装进去的文件，换成调用文件；关闭 PR #8。
2. 团队仓库 `autoteam multica --apply` 建成员项目、写 secret；归档 devcontainer 项目上按项目建的 5 个 autopilot。
3. planner App 加 Administration、Secrets 写权限；`autoteam -P songhuangcn/devcontainer github --apply`。
4. 登记 admin-template，接入工作（`make check` 定义、「上线」定义）作为需求交给团队，等人放行。
5. 恢复团队，端到端走一个小需求。

## 7. 风险

- **爆炸半径**：团队配置或 main 上的 CLI 出错，所有项目一起受影响。缓解：autoteam 的 gate、`make deploy` 在干净仓库安装验证；独立的 example 工作区仍可先试。
- **运行依赖 GitHub**：启动器每 5 分钟查一次团队仓库最新提交，查不到用上次的快照。
- **一个 Planner 管 N 个项目**：派发和额度在团队层面竞争；registry 的 `max_tasks` 和额度路由本来就是团队级的，先观察。
- **planner App 权限变大**：能改所有已装仓库的规则集和 secret，等于 agent 能改自己的闸门。这是人的决定（D6），已登记进不变量的已知偏离。
