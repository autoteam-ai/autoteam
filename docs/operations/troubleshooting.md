# 常见问题

先跑 `aiwf doctor`，它会指出大部分配置问题。任务卡住时，看运行记录：`multica issue runs <任务> --output json`。

## aiwf

| 现象 | 原因和处理 |
|---|---|
| `找不到 multica CLI` | `brew install multica-ai/tap/multica`；装了桌面端的，aiwf 也会找 `/Applications/Multica.app` 里自带的 CLI |
| `multica 默认 profile 没有配置服务器` | 有多个 profile 时 aiwf 不会猜：`--profile <名字>` 或 `export AIWF_MULTICA_PROFILE=<名字>`；一个都没有就先 `multica setup cloud` |
| `没有指定 Multica 工作区` | 在 `ops/agents/aiwf.conf` 写 `AIWF_MULTICA_WORKSPACE=<slug>`，或加 `--workspace` |
| `找不到 runtime xxx@yyy` | `aiwf runtimes` 看可选值；设备名要和 runtime 名称括号里的一致 |
| `registry.yaml 里这一行不是单行 flow 映射` | agents 下每个 agent 必须写成一行 `name: { k: v, ... }` |
| 新建状态失败 | 运行 aiwf 的人要是工作区 owner 或 admin；或者按提示在 Settings → Issue Statuses 手动建（key 一致） |
| `状态 xxx 已存在但类别是 ...` | 类别建好后不能改：在界面里归档这个状态，再重新运行 |
| `需要 xxx 的管理员权限` | gh 登录的账号对仓库没有 admin；换账号，或请管理员来运行 |
| 规则集、自动合并都“不可用” | GitHub Free 的私有仓库没有这些功能，见[保护等级](../concepts/guardrails.md#保护等级) |
| `这些设置没有生效（通常是套餐限制）：allow_auto_merge` | 同上：自动合并在 Free 的私有仓库里不可用 |
| 部署 webhook 已存在但 GitHub 上没有 secret | `aiwf multica --apply --rotate-webhook` 重新生成地址并写入 |

## 流程

| 现象 | 原因和处理 |
|---|---|
| 运行失败：`Failed to authenticate: OAuth session expired and could not be refreshed` | runtime 在线不代表 agent CLI 能用：那台机器上 Claude Code 等的订阅登录过期了，到机器上重新登录。`aiwf doctor` 会报出每个 agent 最近一次失败的原因；修好之前可以先在 registry.yaml 里把 agent 挪到别的 runtime |
| 运行失败：`You've hit your session limit · resets 1:10am` | 订阅的窗口额度用完了。平台不会自动重试额度类错误，任务停在原状态；Planner 下一次巡检会重新派发（额度恢复后也可以手动触发“推进巡检”）。同一个订阅账号下的所有 agent 共用额度，registry.yaml 里要如实写 account；额度经常不够，就加一个其他厂商或按量计费的 agent 分担 |
| 批准了任务，Planner 没反应 | 子任务要指派给 Planner、从 backlog 改成 approved 才会叫醒它；直接新建成 approved 的不会。也可能 Planner 的 runtime 离线，看 `aiwf runtimes` |
| Planner 派发了，Implementer 没开始 | runtime 离线或并发满了（任务在排队，排队超过 2 小时会失败）；或者 agent 是 private，而触发链路上的人不是 agent 的创建者：把 `AIWF_AGENT_ACCESS` 改成 workspace 后 `aiwf multica --apply --only agents` |
| Reviewer 没被叫醒 | 评论里只写了 `@名字`，没用提及链接 `[@名字](mention://agent/<UUID>)`；或者用了 `/note` |
| 改了状态为什么没人被叫醒 | Multica 0.5 起，自定义状态不再负责唤醒，唤醒只靠指派和 @提及，见[唤醒规则](../concepts/lifecycle.md#唤醒规则multica-05) |
| `Can not approve your own pull request` | Implementer 和 Reviewer 用的是同一个 GitHub 账号。准备机器账号；在此之前用试用模式（Reviewer 会改用【批准】评论评审） |
| PR 迟迟不合并 | 检查没过、审批数不够、CODEOWNERS 要求你批准（改了规则文件）、或者没开自动合并。`gh pr view <PR> --json mergeStateStatus,autoMergeRequest,reviewDecision` |
| PR 合并后任务直接变成 done 了 | PR 正文写了 `Closes XXX-123` 之类的关闭关键字，Multica 的 GitHub 集成会直接设为完成。只在标题写任务编号 |
| 运行失败后任务回到了 todo 而不是 rework | 平台的失败回滚只写内置状态，Planner 巡检时会处理 |
| 部署了但 Planner 没验收 | 看 deploy.yml 的 notify planner 步骤；“部署结果”是 run_only，Planner 的 runtime 离线时会跳过，巡检会补查超过 1 小时的待上线任务 |
| autopilot 自己停了 | 过去 7 天至少 50 次运行、失败率 90% 时平台会自动暂停，看运行历史里的报错 |
| agent 说“验证通过”但其实没跑 | 指令要求贴输出；不贴的在评审里打回。规律性出现就在 AGENTS.md 里补规则（带原因） |
| 同一个任务来回打转 | `ops/agents/scripts/loop-guard.sh <任务>` 看次数；到上限 Planner 会升级给你 |

## GitHub

| 现象 | 原因和处理 |
|---|---|
| 规则集要求的检查 `check` 一直是 Expected | gate.yml 没在这个 PR 上运行：确认它在默认分支上，触发条件包含 `pull_request` |
| 合并队列里的 PR 一直等 | gate.yml 必须有 `merge_group` 触发 |
| 自己改规则文件的 PR 合不了 | 没有别的 Code Owner 能批准，见[修改规则文件](daily.md#修改规则文件) |
| 机器账号的 fine-grained token 选不到仓库 | 个人账号的仓库，协作者只能用 classic token；或把仓库迁到组织下 |
