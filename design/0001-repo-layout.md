# 0001 仓库结构重整：一个产品目录，一个安装目录

- 状态：已定稿，待实施
- 日期：2026-09-22
- 影响：仓库结构、npm 包边界、装进用户项目的路径（**breaking**，配 `autoteam migrate`）

## 1. 问题

现在同一个产品散在四处，而且其中两处是同一份字节。

| 东西 | 位置 |
|---|---|
| CLI 入口 | `bin/autoteam`（12 行 shim）→ `skills/autoteam/scripts/autoteam` |
| CLI 实现 | `skills/autoteam/scripts/lib/*.sh` |
| 装进项目的模板 | `skills/autoteam/assets/templates/ops/agents/**` |
| skill 本体 | `skills/autoteam/{SKILL.md,references/}` |
| npm 清单 | 根 `package.json` 的 `files: [bin/, skills/autoteam/, docs/]` |
| 自举副本 | `ops/agents/**`、`.github/**`（`make selfhost` + `diff --check` + `AUTOTEAM_DIFF_IGNORE` 维持同步） |
| 文档站工程 | 根的 `astro.config.mjs`、`src/`、`public/`、`scripts/*.mjs`、`dist/`、`.astro/` |

量化（2026-09-22 实测）：

- `ops/agents/` 下 23 个文件（不含 `local/`）里，**11 个与模板字节完全相同，9 个只差一行 `cron`**，只有 `autoteam.conf`、`registry.yaml`、`playbook.md` 3 个是真正的项目数据。
- 模板里 `{{AUTOTEAM_*}}` 占位符一共 15 处，全部在 `autoteam.conf`、CODEOWNERS 块、`deploy.yml`/`rollback.yml`、AGENTS 块、PR 模板，以及每个 autopilot 的那行 cron。**四个角色指令、playbook、四个脚本一个占位符都没有**——所谓「渲染」其实是 `cp`。
- 字符串 `ops/agents` 在仓库里出现 331 次。

结论：自举漂移不是"难免的代价"，而是**因为 `autoteam multica --apply` 从仓库的 `ops/agents/<role>.md` 读指令，仓库才不得不存一份副本**。

## 2. 调研：同类项目怎么做

1. **skill 不必嵌套在 `skills/` 下。** vercel-labs/skills 的发现列表第一条是「Root directory (if it contains SKILL.md)」，其后是 `skills/`、`.claude/skills/` 等 40 余个位置；有 `.claude-plugin/plugin.json` / `marketplace.json` 时，其中声明的路径「不受 depth-3 限制」，任意深度都能发现。Claude Code plugin 规范里 `skills` 字段是**叠加**语义（默认 `skills/` 永远扫描），并接受 `"."`。
2. **但选"所有渠道都认的默认路径"成本最低。** `skills/<name>/` 同时是 skills CLI 的首选发现路径、Claude Code plugin 的默认组件目录、monorepo 里 `packages/<name>/` 的等价物。因此**不是"为了 skill 安装被迫嵌套"，而是"发布包目录恰好叫 `skills/autoteam`"**。
3. **github/spec-kit**（最接近的同类）：CLI 在 `src/specify_cli/`、模板在 `templates/`、payload 脚本在 `scripts/`，三者平级；装进用户项目时全部收进单个 `.specify/`（issue #38 的理由：散在项目根目录「disruptive and confusing」）；**自己仓库里只留 `.specify/memory/constitution.md`，不 vendor 自己的渲染产物**。
4. **copier / cruft**：`.copier-answers.yml` 记模板版本+答案，`copier update` 三方合并，`--check` 查漂移。这是"装进项目的文件如何升级"的行业解法。
5. **husky / changesets / devcontainer**：工具名 dot 目录，内部再分"生成物"与"用户文件"。`ops/` 在多数项目里是基建目录（terraform / k8s / ansible），占用它会和用户已有约定撞车。

## 3. 核心判断：`ops/agents/` 混了三类东西

| 类别 | 现在 | 本质 | 去处 |
|---|---|---|---|
| 同步进 Multica 的**指令文本** | 4 个角色 md、`autopilots/*.md`、`planner-mcp.json` | 产品内容，人人一样；运行时 agent 读的是 Multica 里的副本，不读文件 | **不落盘**，留在包内 `instructions/` |
| **项目配置** | `autoteam.conf`、`registry.yaml`、`playbook.md`、`local/*.pem` | 真·用户数据 | `.autoteam/` |
| **运行时脚本** | `scripts/*.sh` | 每台机器的 clone 里要能直接跑 | `.autoteam/scripts/` |

拆开之后就不需要为"装到哪"发明名字了。

## 4. 决策

### D1　产品统一到 `skills/autoteam/`，它同时是 skill、npm 包、plugin 组件

