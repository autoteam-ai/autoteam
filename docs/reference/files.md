---
title: 生成的文件
---

# 生成的文件

`autoteam init` 写进目标仓库的所有文件。“受保护”指受 CODEOWNERS 保护，改动必须由人批准。

| 文件 | 作用 | 谁会改 | 受保护 |
|---|---|---|---|
| `AGENTS.md`（受管块） | 四条全局规则：怎么跑检查、不谎报验证、PR 标题、规则文件 | 模板 | |
| `Makefile` | `check` / `dev` / `deploy`（只在不存在时创建） | 人 | ✅ |
| `.jscpd.json` | 重复代码阈值 3%、忽略目录 | 人 | ✅ |
| `.gitignore`（受管块） | 忽略 jscpd 报告目录和 `ops/agents/local/`（App 私钥、按量计费的 key 都在这里；跑 agent 的机器用 `AUTOTEAM_KEYS_DIR`，见[配置](config.md)） | 模板 | |
| `.github/CODEOWNERS`（受管块） | 规则文件的负责人 | 模板 | ✅ |
| `.github/pull_request_template.md` | PR 正文：任务编号、检查结果、范围外发现 | 人 | ✅ |
| `.github/workflows/gate.yml` | 必需检查 `check`：PR 行数、重复代码、`make check` | 人 | ✅ |
| `.github/workflows/deploy.yml` | 合并后 `make deploy`，结果通知 Planner | 人 | ✅ |
| `.github/workflows/rollback.yml` | 手动回滚到指定提交 | 人 | ✅ |
| `ops/agents/README.md` | 目录说明 | 模板 | ✅ |
| `ops/agents/autoteam.conf` | 配置（[说明](config.md#autoteamconf)） | 人 | ✅ |
| `ops/agents/registry.yaml` | 计费注册表和团队清单（[说明](config.md#registryyaml)） | 人 | ✅ |
| `ops/agents/planner.md` 等 4 个 | 角色指令，同步到 Multica | 人 | ✅ |
| `ops/agents/playbook.md` | 本项目的经验库，Planner 每次开工必读；由 Planner 提议、人批准 | 人 | ✅ |
| `ops/agents/planner-mcp.json` | Planner 的浏览器自动化（Playwright MCP，可选） | 人 | ✅ |
| `ops/agents/autopilots/*.md` | 10 个 autopilot 的触发配置和 runbook | 人 | ✅ |
| `ops/agents/scripts/gh-app-token.sh` | 用 App 私钥铸 token，给 agent 提供 GitHub 身份 | 模板 | ✅ |
| `ops/agents/scripts/loop-guard.sh` | 统计打回、验收不通过、换人次数，判断是否升级 | 模板 | ✅ |
| `ops/agents/scripts/merge-mode.sh` | 判断这个 PR 由谁放行、由谁合并（platform / staged / reviewer） | 模板 | ✅ |
| `ops/agents/scripts/health-metrics.sh` | 代码健康指标 | 模板 | ✅ |

“模板”表示一般不需要手改，升级 autoteam 时用 `autoteam diff` / `autoteam init --force` 更新；“人”表示装完后按项目情况修改。

autoteam 不会删除任何文件，也不会删除 GitHub 或 Multica 上的任何东西。卸载时手动删掉这些文件和受管块，在 Multica 里删掉对应的 agent 和 autopilot，在 GitHub 上删掉规则集 `autoteam` 和 secret `MULTICA_DEPLOY_HOOK`。
