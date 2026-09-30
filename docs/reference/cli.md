---
title: autoteam 命令
---

# autoteam 命令

```
autoteam [-C <目录>] <命令> [选项]
```

`-C` 指定在哪个仓库里执行（默认当前目录）。每个命令都有 `-h`。依赖 bash 3.2+、git、jq；`github` 需要 gh，`multica` 需要 multica CLI 和 curl。

## autoteam init

生成工作流文件。

| 选项 | 说明 |
|---|---|
| `--repo <owner/name>` | GitHub 仓库，默认从 git remote 识别 |
| `--owner <用户名>` | 规则文件的人类负责人，默认当前 gh 登录用户 |
| `--issue-prefix <前缀>` | 任务编号前缀，默认从 `--workspace` 读取，否则 MUL |
| `--workspace <slug>` | Multica 工作区 |
| `--human <成员名>` | 负责批准和接收升级的 Multica 成员 |
| `--timezone <时区>` | autopilot 时区，默认 Asia/Shanghai |
| `--force` | 覆盖与模板不同的文件、替换受管块，不管改没改过；`autoteam.conf`、`registry.yaml`（用户数据）不覆盖。升级请用 `autoteam upgrade`，它不会动你改过的文件 |
| `[文件...]` | 只处理这些文件，例如 `autoteam init --force .autoteam/playbook.md` |
| `--dry-run` | 只列出会做什么 |

写文件的规则：

| 文件 | 已存在时 |
|---|---|
| AGENTS.md、.github/CODEOWNERS、.gitignore | 追加受管块，只追加一次；块内容和模板不同时跳过（`--force` 替换） |
| Makefile | 不动，只检查有没有 check / dev / deploy 目标 |
| autoteam.conf、registry.yaml | 保留（用户数据） |
| 其他 | 相同就跳过，不同就提示用 `autoteam diff` 看差异（`--force` 覆盖） |

根目录 `./autoteam` 会随 `init` 安装，ref 来自当前 autoteam 包的构建提交；`upgrade` 用新包的提交更新它。部署打包时会检查该提交能从 codeload 下载，且下载的 `bin/`、`lib/` 与包内一致。本仓库自举使用的 `autoteam` 软链会保留，`diff --check` 不把它报成漂移。

识别顺序：命令行参数 > 已有的 autoteam.conf > 自动识别 > 默认值。识别到 GitHub Free 的私有仓库时，`AUTOTEAM_DEPLOY_ENVIRONMENT` 留空，deploy.yml 不声明 environment。

## autoteam github

配置仓库设置、规则集、environment、机器账号。默认只预览。

| 选项 | 说明 |
|---|---|
| `--apply` | 执行 |
| `--trial` | 单账号试用模式：规则集不要求审批 |
| `--bots impl=<用户>,review=<用户>,planner=<用户>` | 邀请机器账号（也可以写在 autoteam.conf） |
| `--repo <owner/name>` | 覆盖 autoteam.conf 里的仓库 |

保护等级的判断和每条规则见[第 1–3 步 GitHub](../setup/github.md)。重复运行是幂等的。

## autoteam multica

迁移旧 `shipping` 任务并归档状态，同步 agent、项目、运营笔记、autopilot 和部署 webhook。默认只预览。项目没有「运营笔记」时，`--apply` 会创建并指派 Planner、设为 `in_progress`，全程使用不启动运行的命令；已有则跳过。

| 选项 | 说明 |
|---|---|
| `--apply` | 执行 |
| `--profile <名字>` | multica profile；也可以用环境变量 `AUTOTEAM_MULTICA_PROFILE` |
| `--workspace <slug 或 ID>` | 覆盖 autoteam.conf 的 `AUTOTEAM_MULTICA_WORKSPACE` |
| `--only <部分>` | 只处理其中几部分：`statuses`（旧状态迁移）、`agents,project,autopilots` |
| `--paused` | 新建的 autopilot 立即暂停 |
| `--rotate-webhook` | 重新生成部署 webhook 地址并写入 GitHub secret |

环境变量：`AUTOTEAM_MULTICA_BIN`（multica 可执行文件路径）、`MULTICA_TOKEN` / `MULTICA_SERVER_URL`（覆盖 profile 里的 API 凭据，只用于建状态）。

## autoteam stop / resume / status

