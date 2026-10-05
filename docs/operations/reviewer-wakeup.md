---
title: Reviewer 条件唤醒验收
---

# Reviewer 条件唤醒验收

Reviewer 的执行依据是 `skills/autoteam/instructions/roles/reviewer.md`。CI 未结束时注册一次性、有期限的 Multica 条件唤醒，释放当前运行；检查已完成直接评审。合并闸门和权限保持原样。

## CLI 约定

先实跑 `multica issue wakeup create --help`。本次开发实跑输出附在 HDGCS-207 的 PR 正文，未给 CLI 或平台行为新增测试桩。`--until-pr checks` 等待任务关联 PR 的更新的已结束结果，不代表通过，也不接受 PR 编号；注册前用 `multica issue pull-requests <任务> --output json` 匹配 `html_url` 核实任务关联。`--parent` 保存原评论线程，`--agent-id` 显式指向 Reviewer。使用 `--expires-in 2h --on-timeout wake`，到期让 Reviewer 给出阻塞结论。

等待 instruction 文件须保存 PR URL、head SHA、Reviewer UUID、原线程、注册时刻、原期限及重入动作。注册前通过 `wakeup list` 查重，核对实际返回字段，不能凭空假定字段名。已启用的同一等待复用且不重设期限，新 head 禁用旧等待后按原剩余期限重新注册；禁止改其他 agent 的规则。注册失败不能报告正在等待唤醒。

注册后立即复核检查，补上“检查在读取和注册之间结束”的竞态；已结束则禁用本规则，直接处理通过或失败。每次重入重新读取 GitHub 当前 head 和检查，旧 head 或其他关联 PR 的结束事件不代表当前 head 通过。到期仍 pending 时升级 Planner，不自动续期；批准及放行前再核对 head。

## 合并后线上演练

先由人批准并合并指令 PR，再从已合并默认分支运行 `bash ./autoteam multica --apply` 和 `bash ./autoteam doctor`，保存同步结果及无指令漂移输出。不要在未批准的开发分支将新规则同步到线上。

选有较慢 CI 的真实任务 PR，记录任务、原线程、Reviewer、PR URL、head、规则 ID 和期限。用平台运行记录及 `multica issue wakeup list/get/runs` 收集证据，观察不要求占用一个 agent 运行轮询。下表是待执行的线上验收，不是已通过的测试结果：

| 情形 | 操作 | 必须看到的结果 |
|---|---|---|
| 慢检查完成 | 原线程触发评审，检查未结束 | 一次性规则绑定 Reviewer、原线程，期限 2h；当前运行结束；检查完成启动新运行，复核 head 后给结论 |
| 新 push | 等待 head A 时推送 B，让 A 先结束 | 不批准 B；禁用 A 的等待，对 B 重新检查；B 通过才评审并在批准前复核 |
| 检查失败 | 当前 head 的检查失败（也测失败与 pending 并存） | 结束事件不当成功；走原打回及 loop-guard 路径，无批准/合并 |
| 超时 | 在独立演练任务用短 `--expires-in` 模拟超出期限 | timeout 启动一次，仍 pending 则原线程提及 Planner，无无限续期；期限内已完成则处理真实结论 |
| 重复注册 | 相同 head 等待期间再次触发 Reviewer | 复用原规则，规则数及原期限不增长；其他 agent 的规则不变 |
| 注册竞态 | 读取 pending 后、注册前让检查结束 | 注册后复读走直接路径，禁用本等待，不依赖下一次检查事件 |
| 已完成 | Reviewer 开始时当前 head 已全部通过 | 直接评审，不创建无用规则；无检查或 API 错误不能当成功 |

验收评论附运行与规则记录、当前 head、GitHub 检查结论及线程证据；未完成项明确保留，由 Planner 组织后续验收。完成规则不要删除以免丢失审计信息，遗留启用规则只禁用自己的等待。
