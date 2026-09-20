# 第 0 步：准备仓库

`autoteam init` 生成的 Makefile 里，三个目标都是会直接报错的 `AUTOTEAM-TODO` 桩，逼你把它们改成真实命令。这一步决定了后面所有自动化的上限：`make check` 不够严，编排得再好，也只是更快地把不合格的代码送进主干。

## make check

一条命令跑完全部检查，本地和 CI 是同一条：gate.yml 只调 `make check`，Implementer 交付前也只跑它。

- 把现有 CI 里的 lint、类型检查、测试都串进来；
- 能用类型系统、lint、依赖检查表达的约束（比如“core 包不许 import react-dom”），做成检查放进来，而不是写进 AGENTS.md 指望模型记住；
- 失败就退出非 0，不要 `|| true`。

gate.yml 在 `make check` 之前还有两道检查：

| 检查 | 规则 | 调整 |
|---|---|---|
| pr-size | PR 改动不超过 400 行（参考 AI PR 的 75 分位 408 行）；lock 文件和规则文件（`.github/`、`ops/agents/`，由人批准）不计 | `ops/agents/autoteam.conf` 的 `AUTOTEAM_PR_MAX_LINES` |
| duplication | 重复代码占比不超过 3%；不查 Markdown 和规则文件 | `.jscpd.json` 的 `threshold` 和 `ignore`；老项目按现状定值，只降不升 |

## make dev

一条命令起环境，并且可以重复执行：已经起来了就跳过或重启，依赖、数据库、迁移都在里面做完。Implementer 每次开工都先跑它，再做一次端到端验证，确认项目不是坏的，而不是在坏的基础上继续加功能。项目有 docker compose 就优先用容器。

## make deploy

在 GitHub Actions 里部署当前提交：deploy.yml 在合并到默认分支后调它，rollback.yml 用旧提交调它。凭据从 secrets 传进 `env:`。先部署后验收，所以建议新功能放在功能开关后面，验收通过再全量打开。

各技术栈的例子见 skill 里的 [adapt-make.md](../../skills/autoteam/references/adapt-make.md)。

## AGENTS.md

`autoteam init` 只在 AGENTS.md 末尾追加四条规则（受管块）。其余要你自己写，原则：

- 只写从代码里看不出来、或者容易搞错的规则；
- 禁止项带原因：“不要 X，因为 Y，改做 Z”；
- 分层：根目录放全局规则，子包放各自的 AGENTS.md；
- 常驻上下文控制在模型有效上下文的 5% 以内。

详见 [write-agents-md.md](../../skills/autoteam/references/write-agents-md.md)。

## 检查

```bash
make check && make dev && make dev     # dev 连跑两次都要成功
autoteam doctor --skip-github --skip-multica
```
