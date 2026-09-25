---
title: 生成的文件
---

# 生成的文件

`autoteam init` 写进目标仓库的所有文件。“受保护”指受 CODEOWNERS 保护，改动必须由人批准。

```
你的仓库/
├─ AGENTS.md                        受管块
├─ Makefile
├─ .jscpd.json
├─ .gitignore                       受管块
├─ .github/
│  ├─ CODEOWNERS                    受管块
│  ├─ pull_request_template.md
│  └─ workflows/{gate,deploy,rollback}.yml
└─ .autoteam/                       全部由 autoteam 管理，整个目录受 CODEOWNERS 保护
   ├─ autoteam.conf   registry.yaml   playbook.md   README.md
   ├─ scripts/{gh-app-token,loop-guard,merge-mode,health-metrics}.sh
   ├─ .lock.json                    装机版本 + 每个文件的 sha256
   ├─ local/                        私钥、env（gitignore，不入库）
   └─ instructions/                 只有 autoteam eject 之后才存在
```

| 文件 | 作用 | 谁会改 | 受保护 |
|---|---|---|---|
| `AGENTS.md`（受管块） | 四条全局规则：怎么跑检查、不谎报验证、PR 标题、规则文件 | 模板 | |
| `Makefile` | `check` / `dev` / `deploy`（只在不存在时创建） | 人 | ✅ |
| `.jscpd.json` | 重复代码阈值 3%、忽略目录 | 人 | ✅ |
| `.gitignore`（受管块） | 忽略 jscpd 报告目录和 `.autoteam/local/`（App 私钥、按量计费的 key 都在这里；跑 agent 的机器用 `AUTOTEAM_KEYS_DIR`，见[配置](config.md)） | 模板 | |
| `.github/CODEOWNERS`（受管块） | 规则文件的负责人 | 模板 | ✅ |
| `.github/pull_request_template.md` | PR 正文：任务编号、检查结果、范围外发现 | 人 | ✅ |
| `.github/workflows/gate.yml` | 必需检查 `check`：PR 行数、重复代码、`make check` | 人 | ✅ |
| `.github/workflows/deploy.yml` | 合并后 `make deploy`，结果通知 Planner | 人 | ✅ |
| `.github/workflows/rollback.yml` | 手动回滚到指定提交 | 人 | ✅ |
| `.autoteam/README.md` | 目录说明 | 模板 | ✅ |
| `.autoteam/autoteam.conf` | 配置（[说明](config.md#autoteamconf)） | 人 | ✅ |
| `.autoteam/registry.yaml` | 计费注册表和团队清单（[说明](config.md#registryyaml)） | 人 | ✅ |
| `.autoteam/.lock.json` | 装机版本和每个文件的 sha256，`autoteam upgrade` 靠它判断哪些文件改过；要入库 | 工具 | ✅ |
| `.autoteam/playbook.md` | 本项目的经验库，Planner 每次开工必读；由 Planner 提议、人批准 | 人 | ✅ |
| `.autoteam/instructions/**` | 可选，`autoteam eject` 落盘的角色指令、autopilot、`planner-mcp.json`；有这份就优先用，没有则用 autoteam 包内的 | 人 | ✅ |
| `.autoteam/local/` | 本机私钥、按量计费的 key；受管块把它加进 `.gitignore`，不入库 | 人 | |
| `.autoteam/scripts/gh-app-token.sh` | 用 App 私钥铸 token，给 agent 提供 GitHub 身份 | 模板 | ✅ |
| `.autoteam/scripts/loop-guard.sh` | 统计打回、验收不通过、换人次数，判断是否升级 | 模板 | ✅ |
| `.autoteam/scripts/merge-mode.sh` | 判断这个 PR 由谁放行、由谁合并（platform / staged / reviewer） | 模板 | ✅ |
| `.autoteam/scripts/health-metrics.sh` | 代码健康指标 | 模板 | ✅ |

“模板”表示一般不需要手改，升级 autoteam 时用 `autoteam upgrade` 更新（改过的文件它不会动）；“人”表示装完后按项目情况修改。

## 不再落盘的文件

四个角色指令（planner / implementer / reviewer / auditor）、autopilot 的 runbook、`planner-mcp.json` **不写进你的仓库**：它们随 autoteam 包发布，`autoteam multica --apply` 和 `autoteam doctor` 直接读包内的版本，升级 autoteam 就升级了它们。规则由包版本固定，为什么这样是安全的见[安全边界](../concepts/guardrails.md#规则由包版本固定指令不落盘)。

要按本项目改某一份：`autoteam eject <名字>` 把它复制到 `.autoteam/instructions/`（受 CODEOWNERS 保护），此后读取优先用这一份，升级不会覆盖。用 `autoteam eject --diff <名字>` 对比包内的新版本。

## 从旧版布局迁移

旧版把这些文件放在 `ops/` 下的 `agents/` 子目录里，并且把指令也落盘。用 `autoteam migrate` 一次迁完（先加 `--dry-run` 看计划），见 [autoteam migrate](cli.md#autoteam-migrate)。

## 卸载

日常运行中 autoteam 只新建和更新，不删除任何文件（`autoteam migrate` 是一次性的例外：它删除与包内一致的旧指令文件），也不删除 GitHub 或 Multica 上的任何东西。卸载时手动删掉这些文件和受管块，在 Multica 里删掉对应的 agent 和 autopilot，在 GitHub 上删掉规则集 `autoteam` 和 secret `MULTICA_DEPLOY_HOOK`。
