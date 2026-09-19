# 必须由人做的事

这些步骤涉及创建账号、生成凭据或付费，agent 不能代劳。按用户的情况挑出相关的列给他。

## GitHub 机器账号

GitHub 不允许 PR 作者批准自己的 PR，所以写代码和评审用不同账号，“写代码的不能评审自己”就由平台保证。

1. 注册账号（每个账号要单独的邮箱，建议开两步验证），例如 `acme-impl-bot`、`acme-review-bot`、`acme-planner-bot`。
2. 仓库在组织下：把机器账号加成组织成员（基础权限设为 No permission），再给本仓库 Write 权限。仓库在个人账号下：`aiwf github --apply --bots ...` 会发邀请，用机器账号登录后接受。
3. 生成 token，只授权本仓库、设过期时间：

   | 账号 | 组织仓库（fine-grained token） | 个人仓库（classic token） |
   |---|---|---|
   | impl | Contents 读写、Pull requests 读写 | `repo`；不要勾 `workflow`，这样它推不了工作流文件 |
   | review | Pull requests 读写、Contents 只读 | `repo` |
   | planner | Actions 读写、Contents 只读、Pull requests 只读 | `repo` |

   个人账号的仓库，协作者不能用 fine-grained token，这是 GitHub 的限制；想按最小权限给，就把仓库迁到组织下。
4. 在对应机器上登录：`gh auth login --with-token < token.txt`，再设 git 身份（`git config --global user.name/user.email`）。不同账号跑在不同机器（或至少不同系统用户、不同容器）上，避免互相读到凭据。

## GitHub 套餐

| 仓库 | 规则集 / 自动合并 | 合并队列 |
|---|---|---|
| 公开（个人或组织，Free 也行） | 有 | 只有组织仓库有 |
| 私有，个人 Free | **没有** | 没有 |
| 私有，个人 Pro / 组织 Team | 有 | 没有（需要 Enterprise Cloud） |

私有仓库在 GitHub Free 下没有平台闸门，只能靠 agent 指令约束（降级模式）。要拿到完整闸门：仓库改公开、升级 Pro，或迁到 Team 套餐的组织。

## Multica

1. 每台机器装 Multica daemon（桌面端自带，或 `multica setup cloud`），确认对应的 agent CLI（Claude Code、Codex 等）已登录各自的订阅账号，runtime 在线：`aiwf runtimes`。
2. 运行 `aiwf multica --apply` 的人要是工作区 owner 或 admin（自定义状态只有他们能建）。
3. 可选：Settings → GitHub 连接仓库，任务卡片上就能看到关联的 PR 和 CI 状态。
4. 按量计费的 agent：在厂商控制台设好消费上限，把 key 写进 `ops/agents/local/<agent>.json`（`{"ANTHROPIC_API_KEY": "..."}`，不要提交），registry.yaml 里用 `env_file` 指向它。

## 订阅和额度

订阅额度按账号算，同一个账号下的多个 agent 共用。registry.yaml 里如实写每个 agent 用哪个账号，每月核对一次各家规则（窗口、周上限、计费方式经常变）。