```
autoteam/                        ← 仓库根：只放开发基础设施
├─ package.json                  private，workspaces: ["skills/autoteam", "site"]
├─ autoteam                      symlink → skills/autoteam/bin/autoteam（开发用，无逻辑）
├─ Makefile  AGENTS.md  README.md  CHANGELOG.md  LICENSE
├─ .claude-plugin/plugin.json    可选：顺带作为 Claude Code plugin 分发
├─ .autoteam/                    本仓库自己的配置（conf / registry / playbook / local）
├─ .github/                      本仓库 CI
├─ docs/                         文档内容源（人看）
├─ site/                         文档站工程（astro.config、src、public、static、build-docs.mjs）
├─ scripts/release.sh            仓库发布工具
├─ tests/
└─ skills/autoteam/           ★ 唯一的产品目录
   ├─ package.json               name / version / bin —— 版本号唯一来源
   ├─ SKILL.md
   ├─ references/
   ├─ bin/autoteam               真入口（不再是 shim）
   ├─ lib/*.sh
   ├─ instructions/              同步进 Multica 的指令（默认不落盘）
   │  ├─ roles/{planner,implementer,reviewer,auditor}.md
   │  ├─ autopilots/*.md
   │  └─ planner-mcp.json
   └─ templates/                 要写进用户 git 的文件
      ├─ root/                   AGENTS.block.md、Makefile、jscpd.json、gitignore.block、github/**
      └─ autoteam/               autoteam.conf、registry.yaml、playbook.md、README.md、scripts/*.sh
```

一次消掉：根 `bin/`、`assets/` 这一层、`package.json` 的 `files` 数组（包目录就是包）、`common.sh` 里的 `AUTOTEAM_VERSION`（改读包内 `package.json`，版本号从三处降到两处）。

`npx skills add autoteam-ai/autoteam --skill autoteam` 的行为不变：整个 284K 的包目录被复制进 `.claude/skills/autoteam/`，skill 自带工具、离线可用——这是要保留的性质。

### D2　装进用户项目的位置：`ops/agents/` → `.autoteam/`

```
.autoteam/
├─ autoteam.conf   registry.yaml   playbook.md   README.md
├─ scripts/        gh-app-token.sh / loop-guard.sh / merge-mode.sh / health-metrics.sh
├─ local/          私钥、env（gitignore）
├─ instructions/   仅在 autoteam eject 之后才存在
└─ .lock.json      安装版本 + 每个文件的 sha256
```

### D3　角色与 autopilot 指令默认不落盘，改为 eject 模型

指令按优先级解析：`.autoteam/instructions/<...>` → 包内 `instructions/<...>`。`autoteam multica --apply`、`doctor` 都走这个解析。

- 用户要改规则：`autoteam eject reviewer` 落到 `.autoteam/instructions/roles/reviewer.md`，受 CODEOWNERS 保护。
- autopilot 里唯一的 `{{AUTOTEAM_CRON_*}}` 移进 `autoteam.conf`，`instructions/` 从此零占位符。
- **本仓库自举：规则源文件就是 `skills/autoteam/instructions/`（本来就受 CODEOWNERS 保护），没有第二份。** `make selfhost` / `selfhost-check` 删除；剩下会漂的只有 3 个 workflow（已在 `AUTOTEAM_DIFF_IGNORE`）和三个受管块（块合并，不算漂移）。

**已知代价**：升级时角色指令的文本变化不再出现在 PR diff，只剩版本号变更。「改规则由人拍板」的不变量靠 CODEOWNERS 保护版本号仍然成立，但逐行评审弱化。缓解：`autoteam upgrade` 打印指令文本 diff，要求贴进 PR 描述；`autoteam doctor` 比对 Multica 里的文本与包内文本。

### D4　升级用 lock，取代 `AUTOTEAM_DIFF_IGNORE`

`.autoteam/.lock.json` 记装机版本与每个落盘文件的 sha256：

- 当前 sha == lock → 用户没动过 → 直接覆盖，不需要 `--force`
- 不一致 → 用户有意改过 → 三方对比（旧模板 / 新模板 / 现状），只在同一段两边都动时才要人工合并

`AUTOTEAM_DIFF_IGNORE` 删除——它现在的作用就是手工记录"哪些文件我故意改过"，lock 能自动推断。

## 5. 路径对照表

产品侧：

| 现在 | 之后 |
|---|---|
| `bin/autoteam` | 删除；根 symlink `autoteam` |
| `skills/autoteam/scripts/autoteam` | `skills/autoteam/bin/autoteam` |
| `skills/autoteam/scripts/lib/*.sh` | `skills/autoteam/lib/*.sh` |
| `.../assets/templates/{AGENTS.block.md,Makefile,jscpd.json,gitignore.block,github/**}` | `.../templates/root/` 下同名 |
| `.../assets/templates/ops/agents/{autoteam.conf,registry.yaml,playbook.md,README.md,scripts/**}` | `.../templates/autoteam/` 下同名 |
| `.../assets/templates/ops/agents/{planner,implementer,reviewer,auditor}.md` | `.../instructions/roles/*.md` |
| `.../assets/templates/ops/agents/autopilots/*.md` | `.../instructions/autopilots/*.md` |
| `.../assets/templates/ops/agents/planner-mcp.json` | `.../instructions/planner-mcp.json` |
| `astro.config.mjs`、`src/`、`public/`、`scripts/{build-docs,check-docs-links,docs-links}.mjs`、`tsconfig.json` | `site/` |
| `static/`（git 未跟踪的空目录，遗留） | 删除 |

