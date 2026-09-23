---
name: autoteam
description: 把“自管理 agent 团队”工作流装进当前项目：Planner / Implementer / Reviewer / Auditor 四个角色，GitHub 负责合并闸门，Multica 负责任务调度。会生成规则文件和角色指令、按技术栈适配 make check/dev/deploy、配置 GitHub 规则集和 Multica 的状态、agent、autopilot，最后用 autoteam doctor 验收。用户说“搭建自管理 agent 团队”“接入 autoteam”“配置 Planner/Implementer/Reviewer/Auditor”“用 Multica 管 agent 团队”“set up the AI agent team workflow”时使用；升级、检查或排查这套流程时也用。
---

# autoteam：把自管理 agent 团队装进项目

工具是本 skill 目录下的 `bin/autoteam`，一律用 `bash ${CLAUDE_SKILL_DIR}/bin/autoteam <命令>` 调用（不依赖可执行位），下文简写为 `autoteam`。每个命令都有 `-h`。

## 硬约束

- 不替用户创建 GitHub 或 Multica 账号，不生成、不输入、不打印任何 token。需要这些时，列出步骤让用户自己做。
- `autoteam github`、`autoteam multica` 先不加 `--apply` 跑一遍预览，把预览结果讲给用户听，得到明确同意后才加 `--apply`。
- 不覆盖用户已有的文件；`autoteam init --force` 只在用户看过 `autoteam diff` 并同意后才用。
- `make check`、`make dev`、`make deploy` 必须真的跑通再交付，不要编造命令，也不要声称跑过没跑的东西。

## 步骤

### 0. 前提

1. 当前目录是 git 仓库，有 GitHub remote；`gh auth status` 已登录，并且对仓库有 admin 权限；有 `jq` 和 `curl`。
2. `multica version` 能用；没有就让用户装：`brew install multica-ai/tap/multica`。版本过低时升级。
3. 问清楚这几件事（已知的就不用问）：
   - 仓库归属和套餐：个人还是组织、公开还是私有、GitHub Free / Pro / Team。它决定平台闸门能做到什么程度（见 `docs/concepts/guardrails.md` 的保护等级）；
   - 有没有给 Implementer、Reviewer 建好 GitHub App（两个不同的 App）；没有就用单身份试用模式（`autoteam github --trial`）；
   - Multica 工作区 slug，以及有哪些订阅账号、哪几台机器在跑 Multica daemon。

### 1. 生成文件

`autoteam init --workspace <slug>`。看输出：因为已存在而被跳过的文件，用 `autoteam diff <文件>` 看差异，手动合并；受管块（`>>> autoteam >>>` 之间）以外的内容不要动。

### 2. 适配（需要判断的部分）

1. **Makefile**：按 [references/adapt-make.md](references/adapt-make.md) 识别技术栈，把项目已有的 lint、类型检查、测试串成 `make check`；`make dev` 一条命令起环境，而且可以重复执行（项目有 docker compose 就优先用）；`make deploy` 用项目现有的部署方式，没有部署就问用户。三个目标都要实际跑一遍，把结果给用户看。
2. **工作流**：`.github/workflows/gate.yml`、`deploy.yml`、`rollback.yml` 里补上 `make check`、`make deploy` 需要的运行时（setup-node 之类）和 secrets，其他步骤不改。
3. **AGENTS.md**：受管块以外，按 [references/write-agents-md.md](references/write-agents-md.md) 补“从代码里看不出来、或者容易搞错”的规则，控制篇幅。
4. **registry.yaml**：和用户确认订阅账号和机器，用 `autoteam runtimes` 列出 runtime，填 `provider@设备`。Implementer 和 Reviewer 尽量放不同机器、用不同厂商；Planner 用最强的模型；按量计费的 agent 用 `env_file` 指向 `ops/agents/local/` 下的 JSON 文件（让用户自己填 key）。
5. **autoteam.conf**：`AUTOTEAM_MULTICA_WORKSPACE`、`AUTOTEAM_HUMAN`（负责批准的成员名）、三个 `AUTOTEAM_*_APP_ID`。