紧急开关只影响 `AUTOTEAM_MULTICA_PROJECT` 指定的项目，暂停标记保存在该项目「运营笔记」任务的 `autoteam.paused` metadata 中，记录 UTC 时间、操作人、停止前 active 的 autopilot ID。`autoteam multica --apply` 在接入时创建「运营笔记」；已有任务不改内容或 metadata。执行 `stop --apply` 前须有该任务；缺失时运行 `autoteam multica --apply --only project`。

| 命令 | 效果 |
|---|---|
| `autoteam stop` | 预览将暂停的 autopilot、将取消的 running/queued 运行 |
| `autoteam stop --apply [--keep-run <运行 ID>]` | 写标记、暂停本项目 active 的 autopilot，并取消 registry agent 的运行；`--keep-run` 保留当前 Chat 运行 |
| `autoteam resume` | 预览恢复列表 |
| `autoteam resume --apply` | 只恢复标记记录的 autopilot，清除标记；已取消的运行不会自动重跑 |
| `autoteam status [--check]` | 显示暂停状态；`--check` 在暂停时退出码为 1，供 agent 开工检查 |

这三个命令均支持 `--profile <名字>`。连续 stop 保留首次标记里的恢复列表；原来就 paused 的 autopilot 不会被 resume 启动。预览不会写 Multica。

## autoteam next

只读列出本项目下一轮巡检需要处理的 Multica 事项：指派给 Planner、前置批次均已 `done` 的 `todo`，以及最近一次运行失败的 `todo` / `in_progress`。每行显示任务编号、类别（`dispatchable` 或 `failed_run`）和原因。`--output json` 返回包含 `id`、`identifier`、`category`、`reason` 的数组；`--profile <名字>` 选择 Multica profile。

`autoteam next --check` 在清单为空时打印「无事可做」并返回 0，有事项时打印清单并返回 1，读取 Multica 失败时返回 2。此阶段只覆盖 Multica；GitHub PR 和合并状态由后续扩展加入。

## autoteam approve

`autoteam approve <父任务> [--apply] [--profile <名字>]`：一次放行整个拆分。列出父任务下所有指派给 Planner、状态为 `backlog` 的子任务并按批次预览，`--apply` 才把它们改成 `todo`。

- 第一个可派发的批次（前面批次的任务都已 `done`）：只有其中一个任务的状态变更会叫醒 Planner（最后改），其余带 `--no-start`；
- 后续批次一律带 `--no-start`，由批次屏障在前一批全部完成后叫醒 Planner；
- 逐条输出放行结果（成功或失败原因），并用 `multica issue runs` 核对 Planner 那次运行已生成；没生成会报错并提示在该任务下评论 @Planner 补一次，其余任务不必重做；
- 有任务放行失败或运行没生成时退出码为 1。

不改 `AUTOTEAM_AUTO_APPROVE`：新项目仍默认由人批准，这个命令只是把批准变成一次操作。

## autoteam propose

`autoteam propose [--title <PR 标题>] [--apply]`：把你本地的改动用 Implementer App 身份推到新分支并开 PR，你只负责批准。规则集开了 `require_last_push_approval` 后，你自己推的规则文件改动没法自己批准，这个命令代替「另开 clone、`--setup-git implementer`、换身份推送」这一串手工步骤。默认只预览（分支名 `propose/<UTC 时间戳>`、PR 标题、改动文件），`--apply` 才执行。

- 改动来源：工作区未提交的改动（含未跟踪文件，遵守 `.gitignore`），加上当前分支相对 `origin/<默认分支>` 的提交；两者都没有时报错；
- PR 标题默认取分支上最新提交的标题，没有提交就按改动文件生成；标题需要任务编号时用 `--title` 传入；
- 不改你的全局或仓库 git 配置、remote、工作区、暂存区和当前分支：改动快照用临时索引生成，提交作者是 App（`gh-app-token.sh --identity implementer`）；`git push` 直接推到 `https://github.com/<AUTOTEAM_REPO>.git`，凭据只通过这次 push 的 `-c credential.helper` 传入（先清空继承来的钥匙串助手），token 不落盘、不打印。你的 git 配置用 `url.*.insteadOf` 或 `pushInsteadOf` 改写了 push 实际地址时会拒绝执行（按 `git config` 里所有 insteadOf 规则逐条匹配），因为 push 会绕过 App 身份；
- 开 PR 在临时 worktree 里跑 `.autoteam/scripts/open-pr.sh`（合并模式、自动合并、核对都按它的约定），输出原样打印；执行后移除临时 worktree 和临时本地分支，远端分支留给 PR，不删除任何已有分支；
- open-pr.sh 失败时分支已在远端，命令返回 1 并提示；不替你批准或合并。

