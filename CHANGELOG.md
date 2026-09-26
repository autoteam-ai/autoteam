# 更新记录

## 未发布

- 文档：补充 Multica 0.5.1 任务级事件与定时 wakeup rule 的触发边界，并明确 autoteam 仅让人对已指派任务的普通评论使用默认唤醒；角色交接继续显式指派或 @提及。

### 行为变更：自定义状态只保留 `shipping`

- **去掉 `approved`、`code_review`、`rework` 三个自定义状态**：人批准 = 把任务从 `backlog` 改成 `todo`（指派人仍是 Planner），提交 PR 后改 `in_review`，打回后 Implementer 把任务改回 `in_progress`。Multica 0.5 起自定义状态不再负责唤醒，这三个状态在看板上只是重复了内置状态的意思；`shipping` 保留，部署通知和巡检补查靠它找「已合并、等线上验收」的任务。
- **需要升级步骤**：先把停在旧状态的任务分别移到 `todo` / `in_review` / `in_progress`，再到 Multica 界面归档这三个状态（类别建好后不能改，`--apply` 也不会删除状态）。步骤见[从旧版本升级](docs/setup/multica.md#从旧版本升级)。
- 文档（`docs/`、README）同步改成新的状态模型；指令、代码和测试的改动在另一个任务里。

### ⚠️ 破坏性变更：新目录布局 + `autoteam migrate`（结构重整 5/5）

结构重整（1/5–4/5）合起来是一次 breaking 升级，这一条是面向用户的汇总。已装机的项目要迁移，一条命令：

```bash
autoteam migrate --dry-run   # 只看计划
autoteam migrate             # 执行；不提交、不推送
```

- **`ops/` 下的 `agents/` 目录改名为 `.autoteam/`**，拍平：`autoteam.conf`、`registry.yaml`、`playbook.md`、`README.md`、`scripts/`、`local/` 直接在 `.autoteam/` 下。`.autoteam/.lock.json` 记装机版本和每个文件的 sha256。受管块（`.gitignore`、`.github/CODEOWNERS`、`AGENTS.md`）里的路径同步换掉；`AUTOTEAM_PR_SIZE_EXCLUDE` 的默认值换成 `.autoteam/**`。
- **角色指令、autopilot、`planner-mcp.json` 不再落盘**：`autoteam multica` / `autoteam doctor` 直接读 autoteam 包内的版本，规则由包版本固定。要按项目改某一份，`autoteam eject` 到 `.autoteam/instructions/`（受 CODEOWNERS 保护）。代价：升级时指令文本的变化不再出现在 PR diff 里，见 `docs/concepts/guardrails.md`。
- **`autoteam upgrade` 取代 `init --force` 的升级用法**；删除 `AUTOTEAM_DIFF_IGNORE`（`.lock.json` 自动推断哪些文件改过）；autopilot front matter 的 `cron:` 改为 `cron_key:`。
- **新增 `autoteam migrate [--dry-run]`**：识别旧版布局（配置放在 `ops/` 下的 `agents/` 子目录）→ `git mv` 成 `.autoteam/`（`local/` 私钥一起带走）→ 旧目录里的角色指令、autopilot、`planner-mcp.json` 逐个和包内文件比对，一致的删除，改过的保留到 `.autoteam/instructions/` 当作已 eject（旧路径先换成新路径、`cron:` 值等于 `autoteam.conf` 里的才算没改过；不一致的 `cron:` 会转成 `cron_key` 并提醒核对）→ 更新三个受管块 → 写 `.lock.json` → 列出仓库里其余仍写着旧路径的文件（README、workflow、AGENTS.md 正文，以及旧版装的 `.github/workflows/*.yml`、`.autoteam/scripts/*.sh`），**不自动改**，由人处理。逐条打印结果；只碰这些文件，不提交、不推送。`.autoteam/` 已存在时拒绝执行。
- `autoteam doctor` 发现旧版布局时只报一条 ❌，提示 `autoteam migrate`。
- 不为旧路径保留兼容读取：迁移是一次性的。
- 文档全面对齐新结构：「生成的文件」补目录树和「不再落盘」、命令参考补 `migrate` / `eject` / `upgrade`、配置参考补 `.lock.json`，并在安全边界和不变量里讲清楚“规则由包版本固定，改规则 = eject 后受 CODEOWNERS 保护，或升级版本（版本号变更本身受保护）”。

### `.lock.json` + `autoteam upgrade`，删 `AUTOTEAM_DIFF_IGNORE`（结构重整 4/5）

- **`autoteam init` 写 `.autoteam/.lock.json`**：包版本、`generated_at`，以及每个落盘文件的 sha256（受管块记块内内容）。`autoteam.conf`、`registry.yaml`、`Makefile` 是你的，不记。lock 要入库，它是全团队升级的依据；内容没变时不重写，不会因为时间戳多出 diff。
- **新增 `autoteam upgrade [--dry-run] [文件...]`**：现在的 sha 和 lock 一致（没改过）就直接换成新模板，不需要 `--force`；不一致（本地改过）只打印当前文件和新模板的差异，不写，给出下一步（保留就手工合并，放弃就 `autoteam init --force <文件>`）。包里不带历史模板，所以是两方对比。结束后 lock 的版本号推进到当前包。旧项目没有 lock 时，第一次 `upgrade` 生成它，和模板不一致的文件一律当作改过。
- **删除 `AUTOTEAM_DIFF_IGNORE`**：它记的就是"哪些文件我故意改过"，lock 能自动推断。`autoteam diff --check` 改为按 lock 判断，本地改过的报告为"本地已修改"、不算漂移。`autoteam init --force` 不再跳过任何模板文件——要安全升级用 `upgrade`。旧 `autoteam.conf` 里残留的这个键不再有作用，可以删掉。
- `autoteam doctor` 新增：`.lock.json` 的版本和当前包一致；不一致提示 `autoteam upgrade`，没有 lock 只提醒、不报错。

### 指令改为包内兜底 + `autoteam eject`（结构重整 3/5）

- **角色指令、autopilot、`planner-mcp.json` 不再落盘**：`autoteam multica` / `autoteam doctor` 优先读 `.autoteam/instructions/` 下已 eject 的那份，没有就用 autoteam 包内的 `instructions/`。`autoteam init` 不再生成它们；升级 autoteam 就升级了指令，漂移在结构上不可能发生。
- **新增 `autoteam eject <角色名|autopilot 名|planner-mcp.json|--all>`**：把包内文件复制到 `.autoteam/instructions/`，此后由你维护、升级不会覆盖；删掉就回到包内版本。`--diff` 只打印包内文本和已 eject 文本的差异。已知代价：升级时指令文本的变化不再出现在你的 PR diff 里，用 `autoteam eject --diff` 对比。
- autopilot front matter 的 `cron:` 改成 `cron_key:`，指向 `autoteam.conf` 里的 `AUTOTEAM_CRON_*`，同步时才取值；改 conf 后直接 `autoteam multica --apply`，不用重新渲染。`instructions/` 从此没有占位符。
- 本仓库删除自举副本和 `make selfhost` / `selfhost-check`。

### 升级的任务指派给人

- Planner 把任务设为 `blocked` 时，现在**同时把它指派给人**。原来球已经在人手里了，assignee 还挂在 agent 上，人得一列列翻看板才知道哪些等着自己。现在「指派给我的」就是完整待办清单：Backlog 列等批准、Blocked 列等决断，其余的列都是 agent 之间在流转。指派给成员不会启动任何 agent。

### doctor 提前发现缺私钥

- `autoteam doctor` 新增：对 registry 里每个 agent，看它的 runtime 是不是本机（本机 daemon 管着的 runtime）。是，就查这个角色的私钥在不在，缺了报 ❌ 并给出该放的位置（首选 `AUTOTEAM_KEYS_DIR`，文件名带角色名）；不是本机，只提示到那台机器上检查。
- `gh-app-token.sh` 新增 `--find-key <角色>`：只打印按既定顺序找到的私钥路径，不联网。doctor 直接调它，私钥的查找规则仍只有这一份。
- `planner.md`「派发」：派发前看 doctor 里该 Implementer / Reviewer 的私钥检查，未通过就留在 `approved` 并提及人。缺私钥原来要到 Implementer 开工才暴露，白耗两次运行和一次换人。

### 私钥要放机器上，不是仓库里

- **新增 `AUTOTEAM_KEYS_DIR`（默认 `~/.autoteam`）**，App 私钥的机器级目录。查找顺序：`AUTOTEAM_<角色大写>_APP_KEY` 指的路径 > 仓库的 `ops/agents/local/` > `AUTOTEAM_KEYS_DIR`。两处都支持 `~` 开头（shell 只展开字面量里的波浪号，从配置文件和环境变量读出来的要自己处理）。
- 起因是真机上两个 Implementer 同时卡住：`gh-app-token.sh --setup-git implementer` 退出码 1，`ops/agents/local/` 里没有私钥。**agent 每接一个任务都可能重新 checkout 一份仓库**，私钥只放在仓库里不会跟过去——这是个会反复发生、每次都要人去补的坑。两个 Implementer 都中枪之后 Planner 按规则换人一次、再失败升级给人，行为完全正确，但根因在这里。
- 借这次把 `doctor` 的私钥检查也改了：原来它只看 `ops/agents/local/<角色>.pem` 存不存在，私钥放别处就会误报"本机没有"。现在直接铸一次 token 看结果，并把"没有私钥"（正常，只有那台机器需要）和"有私钥但铸不出来"（真问题）分开报。

### 开始试行：团队自己跑这个仓库

- **六个 agent 全部搬到本地 runtime**。云端 runtime 上的 Claude 登录会过期（真机上 auditor 和 impl-claude 就因为 `OAuth session expired` 一起卡住，整条审计链停摆），本地 runtime 的登录跟着你自己的机器走，出问题也看得见。
- **定时任务按优先级降频**，配置在 `ops/agents/autoteam.conf` 末尾：流转心跳每 2 小时 → 每 4 小时；每日摘要和规则复盘不降（前者是人了解全局的唯一窗口，后者是把人工介入变成规则的地方）；五个审计和方向类 autopilot 每周 → 每月并分散到 1/8/15/22/25 号；老代码巡检每月 → 每季度。原来周一挤着 4 份报告，人一次看不完就会积压。退出试行期的依据写在 conf 的注释里，由 Planner 提任务、人批准。`docs/reference/config.md` 也给新装的项目加了同样的建议。
- **补上「合并了但没生效」这个静默缺口：同步 Multica 配置归 Planner**。角色指令和 autopilot 合并到 main 不等于 Multica 上的 agent 换了指令，中间这一步原来没有归属，只靠人记得跑 `autoteam multica --apply`，漏了也没人知道。现在改 `ops/agents/` 的任务，**验收标准里必须有「已同步、doctor 无漂移」一条**，Planner 在验收时和「部署结果」autopilot 里各跑一次。它只能搬 main 上人已经批准的内容，指令里明令禁止在未合并的分支上 `--apply`。代价是 Planner 手里有人的 multica 工作区权限（目前最宽的一处授权），已登记进[已知的偏离](docs/concepts/invariants.md)，等 Multica 支持更细的 agent 权限再收窄。
- **`docs/operations/daily.md` 加了「你的闸门在哪」**：五个必须人放行的地方各自在哪个平台、被什么挡住、什么时候会来。这张表就是「人还要介入多少次」的成本清单，「规则复盘」每周盯的是怎么把它变短。

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
