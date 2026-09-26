---
title: 四条不变量
---

# 四条不变量

这套流程来自《自管理 Agent 团队研究》。那篇文章的结论压缩成一句话是：

> 自管理不是放任 agent，而是把人盯着的环节换成 agent 绕不过去的规则：写代码和评审分开身份，合并交给检查，完成看线上结果，派活按额度调度。人只需要判断一件事值不值得做。

下面四条是这句话拆出来的不变量。**实现可以换，不变量不能破。** 改动前先对照这张表，改动后确认每条的"怎么验证"还是绿的。

## 1. 写代码的不能评审自己

| | |
|---|---|
| 由什么保证 | Implementer 和 Reviewer 是两个不同的 GitHub App 身份；GitHub 不允许 PR 作者批准自己的 PR |
| 什么会破坏它 | 两个角色配成同一个 App ID；用同一个账号的 token 兜底；Reviewer 自己改代码再批准（它有写权限，只靠指令拦着） |
| 怎么验证 | `autoteam doctor` 在两个 App ID 相同、或 Reviewer App 缺 Contents 写权限时报错；真机验证过：Implementer App 批准自己开的 PR 会收到 `Can not approve your own pull request` |

> **Reviewer App 必须有 Contents 写权限。** GitHub 只把「有仓库写权限的身份」提交的批准计入必需审批数：只给 Pull requests 写权限的 App，批准会记录成 APPROVED 但不算数，PR 永远停在 `REVIEW_REQUIRED`。所以「评审者不能推代码」只是指令约束，和机器账号方案一样——**能当硬约束的只有「作者不能批准自己」**。

## 2. 能不能合并只由代码平台判断

| | |
|---|---|
| 由什么保证 | 规则集的必需检查 `check` 只认 GitHub Actions 上报的结果（integration_id 15368）；bypass list 留空，管理员也不例外 |
| 什么会破坏它 | 用 API 伪造状态；给谁开 bypass；在没有平台闸门的仓库里执行 `gh pr merge --auto`（它不报错，而是立即合并）；项目平台的状态被当成合并依据 |
| 怎么验证 | `merge-mode.sh` 每次开 PR 和批准前当场读分支上实际生效的规则；`autoteam doctor` 报出 bypass 非空和降级模式 |

## 3. 完成看线上真实结果

| | |
|---|---|
| 由什么保证 | Planner 只在部署之后按验收标准在线上逐条验证，证据贴进评论；不看代码、不看 PR 描述 |
| 什么会破坏它 | 验收标准写成"代码里有这个函数"这种在线上验不了的；PR 里写 `Closes` 让任务自动关闭；Planner 拿构建产物之外的东西当证据 |
| 怎么验证 | 每条验收标准都要写明在线上怎么验；规格对账 autopilot 每周核对验收标准和实际行为 |

## 4. 约束 agent 的规则文件只能由人批准

| | |
|---|---|
| 由什么保证 | CODEOWNERS 把 `.github/`、`.autoteam/`、`Makefile`、`.jscpd.json` 指给人；规则集要求 Code Owner 审批。**CODEOWNERS 不能写 App**，所以这里必须是人工账号 |
| 什么会破坏它 | 规则文件挪出 CODEOWNERS 覆盖范围；升级 autoteam 版本却不看指令文本的变化；关掉 Require review from Code Owners；用 `--trial` 长期运行（它会关掉 Code Owner 审批）；Planner 在没合并的分支上跑 `autoteam multica --apply`（指令里明令禁止：只能同步 main） |
| 怎么验证 | `autoteam doctor` 检查 CODEOWNERS 和规则集；`--trial` 下 doctor 会一直标黄 |

