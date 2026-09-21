# AGENTS.md

本仓库是 autoteam：把自管理 agent 团队流程装进用户项目的工具（`autoteam`）、Agent Skill 和中文文档。

## 目录

- `skills/autoteam/` 是唯一的实现，必须自包含：`npx skills add` 只会拷贝这个目录。
  - `scripts/autoteam` 入口，`scripts/lib/*.sh` 各命令的实现；
  - `assets/templates/` 装进用户项目的文件，占位符写 `{{AUTOTEAM_名字}}`；
  - `SKILL.md`、`references/` 是给编码 agent 看的。
- `bin/autoteam` 只是薄包装，不要在这里加逻辑。
- `package.json` 和 `scripts/release.sh` 是 npm 包（包名 `autoteam`）的清单和发布脚本；`files` 只放 `bin/`、`skills/autoteam/`、`docs/`，新增顶层目录要同步它。
- `docs/` 是给人看的文档，也是文档站的内容源；`scripts/build-docs.mjs` 把每个 `v*` tag 和 main 各构建一份，**默认进开发版（`next`，也就是 main）**——项目还在活跃开发，发布版本往往落后于正在改的规则，默认落在旧版本会让人按过期说明操作。稳定之后把 `AUTOTEAM_DOCS_DEFAULT` 设成 `latest`。
- `tests/` 是测试（`stubs/` 下是 gh、multica、curl 的桩）。

## 约定

- 脚本要兼容 macOS 自带的 bash 3.2：不用关联数组、`mapfile`、`${var,,}`；空数组用 `${arr[@]+"${arr[@]}"}` 展开。
- `$(函数)` 里调用会 `die` 的函数时，`|| true` 要写在命令替换外面：`x=$(f) || true`。写成 `$(f || true)` 挡不住 `exit`，会在 `set -e` 下把整个脚本带退。
- 模板渲染不要用 `${var//pat/rep}`：bash 5.2 起替换串里的 `&` 有特殊含义。
- autoteam 只新建和更新，不删除任何文件或远端资源；改动 GitHub、Multica 的命令默认只预览，`--apply` 才执行。
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

`make publish` 是对外的、撤不回的动作（npm 72 小时后连 unpublish 都不行），**不接进任何自动流程**：改版本号（`package.json`、`common.sh` 的 `AUTOTEAM_VERSION`、CHANGELOG 三处一起，`scripts/release.sh` 会核对）、CHANGELOG 定版、合并之后，由人执行。`package.json` 受 CODEOWNERS 保护，所以"什么时候发版"这个决定始终在人手里。

## 自举

本仓库自己也用 autoteam 管理，所以同一份东西在仓库里有两份，别搞混：

| 路径 | 是什么 | 谁能改 |
|---|---|---|
| `skills/autoteam/assets/templates/**` | 产品源码，发给所有用户的规则文件 | agent 可以改，但受 CODEOWNERS 保护，**必须由人批准** |
| `ops/agents/**`、`.github/**` | 本仓库自己这份，由模板**渲染**出来 | 只能由 `make selfhost` 生成，**禁止手写** |

- 改了模板就要在**同一个 PR 里**跑 `make selfhost` 把副本同步上。`make check` 里的 `selfhost-check`（`autoteam diff --check`）会挡住不同步的 PR。
- 因此每个改模板的 PR 都会带上受保护路径，必然要人批准。这是设计：**改规则由人拍板**，不是麻烦。
- 三个工作流（gate / deploy / rollback）按本仓库需要改过，登记在 `ops/agents/autoteam.conf` 的 `AUTOTEAM_DIFF_IGNORE` 里，`make selfhost` 不会覆盖它们。改模板里的工作流时，记得手工看一眼本仓库这份要不要跟。
- 一律用仓库里的 `bash bin/autoteam`，不要用全局装的 skill——自举的前提是永远跑正在开发的这一版。
- `dist/` 是文档站的构建输出（会发布到 autoteam-ai.github.io/autoteam/），npm 包放 `build/pkg/`，别放错。

<!-- >>> autoteam >>> -->
## AI 团队工作流

本仓库由 Planner / Implementer / Reviewer / Auditor 四个 agent 协作开发，角色指令和配置在 `ops/agents/`。

- 全部检查只用 `make check`（CI 也只调它）；起环境用 `make dev`，可以重复执行。
- 不要声称验证通过，除非你真的跑了；因故没跑，就写明没跑什么、为什么。
- PR 标题以任务编号开头（如 `MUL-123 按日期导出订单`），不写 `Closes` / `Fixes` 等关闭关键字：任务要等线上验收通过才算完成。
- `.github/`、`ops/agents/`、`Makefile`、`.jscpd.json` 是约束 agent 的规则文件，受 CODEOWNERS 保护，改动必须由人批准才能合并。Implementer 只在任务明确要求时才改这些文件并提 PR；没有任务要求就不要顺手改，发现问题写进评论的“范围外发现”。
<!-- <<< autoteam <<< -->