## autoteam doctor

只读检查，逐项给出 ✅ / ⚠️ / ❌，有 ❌ 时退出码为 1。

| 选项 | 说明 |
|---|---|
| `--skip-github` | 不检查 GitHub |
| `--skip-multica` | 不检查 Multica |
| `--profile`、`--workspace` | 同 autoteam multica |

检查项：工作流文件和受管块、`.lock.json` 的版本、Makefile 目标是否还是桩、CODEOWNERS、registry 是否合法；GitHub 的仓库设置、规则集、secret、CODEOWNERS 错误、机器账号、最近一次 gate；Multica 的 agent（存在、runtime 在线、指令和仓库文件一致、最近一次运行有没有失败）、项目及其唯一的「运营笔记」、autopilot 和触发器；以及 registry 里每个 agent 的 runtime 上有没有它角色的 App 私钥（按 `gh-app-token.sh --find-key` 的顺序查）——runtime 就是本机（本机 daemon 管着它）而缺私钥报 ❌，远端 runtime 从这里看不到磁盘，只提示到那台机器上跑 doctor。

## autoteam runtimes

列出工作区里的 runtime，第一列就是 registry.yaml 里 `runtime` 字段的写法（`provider@设备`）。

## autoteam diff

```bash
autoteam diff                       # 对比全部文件
autoteam diff .github/CODEOWNERS    # 只看某几个
autoteam diff --check               # 有差异就退出码 1，给 CI 用
```

对比已安装的文件和当前模板的渲染结果，受管块只比较块内内容。

`--check` 是给 CI 的漂移闸门：跳过 `autoteam.conf`、`registry.yaml`（装的是用户数据，本来就该不一样）；`.autoteam/.lock.json` 显示本地改过的文件（比如加了运行时的 gate.yml）报告为“本地已修改”，不算漂移。剩下的差异就是“模板更新了、文件还是装机时的样子”，打印 diff 并退出码 1，用 `autoteam upgrade` 更新。

## autoteam upgrade

```bash
autoteam upgrade              # 升级全部文件
autoteam upgrade --dry-run    # 只列计划
autoteam upgrade .github/workflows/gate.yml
```

`autoteam init` 在 `.autoteam/.lock.json` 记下版本和每个文件的 sha256（受管块记块内内容）。`upgrade` 拿现在的文件比一次：

- 和 lock 一致（没改过）：直接换成新模板，不需要 `--force`
- 不一致（本地改过）：不写，打印当前文件和新模板的差异，由你决定——保留改动就手工合并需要的部分，放弃改动就 `autoteam init --force <文件>`。包里不带历史模板，所以只有两方对比
- `autoteam.conf`、`registry.yaml`、`Makefile` 不动；缺的文件补上

结束后更新 lock 的版本号。`.lock.json` 要提交入库：它是全团队升级的依据。如果 lock 丢失，`upgrade` 会重新生成，和模板不一致的文件一律当作改过。

升级 autoteam 的步骤：更新 autoteam（`npx skills update autoteam` 或 `git pull`）→ `autoteam upgrade` → 处理它列出的本地改过的文件 → 提交、合并 → `autoteam multica --apply`。角色指令和 autopilot 不在 `autoteam diff` 的范围内：没 eject 的直接跟着包走，eject 过的用 `autoteam eject --diff` 看差异。

## autoteam eject

```bash
autoteam eject reviewer             # 角色名：planner / implementer / reviewer / auditor
autoteam eject patrol               # autopilot 名
autoteam eject planner-mcp.json
autoteam eject --all                # 全部
autoteam eject --diff reviewer      # 只看差异，不写文件
```

角色指令、autopilot、`planner-mcp.json` 默认不落盘在你的仓库里：`autoteam multica` 直接读 autoteam 包内的版本。`eject` 把包内的文件复制到 `.autoteam/instructions/`（`roles/<角色>.md`、`autopilots/<名字>.md`、`planner-mcp.json`），此后由你维护，升级不会覆盖；读取时优先用落盘的那份，删掉它就回到包内版本。已存在的文件不会被覆盖。

「开工先检查暂停」这段前言只在包内 `instructions/_preamble.md` 维护一份，不 eject；`autoteam multica` 同步时把它加在每份角色指令和 autopilot 正文的最前面，eject 出的文件里没有这段，也不要自己加。

`--diff` 打印包内文本和已 eject 文本的差异，没 eject 过的目标提示“未 eject”。升级 autoteam 之后，用它看包内的新版本改了什么，再手动合并进你的那份。
