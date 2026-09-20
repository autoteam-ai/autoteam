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
| 由什么保证 | Implementer 和 Reviewer 是两个不同的 GitHub App 身份；GitHub 不允许 PR 作者批准自己的 PR。另外 Implementer App 没有 `workflows` 权限，推含 `.github/workflows/` 改动的提交会被 GitHub 直接拒——这条用机器账号做不到 |
| 什么会破坏它 | 两个角色配成同一个 App ID；用同一个账号的 token 兜底；Reviewer 拿到 Contents 写权限后自己改代码再批准 |
| 怎么验证 | `autoteam doctor` 会在两个 App ID 相同时报错；`autoteam github` 同样会拦。Reviewer App 不给 Contents 写权限，它物理上推不了代码 |

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
| 由什么保证 | CODEOWNERS 把 `.github/`、`ops/agents/`、`Makefile`、`.jscpd.json` 指给人；规则集要求 Code Owner 审批。**CODEOWNERS 不能写 App**，所以这里必须是人工账号 |
| 什么会破坏它 | 规则文件挪出 CODEOWNERS 覆盖范围；关掉 Require review from Code Owners；用 `--trial` 长期运行（它会关掉 Code Owner 审批）；给 Implementer App 加上 `workflows` 权限 |
| 怎么验证 | `autoteam doctor` 检查 CODEOWNERS 和规则集；`--trial` 下 doctor 会一直标黄 |

## 已知的偏离

和研究文档不一致的地方都记在这里，每条写明为什么。**不在这张表里的偏离就是走偏了。**

| 偏离 | 研究文档怎么写 | 现在怎么做 | 为什么 |
|---|---|---|---|
| 身份 | 三个 GitHub 机器账号 + fine-grained token | 三个 GitHub App + installation token | 不变量没变（两个不同身份），但不用注册邮箱和两步验证、不占席位，Reviewer 可以连写权限都不给。代价是私钥是长期凭据，比带过期时间的 token 权限宽 |
| 唤醒 | 自定义状态"进入即唤醒" | 全部靠显式指派和评论里的 @提及 | Multica 0.5 改了状态模型，自定义状态不再继承这类行为 |
| 合并模式 | 只有"平台自动合并" | 加了 `staged` 和 `reviewer` 两种降级 | GitHub Free 私有仓库没有规则集；单身份时审批数只能设 0，检查一绿就合并，Reviewer 来不及看 |
| 每日摘要 | 直接运行 | 先建任务再运行（create_issue） | run_only 的结果只在运行历史里，人收不到通知 |

## 谁来对账

「路线图对账」autopilot 每周一对照这张表和研究文档检查一遍，发现漂移就拆成任务请人批准。这条不能只靠自觉——写进流程才会真的发生。

<!-- probe -->
