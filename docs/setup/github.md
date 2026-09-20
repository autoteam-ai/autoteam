---
title: 第 1–3 步：GitHub
---

# 第 1–3 步：GitHub

`autoteam github` 负责能用 API 完成的部分；账号和 token 需要你自己做。

```bash
autoteam github                    # 预览：识别保护等级，列出要做的改动
autoteam github --apply            # 执行
```

## 三个 GitHub App

GitHub 不允许 PR 作者批准自己的 PR。只要 Implementer 和 Reviewer 是**两个不同的 GitHub 身份**，"写代码的不能评审自己"就由平台保证，agent 绕不过去。

身份用 GitHub App，不用机器账号：不用注册邮箱和两步验证、不占席位、权限按 App 定义而不是靠选 token 范围。

**Reviewer App 必须给 Contents 读写。** 这一条是真机验证出来的：GitHub 只把"有仓库写权限的身份"提交的批准计入必需审批数，只给 Pull requests 写权限的 App，批准会被记录成 APPROVED 但**不算数**，PR 一直停在 `REVIEW_REQUIRED`。所以"Reviewer 不能推代码"只能靠指令约束，和机器账号方案一样。

| App | 给谁用 | 权限（都只装本仓库） |
|---|---|---|
| `<前缀>-impl` | 所有 Implementer | Contents 读写、Pull requests 读写 |
| `<前缀>-review` | 所有 Reviewer | Pull requests 读写、Contents 读写（**不能省**，见下） |
| `<前缀>-planner` | Planner、Auditor | Actions 读写、Contents 只读、Pull requests 只读 |

### 建 App

App 不能用 API 创建和安装，这一步必须由人做（`autoteam github` 只核对，不会代建）。三个 App 各做一遍：

1. 组织的 Settings → Developer settings → GitHub Apps → **New GitHub App**（个人仓库就在个人 Settings 下）。
2. 名字按上表；Homepage URL 随便填一个（比如仓库地址）；**取消勾选 Webhook 的 Active**——这套方案不需要 webhook 服务，App 只当身份用。
3. Repository permissions 按上表勾。**Where can this GitHub App be installed** 选 Only on this account。
4. 建好后记下 **App ID**，点 Generate a private key 下载 `.pem`。
5. 左侧 Install App → 装到本仓库，Repository access 选 **Only select repositories**，只选这一个仓库。

### 配置

App ID 写进 `ops/agents/autoteam.conf`：

```
AUTOTEAM_IMPLEMENTER_APP_ID=1234567
AUTOTEAM_REVIEWER_APP_ID=1234568
AUTOTEAM_PLANNER_APP_ID=1234569
```

私钥按角色放到**各自那台机器**的仓库里，文件名固定：

```
ops/agents/local/implementer.pem
ops/agents/local/reviewer.pem
ops/agents/local/planner.pem
```

`ops/agents/local/` 已经在 `.gitignore` 里，不会被提交。权限设 `chmod 600`。

### agent 怎么用

`ops/agents/scripts/gh-app-token.sh` 负责用私钥签 JWT、换 1 小时有效的 installation token，并缓存到快过期才重铸。角色指令里已经写好了，不用你操心，但你要知道它怎么工作：

```bash
# 任何 gh 命令，身份跟着命令走
ops/agents/scripts/gh-app-token.sh --run implementer gh pr create --title "..."

# 每次 clone / checkout 之后配一次：提交身份 + git push 的凭据
ops/agents/scripts/gh-app-token.sh --setup-git implementer
```

**不能用 `export GH_TOKEN=...`**：agent 每次工具调用都是新 shell，导出的变量活不到下一条命令。

`--setup-git` 会先用空值清掉机器上继承来的凭据助手，再配上 App 的。这一步不能省：机器上如果登录过 `gh`，系统钥匙串会抢先应答，agent 就会**以你本人的身份推代码**。

### 代价

私钥是长期凭据，比"只授权本仓库、带过期时间"的 fine-grained token 权限更宽、活得更久。所以：App 只装这一个仓库、权限按上表给到最小、私钥只放需要它的那台机器、不同角色尽量不同机器（至少不同系统用户或容器）。私钥泄露了就到 App 设置里删掉那把 key 再生成一把，已经铸出去的 token 最多 1 小时后失效。

人工账号仍然要留一个：**CODEOWNERS 不能写 App**，所以规则文件的 Code Owner 是你本人，规则文件的改动必须你批准。这正是研究文档要的那条——规则文件只能由人批准。

还没建 App 时，用单身份试用模式：`autoteam github --apply --trial`，见[单身份试用模式](../concepts/guardrails.md#单账号试用模式)。

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
