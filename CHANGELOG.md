# 更新记录

## 未发布

- **GitHub 身份从机器账号换成 GitHub App**。研究文档里是三个机器账号，现在是三个 App：不用注册邮箱和两步验证、不占席位，权限按 App 定义而不是靠选 token 范围，而且 Reviewer App 不给 Contents 写权限——它物理上推不了代码，比两个都是 Write 协作者的机器账号更严。核心不变量没变：Implementer 和 Reviewer 是两个不同身份，GitHub 挡住作者批准自己的 PR；两个 App ID 配成同一个时 `github` 和 `doctor` 都会报错。人工账号仍要留一个：CODEOWNERS 不能写 App，规则文件的 Code Owner 是人。
- 新增 `ops/agents/scripts/gh-app-token.sh`：用 App 私钥签 JWT 换 installation token（缓存到快过期才重铸），`--run` 带身份跑命令、`--setup-git` 配好 clone 的提交身份和凭据助手、`--credential` 做 git 凭据助手。agent 每次工具调用都是新 shell，所以身份必须跟着命令走，不能 `export GH_TOKEN`。
- `--setup-git` 会先用空值清掉继承来的凭据助手。不清的话，机器上 `gh auth login` 留下的系统钥匙串会抢先应答，**agent 会以人的身份推代码**——这个 bug 在实现时真的复现过。
- 真机验证时发现的一条额外收获：**用 Implementer App 推含工作流的提交会被 GitHub 拒绝**（缺 `workflows` 权限）。这把"Implementer 不能改 `.github/workflows/`"从指令约束变成了平台硬约束，机器账号做不到这一点。
- `autoteam.conf` 的 `AUTOTEAM_*_BOT` 换成 `AUTOTEAM_<角色>_APP_ID`；`autoteam github` 的 `--bots` 换成 `--apps`，行为从"邀请协作者"变成"核对 App 装好没有、权限对不对"——App 不能用 API 创建和安装，autoteam 不代做也不假装做了。
- `make check` 的 docker 回退改用 `--format=gcc`：镜像里的 shellcheck 是静态二进制、没有 locale 数据，默认格式要回显源码行，遇到中文就崩在 `commitBuffer: invalid argument`。设 `LANG` / `LC_ALL` 没用（四种组合都试过）。
- 统一 conf 读取：同名键第一条生效。CLI 一直是这样，而 `loop-guard.sh` 等脚本用 `tail -n 1` 是最后一条生效，用户追加一行覆盖时两边会读出不同的值。

- 新增基于 Starlight 的版本化文档站和 GitHub Pages 工作流：`docs/` 只维护开发版，构建时从所有 `v*` tag 提取历史文档，页面可在开发版与各发布版本之间切换。
- 新增 npm 包 `autoteam` 的清单（`package.json`，`bin` 指向 `bin/autoteam`）和 `make deploy`：发布前核对三处版本号、把打出的包装到临时目录跑一遍，再 `npm publish`；版本已发过则跳过，`DRY_RUN=1` 只演练。还没有真正发布过。
- 项目改名为 **autoteam**（原 ai-workflow）：CLI、skill、`ops/agents/autoteam.conf`、`AUTOTEAM_*` 变量、受管块标记和规则集名一并跟随。原名撞的是整个赛道——n8n、Dify、LangGraph 都自称 "AI workflow"，而这套东西做的是 agent 团队自治和合并闸门。
- 合并模式从两种扩展到三种，新增 **`staged`**：仓库有必需检查、但规则集不要求审批时（单账号的必然处境，GitHub 不允许作者批准自己的 PR），Implementer 开 draft PR 且不开自动合并，Reviewer 批准后 `gh pr ready` 放行。补上了“检查一绿就合并、Reviewer 来不及看”这个缺口。
- `merge-mode.sh` 改看 `repos/{repo}/rules/branches/{branch}`：读的是分支上实际生效的规则，别人另建的规则集、老的分支保护一样算数，不再只按名字找 `autoteam` 规则集。
- `autoteam multica --apply` 会纠正绑错项目的 autopilot，`autoteam doctor` 也把它当错误报出来。项目改名或重建后 autopilot 还绑着旧 project_id，它照常运行、照常成功，只是在旧项目里找任务，Planner 一直报"无待验收任务"。
- 配了 `env_file` 的 agent 每次 apply 都重写环境变量。env 读不回来没法比对，之前只看 mcp 不看 envf，换了机器账号的 token 会报"已是最新"却一次都没同步。
- `autoteam doctor` 报 agent 运行失败时带上时间：这条是历史记录，登录修好之后也要等下一次成功运行才消失。
- Planner 换人前先查任务有没有已经开好的 PR。E2E 里 Implementer 开完 PR 才撞到额度上限，巡检只看到运行失败就改派，新人把同一个功能重做了一遍，白花一份额度还留下两个 PR。有 PR 就直接转 `code_review` 交给 Reviewer。

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
