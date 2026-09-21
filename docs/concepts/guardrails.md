---
title: 安全边界和保护等级
---

# 安全边界和保护等级

## 代码平台和项目平台

| | 代码平台（GitHub） | 项目平台（Multica） |
|---|---|---|
| 负责 | 合并规则、自动检查、部署 | 任务状态、角色配置、触发和定时 |
| 谁能改 | 只有人 | agent 和人 |

**能不能合并只由代码平台判断，项目平台的状态只用来调度**，因为 agent 能改的状态拦不住 agent。

## 哪些是硬约束

| 约束 | 由什么保证 | agent 能绕过吗 |
|---|---|---|
| 写代码的不能评审自己 | Implementer、Reviewer 用两个不同的 GitHub App；GitHub 不允许作者批准自己的 PR | 不能（前提是两个 App 不同） |
| 不过检查不能合并 | 规则集的必需检查 `check`，只认 GitHub Actions 上报的结果（integration_id 15368），防止用 API 伪造状态 | 不能 |
| 新提交会作废旧批准 | 规则集：dismiss stale reviews、require approval of the most recent push | 不能 |
| 规则文件只能由人改 | CODEOWNERS 保护 `.github/`、`ops/agents/`、`Makefile`、`.jscpd.json`，规则集要求 Code Owner 审批 | 不能 |
| 任何人都不能豁免 | 规则集的 bypass list 留空，管理员也不例外 | 不能 |
| 强推、删主干 | 规则集：restrict deletions、block force pushes | 不能 |
| PR 不超过 400 行、重复代码不超标 | gate.yml 里的检查（阈值在受保护的文件里） | 不能 |

## 哪些只是指令约束

| 约束 | 风险 | 怎么发现 |
|---|---|---|
| 只有人能把任务改成“已批准” | agent 也有改状态的权限 | 每日摘要里的批准核对 |
| Planner 不写代码 | 它的机器上有代码 | Planner 用只读 + Actions 的 token（planner 账号） |
| 验收要看线上真实结果 | Planner 可能偷懒只看代码 | 评论里必须贴证据；人每周抽查 |
| 打回、验收失败到上限就升级 | agent 可能忘记 | loop-guard.sh 从记录里算，巡检重新计算 |

## 保护等级

`autoteam github` 会按仓库的归属和套餐判断能做到哪一级：

| 等级 | 仓库 | 规则集 | 自动合并 | 合并队列 | 谁来合并 |
|---|---|---|---|---|---|
| full | 组织的公开仓库；组织私有仓库 + Enterprise Cloud | 有 | 有 | 有 | 平台：检查通过后自动合并，合并队列保证合并前在最新主干上重跑检查 |
| standard | 个人公开仓库；个人 Pro、组织 Team 的私有仓库 | 有 | 有 | 没有 | 平台：检查通过后自动合并 |
| none | GitHub Free 的私有仓库 | **没有** | **没有** | 没有 | Reviewer 批准后，等检查全绿自己合并（降级模式） |

- standard 没有合并队列：两个 PR 各自检查通过、先后合并后，主干上的组合可能是坏的。靠合并后的部署、Planner 验收和巡检兜底。
- none 是降级模式：所有“硬约束”都退化成指令约束，`autoteam doctor` 会一直标黄提醒。适合先试用，正式用请把仓库改公开、升级 Pro，或迁到 Team 套餐的组织，再运行一次 `autoteam github --apply`。

## 谁来合并：三种模式

保护等级说的是平台能提供什么，合并模式说的是在这个前提下 Implementer 和 Reviewer 各做什么。`ops/agents/scripts/merge-mode.sh` 每次开 PR 和批准前当场判断，依据是这个分支上**实际生效**的规则（`repos/{repo}/rules/branches/{branch}`，规则集和老的分支保护合并后的结果）加上仓库有没有开自动合并：

| 输出 | 触发条件 | Implementer | Reviewer | 检查能绕过吗 |
|---|---|---|---|---|
| `platform` | 有必需检查，且规则集要求至少 1 个审批 | 正常开 PR + `gh pr merge --auto --squash` | `gh pr review --approve`，然后什么都不用做 | 不能 |
| `staged` | 有必需检查，但不要求审批（单身份只能这样） | 开 **draft** PR，不开自动合并 | 批准后 `gh pr ready` 再 `gh pr merge --auto --squash` | 不能 |
| `reviewer` | 没有必需检查，或仓库没开自动合并 | 不执行任何 `gh pr merge` | 等检查全绿后 `gh pr merge --squash --delete-branch` | 能（只剩指令约束） |

两个容易踩的坑：

1. **没有平台闸门时 `gh pr merge --auto` 不报错，而是立即合并**，绕过评审和检查。端到端验证时真的发生过：PR 创建 7 秒后就被合并了。所以 `reviewer` 模式下 Implementer 绝对不碰 merge 命令。
2. **只有必需检查、不要求审批，等于 Reviewer 没有闸门**。这是单身份的必然处境：GitHub 不允许作者批准自己的 PR，审批数只能设 0，于是检查一绿平台就合并，Reviewer 来不及看。`staged` 模式用 draft PR 补上这一环——draft 本来就不能开自动合并，Reviewer 不 `gh pr ready`，谁都合不了，而检查仍然由平台强制。它不是硬约束（Implementer 理论上可以自己 ready），但比“一绿就合”强得多。

## 单账号试用模式

还没建好 GitHub App 时，Implementer 和 Reviewer 只能用同一个身份，GitHub 不允许它批准自己的 PR。`autoteam github --apply --trial` 会把规则集改成不要求审批（也不要求 Code Owner 审批和最后一次推送审批），其余规则不变：

- Reviewer 的 `gh pr review --approve` 会失败，指令里要求它改用评论评审，并以【批准】或【阻塞】开头，打回次数照样能统计；
- 合并模式落到 `staged`：Implementer 开 draft PR，Reviewer 批准后才 `gh pr ready` 放行。检查依然是硬闸门，但“评审过了才能合”这一条退化成指令约束；
- 评审独立性不再由平台保证，`autoteam doctor` 会标黄；
- 建好 App 后：App ID 写进 autoteam.conf 的 `AUTOTEAM_IMPLEMENTER_APP_ID` / `AUTOTEAM_REVIEWER_APP_ID`，私钥放到各自机器，然后不加 `--trial` 重新运行 `autoteam github --apply`。模式会自动变成 `platform`，不需要改任何指令。

## 凭据

- 每个 App 只装本仓库、权限给到最小（见[第 1–3 步 GitHub](../setup/github.md#三个-github-app)）。注意 **Reviewer App 必须有 Contents 写权限**，否则它的批准不计入必需审批数；「评审者不能推代码」因此只是指令约束。
- App 私钥是长期凭据，只放需要它的那台机器上；不同角色跑在不同机器（至少不同系统用户或容器），避免互相读到私钥。泄露了到 App 设置里删掉那把 key 重新生成，已铸出的 token 最多 1 小时后失效。
- Multica agent 的 `custom_env`（registry 的 `env_file`）以明文存在 Multica 服务端，不要放生产数据库密码这类高价值的长期凭据。
- 部署 webhook 地址里带凭据，只存在 GitHub secret `MULTICA_DEPLOY_HOOK` 里，autoteam 不会打印它；泄露了就 `autoteam multica --apply --rotate-webhook` 重新生成。
