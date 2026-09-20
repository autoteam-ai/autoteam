# 更新记录

## 未发布

- 新增基于 Starlight 的版本化文档站和 GitHub Pages 工作流：`docs/` 只维护开发版，构建时从所有 `v*` tag 提取历史文档，页面可在开发版与各发布版本之间切换。
- 新增 npm 包 `autoteam` 的清单（`package.json`，`bin` 指向 `bin/autoteam`）和 `make deploy`：发布前核对三处版本号、把打出的包装到临时目录跑一遍，再 `npm publish`；版本已发过则跳过，`DRY_RUN=1` 只演练。还没有真正发布过。
- 项目改名为 **autoteam**（原 ai-workflow）：CLI、skill、`ops/agents/autoteam.conf`、`AUTOTEAM_*` 变量、受管块标记和规则集名一并跟随。原名撞的是整个赛道——n8n、Dify、LangGraph 都自称 "AI workflow"，而这套东西做的是 agent 团队自治和合并闸门。
- 合并模式从两种扩展到三种，新增 **`staged`**：仓库有必需检查、但规则集不要求审批时（单账号的必然处境，GitHub 不允许作者批准自己的 PR），Implementer 开 draft PR 且不开自动合并，Reviewer 批准后 `gh pr ready` 放行。补上了“检查一绿就合并、Reviewer 来不及看”这个缺口。
- `merge-mode.sh` 改看 `repos/{repo}/rules/branches/{branch}`：读的是分支上实际生效的规则，别人另建的规则集、老的分支保护一样算数，不再只按名字找 `autoteam` 规则集。
- `autoteam multica --apply` 会纠正绑错项目的 autopilot，`autoteam doctor` 也把它当错误报出来。项目改名或重建后 autopilot 还绑着旧 project_id，它照常运行、照常成功，只是在旧项目里找任务，Planner 一直报"无待验收任务"。
- 配了 `env_file` 的 agent 每次 apply 都重写环境变量。env 读不回来没法比对，之前只看 mcp 不看 envf，换了机器账号的 token 会报"已是最新"却一次都没同步。
- `autoteam doctor` 报 agent 运行失败时带上时间：这条是历史记录，登录修好之后也要等下一次成功运行才消失。

## 0.1.0（2026-09-20）

第一个版本。

- `autoteam init / github / multica / doctor / runtimes / diff` 六个命令，兼容 bash 3.2。
- 模板：四个角色指令、8 个 autopilot、gate / deploy / rollback 工作流、计费注册表、loop-guard 和 health-metrics 脚本。
- 适配 Multica 0.5 的状态模型：唤醒全部靠显式指派和 @提及。
- 按 GitHub 套餐识别保护等级（full / standard / none），支持单账号试用模式（`--trial`）。
- Agent Skill `autoteam`，可用 `npx skills add autoteam-ai/autoteam --skill autoteam` 安装。
- 中文文档：概念、搭建步骤、日常操作、参考。
- 端到端验证中补的修正（详见 docs/setup/first-run.md）：
  - 规则文件和 Markdown 不计入 PR 行数与重复代码检查；
  - doctor 报出 agent 最近一次运行失败的原因（订阅登录过期、额度用完）；
  - Planner 在子任务全部完成后整体验收并关闭父任务；
  - 角色指令加常用命令表；
  - 新增 merge-mode.sh：没有平台闸门时 Implementer 不开自动合并（`gh pr merge --auto` 会立即合并），由 Reviewer 批准后合并；
  - `autoteam init --force <文件...>` 只覆盖指定文件，升级时不动改过的文件。
