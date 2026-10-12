---
title: 一个团队服务多个仓库
---

# 一个团队服务多个仓库

一套 agent 团队（Planner / Implementer / Reviewer / Auditor）服务多个 GitHub 仓库，团队的配置、规则和版本只维护在**团队仓库**一处。成员仓库里不装 autoteam 的文件，只有项目本来就该有的 `make check / dev / deploy`，加一个约 20 行的 `.github/workflows/autoteam.yml`。升级 autoteam、改规则、调参数都只改团队仓库，所有成员仓库（包括以后接入的）下一次运行就生效。设计见 [design/0003](https://github.com/autoteam-ai/autoteam/blob/main/design/0003-workspace-team.md)。

## 东西放在哪

| 东西 | 位置 |
|---|---|
| 团队配置、registry、团队 playbook、eject 的指令 | 团队仓库 `.autoteam/`（`autoteam.conf` 就是全部项目的默认配置） |
| 成员项目的配置和经验 | 团队仓库 `.autoteam/projects/<owner>/<repo>/project.conf`、`playbook.md` |
| 合并闸门和上线 | 成员仓库 `.github/workflows/autoteam.yml`，调用团队仓库的可复用工作流 `.github/workflows/member.yml@main` |
| 检查、开发、部署命令 | 成员仓库的 Makefile：`check`、`dev`、`deploy` |
| autopilot | 只在团队仓库的项目上建一套：巡检、每日摘要、健康报告、规则复盘覆盖全部项目，「部署结果」的 webhook 所有仓库共用 |
| 运营笔记、暂停标记 | 每个项目一条，`autoteam multica --apply` 在团队仓库里一起建 |

成员项目的配置 = 团队 `autoteam.conf` + 本项目的 `project.conf`。下面这些键描述项目自己，不继承团队仓库的值，没写时用 autoteam 默认值：`AUTOTEAM_REPO`（取登记的目录名）、`AUTOTEAM_DEFAULT_BRANCH`、`AUTOTEAM_MULTICA_PROJECT`（默认仓库名）、`AUTOTEAM_CHECK_NAME`（默认 `autoteam / check`）、`AUTOTEAM_PR_SIZE_EXCLUDE`、`AUTOTEAM_DEPLOY_ENVIRONMENT`（成员仓库固定 `production`）、`AUTOTEAM_AUTOPILOTS`（默认空）。在任意项目里运行 `autoteam conf` 看生效的值。

## agent 怎么拿到 CLI 和配置

跑 agent 的机器上装一次启动器，作为 PATH 里的 `autoteam`：

```bash
curl -fsSL https://raw.githubusercontent.com/autoteam-ai/autoteam/main/skills/autoteam/bin/autoteam-launcher \
  -o ~/.local/bin/autoteam && chmod +x ~/.local/bin/autoteam
```

启动器按顺序选 CLI：

1. 仓库自带的：团队仓库自己的 checkout，或独立项目根目录固定版本的 `./autoteam`；
2. 团队仓库默认分支最新提交的快照（`AUTOTEAM_TEAM_HOME`，默认 `autoteam-ai/autoteam`）：CLI、团队配置和成员项目配置来自同一个提交。最新提交缓存 5 分钟（`AUTOTEAM_TEAM_TTL`），查不到时用上次的快照。

所以版本只在团队仓库一处：团队仓库 main 上合并了什么，agent 下一次运行就用什么。角色指令和 autopilot 仍由团队仓库合并后 `autoteam multica --apply` 同步到 Multica。

agent 在成员仓库里用子命令代替原来 `.autoteam/scripts/` 下的脚本：`autoteam token --run implementer gh ...`、`autoteam open-pr`、`autoteam merge-mode`、`autoteam loop-guard`、`autoteam protected-paths`、`autoteam metrics`。用 `-P <owner/repo>` 可以在不 checkout 某个项目的情况下操作它（如 `autoteam -P songhuangcn/devcontainer status`）。

## 接入一个新仓库

在 Planner 的 Chat 里说「接入 owner/repo」，Planner 按 `onboard` runbook 拆成两个子任务，你只需放行。手工接入的步骤如下。

**一次性前提**

- 三个 GitHub App 装在仓库所在的账号或组织上，选**全部仓库**：以后在这个账号新建的仓库自动覆盖，不用再装。仓库在别的账号或组织下时，先到每个 App 的设置页把可见性改成可以安装到其他账号。
- Multica 的 GitHub App 也要装在这个账号或组织上（全部仓库）。没装时 PR 不会自动关联到任务，Reviewer 没法注册“等检查结束”的条件唤醒，只能靠巡检兜底。
- 要让 Planner 自己配置规则集和 secret，planner App 需要 Administration、Secrets 的写权限，并在每个安装上接受新权限；没有就由有仓库 admin 的人运行下面的 `github --apply`。

**步骤**

1. 在团队仓库登记，提交并合并：

   ```bash
   autoteam project add owner/repo      # 生成 .autoteam/projects/owner/repo/{project.conf,playbook.md}
   ```

2. 在团队仓库 main 上同步 Multica（新建项目、挂仓库、运营笔记，把团队「部署结果」的 webhook 写进新仓库的 secret），并配置新仓库的 GitHub：

   ```bash
   autoteam token --run planner autoteam multica --apply
   autoteam token --run planner autoteam -P owner/repo github --apply   # 规则集的必需检查是 autoteam / check
   ```

3. 在新仓库的 clone 里生成调用文件和 Makefile，把三个目标改成真实命令，提 PR 合并：

   ```bash
   autoteam init          # 只生成 .github/workflows/autoteam.yml 和 Makefile（已有 Makefile 只提示缺哪些目标）
   ```

   调用文件显式传 `MULTICA_DEPLOY_HOOK`，不用 `secrets: inherit`：后者只在同一组织内生效，个人账号下的仓库调用团队仓库的工作流时传不过去。`make deploy` 要等线上换成本次提交再返回；项目已有自己的部署流水线时，`make deploy` 等那条流水线完成即可（devcontainer 就是这样）。

4. 在新仓库的 clone 里 `autoteam doctor` 验收。

## 从 0002 的成员仓库迁移

按 0002 接入的成员仓库（仓库里有 `.autoteam/` 和 `AUTOTEAM_TEAM_HOME`）这样迁：

1. 在团队仓库 `autoteam project add owner/repo`，把成员仓库 `autoteam.conf` 里和团队不同、又确实需要的键搬进 `project.conf`，`playbook.md` 里有内容就搬过去；
2. 在成员仓库删掉 `.autoteam/`、`./autoteam`、`.github/workflows/{gate,deploy,rollback}.yml`、`.github/CODEOWNERS` 的 autoteam 受管块、`AGENTS.md` 的 autoteam 受管块，再 `autoteam init` 生成调用文件；
3. 团队仓库 `autoteam multica --apply` 改写 secret，`autoteam -P owner/repo github --apply` 把必需检查改成 `autoteam / check`；
4. 成员项目上原来按项目建的 autopilot 由人在 Multica 界面归档（autoteam 不删远端资源）。

## doctor 怎么核对成员仓库

- **文件**：有调用团队可复用工作流的 `.github/workflows/autoteam.yml`，Makefile 有三个目标；旧版装进来的文件提示删除。
- **App 安装**：组织仓库用 `orgs/<owner>/installations` 核对。个人账号下的仓库，或没有组织 admin 权限读不到时，doctor 对每个角色用本机私钥直接问 `repos/<repo>/installation`。本机没有该角色私钥时只提示核对不了。
- **agent**：只核对存在且 runtime 在线；指令和 runtime / 模型 / 并发的差异由团队仓库负责。
