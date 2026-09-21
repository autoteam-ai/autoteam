<!-- >>> autoteam >>> -->
## AI 团队工作流

本仓库由 Planner / Implementer / Reviewer / Auditor 四个 agent 协作开发，角色指令和配置在 `ops/agents/`。

- 全部检查只用 `make check`（CI 也只调它）；起环境用 `make dev`，可以重复执行。
- 不要声称验证通过，除非你真的跑了；因故没跑，就写明没跑什么、为什么。
- PR 标题以任务编号开头（如 `{{AUTOTEAM_ISSUE_PREFIX}}-123 按日期导出订单`），不写 `Closes` / `Fixes` 等关闭关键字：任务要等线上验收通过才算完成。
- `.github/`、`ops/agents/`、`Makefile`、`.jscpd.json` 是约束 agent 的规则文件，受 CODEOWNERS 保护，改动必须由人批准才能合并。Implementer 只在任务明确要求时才改这些文件并提 PR；没有任务要求就不要顺手改，发现问题写进评论的“范围外发现”。
<!-- <<< autoteam <<< -->
