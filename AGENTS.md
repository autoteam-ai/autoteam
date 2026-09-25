# AGENTS.md

本仓库是 autoteam：把自管理 agent 团队流程装进用户项目的工具（`autoteam`）、Agent Skill 和中文文档。

## 目录

- `skills/autoteam/` 是唯一的实现，必须自包含：`npx skills add` 只会拷贝这个目录。
  - `bin/autoteam` 入口，`lib/*.sh` 各命令的实现；旧路径的字面量只允许出现在 `lib/migrate.sh`，其他地方（含测试、文档）不写；
  - `templates/` 装进用户项目的文件（`root/` 装进仓库根、`autoteam/` 装进 `.autoteam/`），占位符写 `{{AUTOTEAM_名字}}`；
  - `instructions/` 是同步进 Multica 的角色和 autopilot 指令文本（不落盘到用户仓库，`autoteam eject` 才复制出去）；
  - `SKILL.md`、`references/` 是给编码 agent 看的。
- 根 `autoteam` 是指向 `skills/autoteam/bin/autoteam` 的 symlink，只给本仓库开发用，不要在这里加逻辑。
- npm 包就是 `skills/autoteam/` 这个目录（包名 `autoteam`），清单是 `skills/autoteam/package.json`，没有 `files` 白名单，目录里有什么就发什么；根 `package.json` 是 `private` 的 workspace 根（`skills/autoteam`、`site`）。`scripts/release.sh` 是发布脚本。
- `docs/` 是给人看的文档，也是文档站的内容源；`site/` 是文档站工程（Astro），`site/scripts/build-docs.mjs` 把每个 `v*` tag 和 main 各构建一份，**默认进开发版（`next`，也就是 main）**——项目还在活跃开发，发布版本往往落后于正在改的规则，默认落在旧版本会让人按过期说明操作。稳定之后把 `AUTOTEAM_DOCS_DEFAULT` 设成 `latest`。
- `design/` 是给团队看的设计记录（不进文档站）。
- `tests/` 是测试（`stubs/` 下是 gh、multica、curl 的桩）。

## 约定

- 脚本要兼容 macOS 自带的 bash 3.2：不用关联数组、`mapfile`、`${var,,}`；空数组用 `${arr[@]+"${arr[@]}"}` 展开。
- `$(函数)` 里调用会 `die` 的函数时，`|| true` 要写在命令替换外面：`x=$(f) || true`。写成 `$(f || true)` 挡不住 `exit`，会在 `set -e` 下把整个脚本带退。
- 模板渲染不要用 `${var//pat/rep}`：bash 5.2 起替换串里的 `&` 有特殊含义。
- autoteam 只新建和更新，不删除任何文件或远端资源（唯一例外是一次性的 `autoteam migrate`：删除与包内一致的旧指令文件）；改动 GitHub、Multica 的命令默认只预览，`--apply` 才执行。
- 不打印 token 和 webhook 地址。
- 改了模板、命令行为或配置项，同一个 PR 里更新 `docs/` 和 `skills/autoteam/SKILL.md` 里对应的说明。

## 检查

```bash
make check   # shellcheck + actionlint + tests/run.sh；本机没装 linter 时用 docker 镜像
bash tests/run.sh multica   # 只跑名字里带 multica 的测试
```

不要声称检查通过，除非你真的跑了。

## 上线和发版

两件事，分开：

```bash
make deploy    # 上线：打包 + 装进干净仓库真跑一遍，产物在 build/pkg/。合并后 CI 自动跑
make publish   # 发版：发到 npm，由人执行；DRY_RUN=1 只演练
```

`make deploy` 是本仓库的"上线"——Planner 下载 CI 传上去的那个 tarball 做线上验收，验的是真实可安装的制品，不是代码。它不碰网络凭据，可以随便跑。

`make publish` 是对外的、撤不回的动作（npm 72 小时后连 unpublish 都不行），**不接进任何自动流程**：改版本号（只改 `skills/autoteam/package.json`，CLI 的 `autoteam version` 从它读；CHANGELOG 定版，`scripts/release.sh` 会核对）、合并之后，由人执行。`skills/autoteam/package.json` 受 CODEOWNERS 保护，所以"什么时候发版"这个决定始终在人手里。

## 自举

本仓库自己也用 autoteam 管理，但**不再有渲染出来的副本**：角色指令、autopilot、`planner-mcp.json` 默认不落盘，`autoteam multica` 直接读包内 `skills/autoteam/instructions/**`。

| 路径 | 是什么 | 谁能改 |
|---|---|---|
| `skills/autoteam/templates/**`、`skills/autoteam/instructions/**` | 产品源码，也是本仓库自己的规则源文件 | agent 可以改，但受 CODEOWNERS 保护，**必须由人批准** |
| `.autoteam/instructions/**` | `autoteam eject` 落盘的覆盖文件（落盘 = 有意改过），读取时优先于包内那份 | 同上；升级不会覆盖 |
| `.autoteam/**`、`.github/**` 其余部分 | 本仓库自己的配置、脚本、工作流 | 受 CODEOWNERS 保护，必须由人批准 |

- 改规则就改 `skills/autoteam/instructions/**` 或 `skills/autoteam/templates/**`，同一个 PR 里不需要再同步副本。因此这类 PR 必然带上受保护路径，必须人批准——**改规则由人拍板**，这是设计。
- 三个工作流（gate / deploy / rollback）和 `playbook.md` 按本仓库需要改过，`.autoteam/.lock.json` 据此把它们记为“本地已修改”，`autoteam upgrade` 不覆盖、`autoteam diff --check` 不算漂移。改了模板后跑 `bash ./autoteam upgrade` 同步没改过的文件、连同 `.lock.json` 一起提交；改过的那几份手工看一眼要不要跟。
- 一律用仓库里的 `bash ./autoteam`（或 `bash skills/autoteam/bin/autoteam`），不要用全局装的 skill——自举的前提是永远跑正在开发的这一版。
- `site/dist/` 是文档站的构建输出（会发布到 autoteam-ai.github.io/autoteam/），npm 包放 `build/pkg/`，别放错。

<!-- >>> autoteam >>> -->
## AI 团队工作流

本仓库由 Planner / Implementer / Reviewer / Auditor 四个 agent 协作开发，角色指令和配置在 `.autoteam/`。

- 全部检查只用 `make check`（CI 也只调它）；起环境用 `make dev`，可以重复执行。
- 不要声称验证通过，除非你真的跑了；因故没跑，就写明没跑什么、为什么。
- PR 标题以任务编号开头（如 `MUL-123 按日期导出订单`），不写 `Closes` / `Fixes` 等关闭关键字：任务要等线上验收通过才算完成。
- `.github/`、`.autoteam/`、`Makefile`、`.jscpd.json` 是约束 agent 的规则文件，受 CODEOWNERS 保护，改动必须由人批准才能合并。Implementer 只在任务明确要求时才改这些文件并提 PR；没有任务要求就不要顺手改，发现问题写进评论的“范围外发现”。
<!-- <<< autoteam <<< -->