改完再跑一次 `autoteam doctor --skip-github --skip-multica`，本地部分应该全绿。

### 3. 提交

新建分支、提交、开 PR，请用户审阅后合并。这些都是约束 agent 的规则文件，本来就该由人批准。

### 4. GitHub

`autoteam github` 预览，给用户解释保护等级（full / standard / none）、`--trial` 的含义和要做的改动。用户同意后：`autoteam github --apply`，按情况加 `--trial`、`--apps impl=<App ID>,review=<App ID>,planner=<App ID>`。App 只能由人创建和安装，autoteam 只核对。

### 5. Multica

`autoteam multica` 预览，给用户看会建哪些状态、agent、autopilot。用户同意后 `autoteam multica --apply`；想先配好、晚点再让定时任务跑起来，加 `--paused`。

### 6. 必须由人做的事

按用户的情况，从 [references/manual-steps.md](references/manual-steps.md) 里挑出相关的列给用户：建 GitHub App 和放私钥、各机器上跑一次 `gh-app-token.sh --setup-git`、Multica daemon 和 runtime、Multica 的 GitHub 集成、套餐升级。

### 7. 验收

`autoteam doctor`，逐条解释 ⚠️ 和 ❌。处理完后，建议用户跑一个小需求演练一遍（autoteam 文档的 `docs/setup/first-run.md`）。

## Planner 推进已有任务

人工评论、补充说明、回答问题或状态变化后，先核对原任务描述和验收标准；仍成立就在原任务继续派发、返工或验收。建子任务前除搜索查重，还要检查有没有可以直接推进的原任务。验收失败、评审打回和人工反馈均回原任务处理，父任务整体验收失败回对应原子任务返工；仍遵守批准要求及升级次数上限。只有目标或范围确实变化且无法在原任务继续时，才新建子任务，并在描述里写明「为什么不能在原任务上继续」。首次拆分大需求的规则和 PR 行数上限不变。

## 升级和排查

- autoteam 更新后：`npx skills update autoteam`（或 `git pull`）→ `autoteam init` 补上新增的文件 → `autoteam diff` 看已有文件的差异 → 用户同意后只覆盖没被改过的文件：`autoteam init --force <文件...>`；改过的（比如加了运行时的 gate.yml）手动合并 → 提交合并 → `autoteam multica --apply` 同步指令。
- 改了 `ops/agents/` 下的指令、registry 或 autopilot：合并后跑 `autoteam multica --apply`；`autoteam doctor` 能发现 Multica 里的指令和仓库不一致。
- 其他问题先跑 `autoteam doctor`，再查 autoteam 文档的 `docs/operations/troubleshooting.md`。

同步读取失败最多尝试 3 次；写操作不自动重试。失败时会以非零退出码结束，输出“同步不完整”，按所选部分列出已完成、失败或部分完成、未执行的清单；已写入的改动不回滚，修复后可重新运行。重复挂载同一个仓库视为已是最新。`--only statuses` 不读取 runtime。

CLI 和状态 API 的 curl 请求都受 `MULTICA_HTTP_TIMEOUT` 控制，默认 30 秒，支持正秒数或 Go duration（如 `45`、`45s`、`2m`、`1m30s`）；无效或非正值会在同步前报错。格式依据 [Multica CLI 官方说明](https://github.com/multica-ai/multica/blob/main/CLI_AND_DAEMON.md)。

人工 CODEOWNERS 路径的 PR：Implementer 提交后立即将任务设为 `blocked`、指派给 `AUTOTEAM_HUMAN` 并提及人及 Reviewer；Reviewer 批准后保持 `blocked`，等待 codeowner 批准。人批准并合并后回复 @Planner，由 Planner 转回 `shipping` 并验收；未命中人工路径的 PR 按原流程流转。
