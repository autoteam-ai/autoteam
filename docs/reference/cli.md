# autoteam 命令

```
autoteam [-C <目录>] <命令> [选项]
```

`-C` 指定在哪个仓库里执行（默认当前目录）。每个命令都有 `-h`。依赖 bash 3.2+、git、jq；`github` 需要 gh，`multica` 需要 multica CLI 和 curl。

## autoteam init

生成工作流文件。

| 选项 | 说明 |
|---|---|
| `--repo <owner/name>` | GitHub 仓库，默认从 git remote 识别 |
| `--owner <用户名>` | 规则文件的人类负责人，默认当前 gh 登录用户 |
| `--issue-prefix <前缀>` | 任务编号前缀，默认从 `--workspace` 读取，否则 MUL |
| `--workspace <slug>` | Multica 工作区 |
| `--human <成员名>` | 负责批准和接收升级的 Multica 成员 |
| `--timezone <时区>` | autopilot 时区，默认 Asia/Shanghai |
| `--force` | 覆盖与模板不同的文件、替换受管块（autoteam.conf、registry.yaml 永远不覆盖） |
| `[文件...]` | 只处理这些文件，例如 `autoteam init --force ops/agents/reviewer.md` |
| `--dry-run` | 只列出会做什么 |

写文件的规则：

| 文件 | 已存在时 |
|---|---|
| AGENTS.md、.github/CODEOWNERS、.gitignore | 追加受管块，只追加一次；块内容和模板不同时跳过（`--force` 替换） |
| Makefile | 不动，只检查有没有 check / dev / deploy 目标 |
| autoteam.conf、registry.yaml | 保留（用户数据） |
| 其他 | 相同就跳过，不同就提示用 `autoteam diff` 看差异（`--force` 覆盖） |

识别顺序：命令行参数 > 已有的 autoteam.conf > 自动识别 > 默认值。识别到 GitHub Free 的私有仓库时，`AUTOTEAM_DEPLOY_ENVIRONMENT` 留空，deploy.yml 不声明 environment。

## autoteam github

配置仓库设置、规则集、environment、机器账号。默认只预览。

| 选项 | 说明 |
|---|---|
| `--apply` | 执行 |
| `--trial` | 单账号试用模式：规则集不要求审批 |
| `--bots impl=<用户>,review=<用户>,planner=<用户>` | 邀请机器账号（也可以写在 autoteam.conf） |
| `--repo <owner/name>` | 覆盖 autoteam.conf 里的仓库 |

保护等级的判断和每条规则见[第 1–3 步 GitHub](../setup/github.md)。重复运行是幂等的。

## autoteam multica

配置自定义状态、agent、项目、autopilot 和部署 webhook。默认只预览。

| 选项 | 说明 |
|---|---|
| `--apply` | 执行 |
| `--profile <名字>` | multica profile；也可以用环境变量 `AUTOTEAM_MULTICA_PROFILE` |
| `--workspace <slug 或 ID>` | 覆盖 autoteam.conf 的 `AUTOTEAM_MULTICA_WORKSPACE` |
| `--only <部分>` | 只处理其中几部分：`statuses,agents,project,autopilots` |
| `--paused` | 新建的 autopilot 立即暂停 |
| `--rotate-webhook` | 重新生成部署 webhook 地址并写入 GitHub secret |

环境变量：`AUTOTEAM_MULTICA_BIN`（multica 可执行文件路径）、`MULTICA_TOKEN` / `MULTICA_SERVER_URL`（覆盖 profile 里的 API 凭据，只用于建状态）。

## autoteam doctor

只读检查，逐项给出 ✅ / ⚠️ / ❌，有 ❌ 时退出码为 1。

| 选项 | 说明 |
|---|---|
| `--skip-github` | 不检查 GitHub |
| `--skip-multica` | 不检查 Multica |
| `--profile`、`--workspace` | 同 autoteam multica |

检查项：工作流文件和受管块、Makefile 目标是否还是桩、CODEOWNERS、registry 是否合法；GitHub 的仓库设置、规则集、secret、CODEOWNERS 错误、机器账号、最近一次 gate；Multica 的自定义状态、agent（存在、runtime 在线、指令和仓库文件一致、最近一次运行有没有失败）、项目、autopilot 和触发器。

## autoteam runtimes

列出工作区里的 runtime，第一列就是 registry.yaml 里 `runtime` 字段的写法（`provider@设备`）。

## autoteam diff

```bash
autoteam diff                       # 对比全部文件
autoteam diff .github/CODEOWNERS    # 只看某几个
```

对比已安装的文件和当前模板的渲染结果，受管块只比较块内内容。

升级 autoteam 的步骤：更新 autoteam（`npx skills update autoteam` 或 `git pull`）→ `autoteam init` 补上新增的文件 → `autoteam diff` 看已有文件的差异 → 没改过的文件用 `autoteam init --force <文件...>` 覆盖，改过的（比如加了运行时的 gate.yml）手动合并 → 提交、合并 → `autoteam multica --apply`。
