---
title: 共享团队接入新仓库
---

# 共享团队接入新仓库

一套 agent 团队（Planner / Implementer / Reviewer / Auditor）可以服务多个仓库：团队仓库管理 agent，成员仓库只管自己的项目、运营笔记和 autopilot。本文是接入一个新成员仓库的完整步骤。成员仓库可以在个人账号下，也可以在其他组织里。

## 人要做的

1. **让 App 能装到新仓库所在的账号。** 三个 GitHub App（Implementer / Reviewer / Planner）的可见性默认只对创建者自己的账号开放；新仓库在别的账号或组织下时，到每个 App 的设置页把可见性改为可安装到其他账号。autoteam 不改 App 的可见性。
2. **把三个 App 装到新仓库。** 打开各 App 的 Install 页面，Repository access 选 **Only select repositories**，只选新仓库。autoteam 不替人安装 App。
3. **准备私钥。** 跑 agent 的机器上，三个角色的 `.pem` 放进团队仓库 `AUTOTEAM_KEYS_DIR` 指定的目录，成员仓库共用这个机器级目录，不用每个仓库各放一份。
4. **确认新仓库的 admin 权限。** `autoteam github --apply` 要改规则集和仓库设置，需要对新仓库有 admin 权限。

## 在新仓库里做的

1. 先把团队仓库拉到本机，然后在新仓库根目录运行：

   ```bash
   autoteam init --team-home <团队仓库本地目录> --dry-run   # 先看会带过来什么
   autoteam init --team-home <团队仓库本地目录>
   ```

   `init --team-home` 读取团队仓库的 `.autoteam/autoteam.conf` 和 `registry.yaml`：

   - 带过来这些团队级配置：`AUTOTEAM_MULTICA_WORKSPACE`、三个 `AUTOTEAM_*_APP_ID`、`AUTOTEAM_KEYS_DIR`、`AUTOTEAM_HUMAN`、`AUTOTEAM_AGENT_ACCESS`、`AUTOTEAM_ISSUE_PREFIX`、`AUTOTEAM_LANGUAGE`、`AUTOTEAM_TIMEZONE`；
   - 把 `registry.yaml` 原样复制过来；
   - 写入 `AUTOTEAM_TEAM_HOME=<团队仓库的 AUTOTEAM_REPO>`，成员仓库从此不同步 agent；
   - `AUTOTEAM_REPO`、`AUTOTEAM_OWNER`、`AUTOTEAM_MULTICA_PROJECT` 仍按新仓库识别；
   - 命令行参数优先于团队仓库的值，例如 `--timezone Asia/Tokyo`。已有的 `autoteam.conf`、`registry.yaml` 不会被覆盖。

2. **约定 `make check`。** 把新仓库的 Makefile 里 `check`、`dev`、`deploy` 改成真实命令并跑通（见[第 0 步](repo.md)）。Implementer 交付前只跑 `make check`，gate 也只调它。
3. 提交生成的文件，走 PR 由人批准合并。
4. `autoteam github --apply` 配置规则集；然后运行 `autoteam multica --apply`。成员仓库的 `multica --apply` **只建项目、运营笔记和 autopilot**，不创建也不更新 agent；显式写 `--only agents` 会报错。
5. 运行 `autoteam doctor` 验收。

## doctor 怎么核对

- **App 安装**：组织仓库用 `orgs/<owner>/installations` 核对。个人账号下的仓库、或没有组织 admin 权限读不到时，doctor 对每个角色用本机私钥直接问 `repos/<repo>/installation`，显示「已装在 \<repo\>」，并照常检查 Implementer 的 Workflows 权限和 Reviewer 的 Contents 写权限。本机没有该角色私钥时只提示核对不了，到 App 的 Install 页面自己确认。
- **团队级配置**：成员仓库的 doctor 会读团队仓库的 `autoteam.conf`，上面这些团队级键的值与本仓库不一致时 warn；读不到团队仓库就跳过。
- **agent**：只核对存在且 runtime 在线，指令和 runtime / 模型 / 并发的差异由团队仓库负责，见[第 4–6 步 Multica](multica.md)。
