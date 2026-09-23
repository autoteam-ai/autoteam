# .autoteam

这个目录定义了本仓库的自管理 agent 团队，由 [autoteam](https://github.com/autoteam-ai/autoteam) 生成。
整个目录受 CODEOWNERS 保护，修改走 PR，由人批准。

| 文件 | 作用 |
|---|---|
| `autoteam.conf` | 仓库、负责人、Multica 工作区、各种上限 |
| `registry.yaml` | 计费注册表 + 团队清单：有哪些 agent、什么角色、用哪个账号、跑在哪个 runtime |
| `planner.md` `implementer.md` `reviewer.md` `auditor.md` | 四个角色的指令，Multica 里 agent 的指令从这里同步 |
| `autopilots/*.md` | 定时和 webhook 触发的 runbook，front matter 是触发配置 |
| `planner-mcp.json` | Planner 线上验收用的浏览器自动化（Web 项目可选） |
| `scripts/loop-guard.sh` | 统计打回和验收不通过的次数，判断是否升级给人 |
| `scripts/merge-mode.sh` | 判断这个 PR 由谁放行、由谁合并（platform / staged / reviewer） |
| `scripts/health-metrics.sh` | 代码健康指标，Auditor 每周用 |

改了角色指令、registry 或 autopilot，合并到默认分支后运行：

```bash
autoteam multica --apply   # 同步到 Multica
autoteam doctor            # 逐项检查，能发现 Multica 里的指令和这里不一致
```