**指令不落盘不改变这条**：角色指令和 autopilot 由包版本固定，改规则的路径只剩两条——`autoteam eject` 后修改 `.autoteam/instructions/`（受 CODEOWNERS 保护），或升级 autoteam 版本（版本号变更本身受 CODEOWNERS 保护）。两条都要人批准；代价是升级时指令文本不再出现在 PR diff 里，见[规则由包版本固定](guardrails.md#规则由包版本固定指令不落盘)。

初期阶段可用 `AUTOTEAM_CODEOWNERS_GATE=off` 临时关闭这道升级闸门，见 playbook；何时恢复由人决定。

> **前提：仓库必须开启「Require review from Code Owners」。** Implementer 在任务明确要求时可以改规则文件并提 PR，全靠这条规则集把关；没开就不要放开这条权限（`autoteam github --apply` 会配置它）。没有任务要求时，Implementer 仍不得顺手改这些文件，也仍不能批准或合并 PR。

> **闸门是「人批准」，不是「agent 不能碰」。** agent 必须能对规则文件提 PR——工作流、角色指令、阈值都是项目的一部分，禁止 agent 提议改它们，等于每次改 CI 都要人自己写代码，agent 团队就没用了。所以 Implementer App 要给 `Workflows: 读写`（否则它推含 `.github/workflows/` 的提交会被 GitHub 直接拒），拦住它的是 CODEOWNERS 要求的人工批准，不是推送权限。

## 已知的偏离

和研究文档不一致的地方都记在这里，每条写明为什么。**不在这张表里的偏离就是走偏了。**

| 偏离 | 研究文档怎么写 | 现在怎么做 | 为什么 |
|---|---|---|---|
| 身份 | 三个 GitHub 机器账号 + fine-grained token | 三个 GitHub App + installation token | 不变量没变（两个不同身份），但不用注册邮箱和两步验证、不占席位，Reviewer 可以连写权限都不给。代价是私钥是长期凭据，比带过期时间的 token 权限宽 |
| 唤醒 | 自定义状态"进入即唤醒" | 人对已指派任务的普通评论用平台默认唤醒；角色交接靠显式指派和 @提及；任务级定时或事件规则按需单独创建 | Multica 0.5 的自定义状态不继承唤醒行为；0.5.1 新增任务级 wakeup rule，但自动为每个任务配置会增加循环触发风险 |
| 合并模式 | 只有"平台自动合并" | 加了 `staged` 和 `reviewer` 两种降级 | GitHub Free 私有仓库没有规则集；单身份时审批数只能设 0，检查一绿就合并，Reviewer 来不及看 |
| 每日摘要 | 直接运行 | 先建任务再运行（create_issue） | run_only 的结果只在运行历史里，人收不到通知 |
| 批准 | 人只需要判断一件事值不值得做：所有任务都由人批准 | `AUTOTEAM_AUTO_APPROVE=on` 时 Planner 自主放行低风险任务：不碰受保护路径（CODEOWNERS 覆盖的全部文件和 lock 文件），不涉及凭据、权限、部署、回滚、删数据、对外发布，单个子任务不超过行数上限、整个需求不超过 3 个子任务，不是新功能也不改方向；Auditor 和前沿扫描的建议优先级最高 `medium`；每天最多 `AUTOTEAM_AUTO_APPROVE_MAX_PER_DAY` 个，每个都有 `【自主放行】` 评论 | 过去 6 天 38 次批准决定大多当场就批，隔夜才批的任务白等 9–11 小时。「值不值得做」仍归人：新功能、方向调整和规则文件的改动照旧等人批准，不变量 4 不受影响；代码照样要过检查和独立评审 |
| Multica 配置同步 | 没提（默认规则文件合并即生效） | Planner 验收时跑 `autoteam multica --apply`，用的是人的 multica 凭据 | 合并到 main 不等于 Multica 上的 agent 换了指令，这一步原来没有归属、漂移是静默的。交给 Planner 的前提是它只能搬 main 上人已批准的内容。**代价是 Planner 手里有人的工作区权限，能改所有 agent 的配置，这是目前最宽的一处授权**；等 Multica 支持更细的 agent 权限再收窄 |

## 谁来对账

「路线图对账」autopilot 每周一对照这张表和研究文档检查一遍，发现漂移就拆成任务请人批准。这条不能只靠自觉——写进流程才会真的发生。
