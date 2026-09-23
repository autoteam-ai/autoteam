# 必须由人做的事

这些步骤涉及创建账号、生成凭据或付费，agent 不能代劳。按用户的情况挑出相关的列给他。

## GitHub App

GitHub 不允许 PR 作者批准自己的 PR，所以 Implementer 和 Reviewer 用两个不同的 GitHub App，"写代码的不能评审自己"就由平台保证。用 App 而不是机器账号：不用注册邮箱和两步验证、不占席位。注意 Reviewer App 也要给 Contents 写权限，否则它的批准不计入必需审批数。

App 不能用 API 创建和安装，这一步只能由人做。三个 App 各做一遍：

1. 组织（或个人）Settings → Developer settings → GitHub Apps → New GitHub App。
2. **取消 Webhook 的 Active**（只当身份用，不需要 webhook 服务）；安装范围选 Only on this account。
3. Repository permissions：

   | App | 权限 |
   |---|---|
   | impl | Contents 读写、Pull requests 读写、**Workflows 读写**（没有它连含工作流改动的 PR 都提不了） |
   | review | Pull requests 读写、Contents **读写**（不能省：App 的批准只有在它有写权限时才计入必需审批数） |
   | planner | Actions 读写、Contents 只读、Pull requests 只读 |

4. 记下 App ID，Generate a private key 下载 `.pem`。
5. Install App → 只选本仓库。
6. App ID 填进 `.autoteam/autoteam.conf` 的 `AUTOTEAM_IMPLEMENTER_APP_ID` / `AUTOTEAM_REVIEWER_APP_ID` / `AUTOTEAM_PLANNER_APP_ID`；`.pem` 按角色放到各自机器的 `.autoteam/local/<角色>.pem`（这个目录不会被提交），`chmod 600`。
7. 在每台 agent 机器上跑一次 `.autoteam/scripts/gh-app-token.sh --setup-git <角色>`，确认输出的是 `<app>[bot]` 而不是你的账号。

私钥是长期凭据，比带过期时间的 token 权限宽：只装这一个仓库、权限给到最小、只放需要它的机器上。泄露了就删掉那把 key 重新生成。

人工账号要留一个：CODEOWNERS 不能写 App，规则文件的 Code Owner 是人，规则文件改动必须由人批准。

## GitHub 套餐

| 仓库 | 规则集 / 自动合并 | 合并队列 |
|---|---|---|
| 公开（个人或组织，Free 也行） | 有 | 只有组织仓库有 |
| 私有，个人 Free | **没有** | 没有 |
| 私有，个人 Pro / 组织 Team | 有 | 没有（需要 Enterprise Cloud） |

私有仓库在 GitHub Free 下没有平台闸门，只能靠 agent 指令约束（降级模式）。要拿到完整闸门：仓库改公开、升级 Pro，或迁到 Team 套餐的组织。

## Multica

1. 每台机器装 Multica daemon（桌面端自带，或 `multica setup cloud`），确认对应的 agent CLI（Claude Code、Codex 等）已登录各自的订阅账号，runtime 在线：`autoteam runtimes`。
2. 运行 `autoteam multica --apply` 的人要是工作区 owner 或 admin（自定义状态只有他们能建）。
3. 可选：Settings → GitHub 连接仓库，任务卡片上就能看到关联的 PR 和 CI 状态。
4. 按量计费的 agent：在厂商控制台设好消费上限，把 key 写进 `.autoteam/local/<agent>.json`（`{"ANTHROPIC_API_KEY": "..."}`，不要提交），registry.yaml 里用 `env_file` 指向它。

## 订阅和额度

订阅额度按账号算，同一个账号下的多个 agent 共用。registry.yaml 里如实写每个 agent 用哪个账号，每月核对一次各家规则（窗口、周上限、计费方式经常变）。
