# 每周指标

这套流程有没有用，要看数字，而且看趋势比看绝对值重要。

## 每周关注的五个数

| 指标 | 从哪里来 | 说明 |
|---|---|---|
| Reviewer 一次通过率 | Auditor 的成绩单；`health-metrics.sh` 的 `first_pass_pct` | 太低：任务拆得太大，或 Implementer 不行；太高（接近 100%）：Reviewer 可能在放水 |
| 验收一次通过率 | 成绩单（【验收不通过】次数） | 低说明验收标准没写清，或实现和需求有偏差 |
| 升级到人的次数 | 每日摘要里的 blocked | 越来越多：流程在空转，要看是哪类升级 |
| 单任务花费 | 成绩单（`multica issue usage`） | 突然变高：任务变大了，或某个 agent 在打转 |
| 重复代码占比趋势 | 整合审计（`duplication_pct`） | 只降不升；涨了就是“向外长而不向内整合” |

## health-metrics.sh

Auditor 每周跑，你也可以随时在仓库里跑：

```bash
ops/agents/scripts/health-metrics.sh          # Markdown 表格
ops/agents/scripts/health-metrics.sh --json   # JSON
```

| 字段 | 含义 |
|---|---|
| `duplication_pct` | 重复代码占比（jscpd，配置在 .jscpd.json） |
| `legacy_touch_pct` | 近 30 天改过的文件里，上一次改动在一年以前的比例：老代码有没有人维护 |
| `rework_14d_pct` | 近 14 天改过的文件里，前 14 天也改过的比例：两周内返工 |
| `prs_7d.merged` | 近 7 天合并的 PR 数 |
| `prs_7d.size_p50` / `size_p75` | PR 改动行数的中位数和 75 分位 |
| `prs_7d.first_pass_pct` | 近 7 天合并的 PR 里，从没被打回的比例 |
| `prs_7d.avg_rejections` | 平均打回次数 |

跨文件调用数这类指标和语言强相关，脚本没有内置；需要的话在 Auditor 的 runbook 里加上你项目的计算方法。

## 看 Auditor 的报告

四份报告都会建成任务（create_issue），并 @Planner 把值得做的拆进 backlog：

- **agent 成绩单**（周一 8:00）：哪个 Implementer 该多派、哪个该少派，Planner 选人时会参考；
- **整合审计**（周一 9:00）：新增的重复实现、该复用却重写的地方；
- **规格对账**（周五 9:00）：任务的验收标准和实际代码不一致的地方；
- **老代码巡检**（每月 1 号）：一年没动、可能已经没用的模块。

Planner 拆出来的整改任务一样要你批准。业界经验是固定拿出 15–25% 的容量做整合和偿债，作为常态而不是一次性冲刺。
