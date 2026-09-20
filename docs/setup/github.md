# 第 1–3 步：GitHub

`autoteam github` 负责能用 API 完成的部分；账号和 token 需要你自己做。

```bash
autoteam github                    # 预览：识别保护等级，列出要做的改动
autoteam github --apply            # 执行
```

## 机器账号和 token

GitHub 不允许 PR 作者批准自己的 PR，所以 Implementer 和 Reviewer 用不同账号，就能在平台层面保证写代码的不能评审自己。

| 账号 | 机器 | 给谁用 | 仓库权限 |
|---|---|---|---|
| `acme-impl-bot` | A | 所有 Implementer | Write：推分支、开 PR、开自动合并 |
| `acme-review-bot` | B | 所有 Reviewer | Write：提交评审 |
| `acme-planner-bot` | C | Planner、Auditor | Write，但 token 只开读取和 Actions：查 PR、触发回滚 |

1. 注册账号（每个一个邮箱，开两步验证），写进 `ops/agents/autoteam.conf`：

   ```
   AUTOTEAM_IMPL_BOT=acme-impl-bot
   AUTOTEAM_REVIEW_BOT=acme-review-bot
   AUTOTEAM_PLANNER_BOT=acme-planner-bot
   ```

2. `autoteam github --apply` 会邀请它们为协作者（permission=push），用各自账号登录 GitHub 接受邀请。仓库在组织下时，也可以把它们加成组织成员（基础权限 No permission）再单独给本仓库 Write。
3. 生成 token，只授权本仓库、设过期时间：

   | 账号 | 组织仓库：fine-grained token | 个人仓库：classic token |
   |---|---|---|
   | impl | Contents 读写、Pull requests 读写 | `repo`；不勾 `workflow`，它就推不了工作流文件 |
   | review | Pull requests 读写、Contents 只读 | `repo` |
   | planner | Actions 读写、Contents 只读、Pull requests 只读 | `repo` |

   个人账号的仓库，协作者不能用 fine-grained token（resource owner 只能选自己或所在的组织），只能用 classic token，没法按仓库细分权限。想按最小权限给，就把仓库放到组织下，机器账号作为组织成员。

4. 在各自机器上登录，并设好 git 身份：

   ```bash
   gh auth login --with-token < token.txt
   git config --global user.name acme-impl-bot
   git config --global user.email <账号邮箱>
   ```

不同账号跑在不同机器上（至少是不同系统用户或容器），避免互相读到凭据。

还没准备账号时，用单账号试用模式：`autoteam github --apply --trial`，见[单账号试用模式](../concepts/guardrails.md#单账号试用模式)。

## 合并规则

`autoteam github --apply` 在默认分支上建规则集 `autoteam`，和研究文档第 2 步一一对应：

| 规则 | 设置 |
|---|---|
| Bypass list | 留空，管理员也不能豁免 |
| Restrict deletions、Block force pushes | 打开 |
| Require a pull request before merging | 1 个审批；新提交作废旧审批；规则文件要 Code Owner 审批；最后一次推送要别人批准；合并方式只留 squash |
| Require status checks to pass | `check`，只认 GitHub Actions 上报的结果 |
| Require merge queue | 只有组织仓库（full 等级）才加 |

仓库设置：打开 Allow auto-merge、Automatically delete head branches，只保留 squash 合并。重复运行是幂等的：规则集已经符合就不再写，不符合就更新。

GitHub Free 的私有仓库调这些接口会返回“Upgrade to GitHub Pro or make this repository public”，autoteam 会跳过并说明哪些闸门没有生效，见[保护等级](../concepts/guardrails.md#保护等级)。

规则文件由 CODEOWNERS 保护（`autoteam init` 追加的受管块）：

```text
/.github/        @你
/ops/agents/     @你
/Makefile        @你
/.jscpd.json     @你
```

注意：你自己开 PR 改这些文件时，没有别的 Code Owner 能批准。做法是让 Implementer 来改（你作为 Code Owner 批准），或者临时把规则集改成 disabled，改完再恢复（操作会记在审计日志里）。

## 自动部署和回滚

- `deploy.yml`：推到默认分支后运行 `make deploy`，无论成败都把 `{kind, sha, result, repo, run_url}` POST 给 Multica 的“部署结果” autopilot（`MULTICA_DEPLOY_HOOK`，带 Idempotency-Key 防重复）。只在部署工作流里通知，避免每次 PR 检查都唤醒 Planner。
- `rollback.yml`：手动触发，Planner 用 `gh workflow run rollback.yml -f sha=<上次验收通过的提交>` 回滚。
- `MULTICA_DEPLOY_HOOK` 由 `autoteam multica --apply` 写入，没设置时通知步骤会跳过并给出警告。
- `AUTOTEAM_DEPLOY_ENVIRONMENT`（默认 `production`）非空时，部署 job 使用这个 environment，`autoteam github --apply` 会创建它；GitHub Free 的私有仓库不支持 environment，`autoteam init` 识别到时会留空。

## 检查

```bash
autoteam doctor --skip-multica
```
