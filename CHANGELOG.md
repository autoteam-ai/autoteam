# 更新记录

## 0.1.0（2026-09-20）

第一个版本。

- `aiwf init / github / multica / doctor / runtimes / diff` 六个命令，兼容 bash 3.2。
- 模板：四个角色指令、8 个 autopilot、gate / deploy / rollback 工作流、计费注册表、loop-guard 和 health-metrics 脚本。
- 适配 Multica 0.5 的状态模型：唤醒全部靠显式指派和 @提及。
- 按 GitHub 套餐识别保护等级（full / standard / none），支持单账号试用模式（`--trial`）。
- Agent Skill `ai-workflow`，可用 `npx skills add songhuangcn/ai-workflow --skill ai-workflow` 安装。
- 中文文档：概念、搭建步骤、日常操作、参考。