用户项目侧：

| 现在 | 之后 |
|---|---|
| `ops/agents/{autoteam.conf,registry.yaml,playbook.md,README.md}` | `.autoteam/` 下同名 |
| `ops/agents/scripts/*.sh` | `.autoteam/scripts/*.sh` |
| `ops/agents/local/` | `.autoteam/local/` |
| `ops/agents/{角色}.md`、`autopilots/*.md`、`planner-mcp.json` | 不再落盘；eject 后进 `.autoteam/instructions/` |
| —— | 新增 `.autoteam/.lock.json` |

## 6. 代码改动清单

1. `lib/render.sh` 的 `autoteam_manifest`：目标路径前缀改用常量 `AUTOTEAM_DIR=.autoteam`；全仓库硬编码的 `ops/agents/` 一律走常量。
2. 新增 `instructions_path <kind> <name>`（eject 优先，包内兜底），`multica.sh`、`doctor.sh` 改用。
3. 新增 `cmd_eject`、`cmd_upgrade`、`cmd_migrate`。
4. `init` 写 `.lock.json`；`diff` / `upgrade` 依据 lock 判断"用户改过"。
5. `common.sh` 的 `AUTOTEAM_VERSION` 改从包内 `package.json` 提取（用 sed，不依赖 jq）。
6. `Makefile`：删 `selfhost` / `selfhost-check`，更新 `SCRIPTS` 列表。
7. `templates/root/github/workflows/gate.yml`：`conf=.autoteam/autoteam.conf`，`AUTOTEAM_PR_SIZE_EXCLUDE` 默认值改 `.autoteam/**`。
8. 根 `package.json` workspace 化；新建 `skills/autoteam/package.json`；`scripts/release.sh` 改 `npm publish -w autoteam`，去掉 `common.sh` 版本核对，保留 CHANGELOG 核对，更新冒烟路径。
9. CI 加一条守卫：全仓库不得再出现 `ops/agents`（文档历史章节除外）。
10. `tests/`：路径更新 + 新增 eject / upgrade / migrate 用例。

## 7. 实施拆分

`gate.yml` 用 `git diff --numstat` 统计行数，纯 `git mv` 算 0 行，且 `**/*.md` 与规则文件不计入预算，所以可以拆得很干净。每个 PR 都以 `make check` 通过为准。

| PR | 内容 | 计入行数 |
|---|---|---|
| 1 | 纯搬迁：`assets/templates`→`templates`、`scripts/lib`→`lib`、拆出 `instructions/`、文档站进 `site/`、根 `bin/` 换 symlink | ≈0 |
| 2 | 路径收敛：manifest 改造、`ops/agents`→`.autoteam`、workspace 化、版本号单源 | 中 |
| 3 | 指令解析 + `eject`，删自举副本与 `make selfhost` | 中 |
| 4 | `.lock.json` + `upgrade`，删 `AUTOTEAM_DIFF_IGNORE` | 中 |
| 5 | `migrate` + docs / README / AGENTS.md / SKILL.md 重写 | md 不计入 |

## 8. 兼容与迁移

- `autoteam doctor` 发现 `ops/agents/` 存在时提示 `autoteam migrate`。
- `autoteam migrate`：`git mv ops/agents .autoteam`；比对不再落盘的指令文件，**用户改过的保留为 eject**，与模板一致的删除；更新 `.gitignore` / CODEOWNERS / AGENTS 受管块里的路径；写 `.lock.json`。用户自己写在 AGENTS.md 或 workflow 里的 `ops/agents` 字样由 migrate 列出，人工处理。
- v0.1 实验期、用户量小，一次 breaking + migrate 命令可以接受；CHANGELOG 写清楚。

## 9. 风险

| 风险 | 缓解 |
|---|---|
| 指令不落盘 → 升级时规则变化不进 PR diff | `autoteam upgrade` 打印文本 diff 并要求贴进 PR；`doctor` 比对 Multica 与包内文本 |
| `.autoteam/` 是隐藏目录，不易发现 | README、`init` 输出、`doctor` 明确列出路径 |
| 331 处路径引用漏改 | CI grep 守卫 + `make deploy` 的干净仓库冒烟 |
| 老用户升级踩空 | `doctor` 提示 + `migrate` 命令 + CHANGELOG |

## 10. 参考

- vercel-labs/skills（发现机制与 plugin manifest）：<https://github.com/vercel-labs/skills>
- Claude Code plugins reference（`skills` 字段的叠加语义、`"."`）：<https://code.claude.com/docs/en/plugins-reference>
- github/spec-kit issue #38（收进 `.specify/` 的理由）：<https://github.com/github/spec-kit/issues/38>
- copier 的更新机制：<https://copier.readthedocs.io/en/stable/updating/>
