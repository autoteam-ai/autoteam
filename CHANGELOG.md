# 更新记录

## 未发布

- **autopilot 改用 agent ID 而不是名字**。Multica 按名字解析 agent 是模糊匹配：工作区里只要存在名字包含它的另一个 agent（比如 `ex-planner` 之于 `planner`），就会报 `ambiguous agent`，8 个 autopilot 全部创建/更新失败。真机装配时撞到的。

### 真机验证修正的两条

- **Reviewer App 必须有 Contents 写权限**。GitHub 只把「有仓库写权限的身份」提交的批准计入必需审批数：只给 Pull requests 写权限的 App，批准会记录成 APPROVED 但不算数，PR 永远停在 `REVIEW_REQUIRED`。原来按「Reviewer 只读、物理上推不了代码」设计，真机一跑就卡住；`github` 和 `doctor` 现在会在 Reviewer App 缺写权限时报错。代价是「评审者不能推代码」退回指令约束，和机器账号方案一样——**能当硬约束的只有「作者不能批准自己」**，这条已真机验证（Implementer App 批准自己开的 PR 收到 `Can not approve your own pull request`）。
- **Implementer App 要给 `Workflows` 读写权限。** 之前把「App 推不了工作流」当成硬约束的收获写进了不变量表，这是判断错误：**闸门应该是「人批准」而不是「agent 不能碰」**。工作流也是项目的一部分，禁止 agent 提议改它，等于每次动 CI 都要人自己写代码，agent 团队就没意义了。缺这个权限连含 `.github/workflows/` 改动的 PR 都提不了；拦住它的是 CODEOWNERS 要求的人工批准。`github` 和 `doctor` 现在会在缺这个权限时提醒。

### 自举：autoteam 开始用 autoteam 开发自己

- 本仓库装上了自己：`ops/agents/`（四个角色、10 个 autopilot、经验库、四个脚本）全部由 `autoteam init` 生成。每一条规则先落在自己身上，模板改坏了先坏的是自己的团队。
- `make check` 加了 **`selfhost-check`**（`autoteam diff --check`）：模板和本仓库那份副本漂移就挡住 PR。因此改模板的 PR 必须同一个 PR 里跑 `make selfhost` 同步，必然带上 CODEOWNERS 保护的路径——**改规则一律由人批准**，这是设计。
- 新增 `autoteam diff --check`：有差异退出码 1，跳过 `autoteam.conf` / `registry.yaml`（用户数据）和 `AUTOTEAM_DIFF_IGNORE` 登记的文件。
- **`autoteam init --force` 现在也尊重 `AUTOTEAM_DIFF_IGNORE`**，不再覆盖你有意改过的文件（显式点名时才动）。这正是 first-run 记录里第 6 条踩过的坑。
- `make dev` 起沙盒仓库（`tests/dev-sandbox.sh`）：用桩把 init 和 doctor 跑一遍，Implementer 每次开工先跑它确认当前代码是好的。
- **`make deploy` 和 `make publish` 拆开**。deploy = 打包 + 装进干净仓库真跑一遍，产物 `build/pkg/*.tgz` 由 CI 传成 artifact，Planner 下载它做线上验收——验的是真实可安装的制品，不是代码。publish = 发 npm，**不接进任何自动流程**，由人执行：它撤不回（npm 72 小时后连 unpublish 都不行），而 `package.json` 受 CODEOWNERS 保护，所以"什么时候发版"始终在人手里。

### 规则和频率全部参数化

- 硬编码挪进 `autoteam.conf`：`AUTOTEAM_MAX_IMPLEMENTER_SWITCHES`（原来写死在 loop-guard.sh 里）、`AUTOTEAM_SHIPPING_RECHECK_HOURS`（原来写死在 patrol 正文）、`AUTOTEAM_METRICS_DAYS`，以及 9 个 `AUTOTEAM_CRON_*`。Planner 因此能提出具体到某个参数的改进建议。
- 阈值和 cron 的处理方式不同：阈值写成"读 conf"，改完立即生效；cron 必须渲染进 front matter（Multica 要具体值），改完要 `autoteam init --force <文件>` 再 `multica --apply`。

### Planner 的经验积累和学习闭环

- 新增 `ops/agents/playbook.md`：本项目的经验库（拆任务、验收口径、选人、参数为什么是这个值、踩过的坑），Planner 每次开工必读，由它提议、由人批准。
- Planner 多了一条长期的「运营笔记」任务：日常观察随手记，不走 PR。两层记忆的区别是——playbook 约束行为，笔记是素材。
- 新增「规则复盘」autopilot（每周一 12:00）：读 Auditor 报告 + 人工介入记录 + 运营笔记，产出四类建议（加经验、调参数、改指令、补流程缺口），拆成任务等人批准。判断标准只有一个：**能不能减少下一周的人工介入**。
- Planner 指令新增「你可以自己决定」清单，和原有的「你不能」对称——自由度要写出来才存在。
- `health-metrics.sh` 新增 `human_7d`（人自己提交和评审 PR 的次数），[docs/operations/metrics.md](docs/operations/metrics.md) 把它列为第六个指标，**目标是下降**：这是判断规则有没有在变好的唯一客观指标。

### Auditor 的前沿扫描

- 新增「前沿扫描」autopilot（每周一 11:00）：查 agent CLI、模型能力、额度规则、Multica 和 GitHub 平台的变化，判断哪条指令或参数因此不再适配，结论要具体到文件和行。防止项目一直在旧知识下演进。

### 防走偏

- 新增 [docs/concepts/invariants.md](docs/concepts/invariants.md)：把研究文档的四条不变量固化成"改动前对照"的表（由什么保证 / 什么会破坏 / 怎么验证），附已知偏离登记。「路线图对账」autopilot 每周多做一次不变量对账。

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
