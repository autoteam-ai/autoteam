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
| `<前缀>-impl` | 所有 Implementer | Contents 读写、Pull requests 读写、Workflows 读写 |
| `<前缀>-review` | 所有 Reviewer | Pull requests 读写、Contents 读写（**不能省**，见下） |
| `<前缀>-planner` | Planner、Auditor | Actions 读写、Contents 只读、Pull requests 只读 |

`Workflows 读写` 不能省：没有它，Implementer 推含 `.github/workflows/` 改动的提交会被 GitHub 直接拒，连 PR 都提不了。**闸门是「人批准」不是「agent 不能碰」**——工作流也是项目的一部分，agent 得能提议改它，拦住它的是 CODEOWNERS 要求的人工批准。

### 建 App

**推荐：`autoteam github --create-apps`**（用 GitHub 的 App Manifest 流程，一次建好三个，权限已按上表预填）。默认只预览，`--apply` 才创建：

```bash
autoteam github --create-apps            # 预览：会建哪几个、权限是什么、私钥写到哪
autoteam github --create-apps --apply    # 创建
```

对每个角色：

1. autoteam 生成一个本地 HTML 页（临时目录里，路径会打印出来），在**有浏览器的机器**上打开它（远端机器先把这个文件拷过去；命令会一直等你粘贴，文件不会提前被删）。页面自动跳到 GitHub 的创建页，名称、权限都已填好（默认名字是 `<仓库名>-implementer`、`-reviewer`、`-planner`，可用 `--app-prefix` 改前缀；名字被占用时在页面上改）。
2. 点 **Create GitHub App**。GitHub 会跳到 `http://localhost:3000/autoteam-callback?code=…`——没有程序在监听这个端口，浏览器显示"无法连接"是正常的。
3. 把地址栏里的**完整 URL** 粘回终端。autoteam 只接受以回调地址开头、带 `code` 和本轮本角色 `state` 的完整 URL（裸 code、缺 state、粘错角色的 URL 都会被拒绝）；通过后用里面的 `code` 向 GitHub 换回 App ID 和私钥：私钥写进 `AUTOTEAM_KEYS_DIR/<角色>.pem`（权限 600，目录不存在时以 700 创建），App ID 写进 `autoteam.conf` 对应的键。私钥、client secret、webhook secret 都不会打印。

之后**装到仓库**：命令会打印每个 App 的安装地址，Repository access 选 **Only select repositories**，只选本仓库（autoteam 只创建、不安装）。装完运行 `autoteam github` 核对安装状态和权限。

不做的事：`AUTOTEAM_KEYS_DIR` 里已有该角色私钥就跳过这个角色，绝不覆盖；`autoteam.conf` 已有 App ID 但没有私钥的角色也不重复建，到该 App 的设置页 Generate a private key 即可。换回之后写私钥或写 `autoteam.conf` 失败时，命令会明确报错、退出码非 0，并打印恢复办法（App 已建好，到设置页重新生成私钥、手工补一行 App ID）。中途出错或跳过某个角色，重新运行 `--apply` 会从没做完的角色接着来。

回调用"粘贴 URL"而不是本地监听，是为了在 macOS 自带的 bash 3.2 和没有浏览器的远端机器上都能用，不占端口。

**备选：手工创建。** 三个 App 各做一遍：

1. 组织的 Settings → Developer settings → GitHub Apps → **New GitHub App**（个人仓库就在个人 Settings 下）。
2. 名字按上表；Homepage URL 随便填；**取消勾选 Webhook 的 Active**；Repository permissions 按上表勾；**Where can this GitHub App be installed** 选 Only on this account。
3. 建好后记下 **App ID**，点 Generate a private key 下载 `.pem`；Install App → 装到本仓库，只选这一个仓库。
4. App ID 和私钥按下面「配置」放好。

如果有意让同一组 App 服务组织里的多个仓库，可以保留 **All repositories**。先在 GitHub 的 Install App 页面逐个核对三个 App 的安装范围和权限，确认私钥泄露时可能触及范围内所有仓库；再在每个项目的 `.autoteam/autoteam.conf` 设置 `AUTOTEAM_APP_ALL_REPOS_ACK=on`。`autoteam github` 此后只报确认信息，不再重复警告。未确认时会提醒缩小安装范围。

### 配置

App ID 写进 `.autoteam/autoteam.conf`：

```
AUTOTEAM_IMPLEMENTER_APP_ID=1234567
AUTOTEAM_REVIEWER_APP_ID=1234568
AUTOTEAM_PLANNER_APP_ID=1234569
```

私钥按角色放到**各自那台机器**上。放哪里有两个选择：

| 位置 | 适合 | 说明 |
|---|---|---|
| `AUTOTEAM_KEYS_DIR`（默认 `~/.autoteam`） | **跑 agent 的机器** | 机器级的固定位置，跟仓库无关 |
| 仓库里的 `.autoteam/local/` | 你自己的机器 | 已在 `.gitignore` 里，不会被提交 |

文件名只要带上角色名就行（`implementer.pem`，或 GitHub 下载时的 `autoteam-implementer.2026-01-01.private-key.pem`），权限设 `chmod 600`。两个位置都有时仓库里的优先；也可以用 `AUTOTEAM_<角色大写>_APP_KEY` 直接指一个路径。

> **给 agent 用的私钥一定要放 `AUTOTEAM_KEYS_DIR`，不要只放仓库里。** agent 每接一个任务都可能重新 checkout 一份仓库，放在 `.autoteam/local/` 的私钥不会跟过去，下一个任务就会卡在「找不到私钥」——真机上两个 Implementer 同时中过这一枪。`autoteam doctor` 会在跑 agent 的那台机器上检查这一点：registry 里 runtime 在本机的角色缺私钥就报 ❌，并给出该放的位置。Planner 派发前也看这项，没通过就不派。

### agent 怎么用

`.autoteam/scripts/gh-app-token.sh` 负责用私钥签 JWT、换 1 小时有效的 installation token，并缓存到快过期才重铸。角色指令里已经写好了，不用你操心，但你要知道它怎么工作：

```bash
# 任何 gh 命令，身份跟着命令走
.autoteam/scripts/gh-app-token.sh --run implementer gh pr create --title "..."

# 每次 clone / checkout 之后配一次：提交身份 + git push 的凭据
.autoteam/scripts/gh-app-token.sh --setup-git implementer
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
/.autoteam/     @你
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
