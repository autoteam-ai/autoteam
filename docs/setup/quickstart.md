# 快速上手

从零到跑通，按顺序做。每一步的细节在对应文档里。

## 1. 安装 aiwf

二选一：

```bash
# 让编码 agent 来装：之后在项目里说“帮我在这个项目里搭好自管理 agent 团队”
npx skills add songhuangcn/ai-workflow --skill ai-workflow

# 或者自己用
git clone https://github.com/songhuangcn/ai-workflow ~/.ai-workflow
```

下面用 `aiwf` 指代 `~/.ai-workflow/bin/aiwf`（用 skill 时是 `bash <skill 目录>/scripts/aiwf`）。

## 2. 生成文件

在项目根目录：

```bash
aiwf init --workspace <Multica 工作区 slug>
```

已有的文件不会被覆盖，AGENTS.md、CODEOWNERS、.gitignore 只追加一个受管块。被跳过的文件用 `aiwf diff <文件>` 看差异，手动合并。

## 3. 适配

1. `Makefile` 的 `check` / `dev` / `deploy` 改成真实命令，删掉 `AIWF-TODO`（[第 0 步](repo.md)）；
2. `.github/workflows/gate.yml`、`deploy.yml`、`rollback.yml` 补上需要的运行时和 secrets；
3. `ops/agents/registry.yaml` 按你的订阅账号和机器填，`aiwf runtimes` 列出 runtime（[按额度选 agent](../concepts/quota-routing.md)）；
4. `ops/agents/aiwf.conf` 填 `AIWF_HUMAN`（负责批准的 Multica 成员）和机器账号。

检查本地部分：

```bash
aiwf doctor --skip-github --skip-multica
```

## 4. 提交

开 PR，审阅后合并。之后这些规则文件受 CODEOWNERS 保护，改动都要人批准。

## 5. 配置 GitHub

```bash
aiwf github                  # 预览
aiwf github --apply          # 有机器账号：--bots impl=<账号>,review=<账号>,planner=<账号>
aiwf github --apply --trial  # 还没有机器账号：单账号试用模式
```

然后按提示完成机器账号的邀请、token 和登录（[第 1–3 步](github.md)）。

## 6. 配置 Multica

```bash
aiwf multica                 # 预览
aiwf multica --apply         # 想先不让定时任务跑，加 --paused
```

会建 4 个自定义状态、registry 里的 agent、一个项目、8 个 autopilot，并把部署 webhook 地址写进 GitHub secret（[第 4–6 步](multica.md)）。

## 7. 验收

```bash
aiwf doctor
```

所有 ❌ 处理掉，⚠️ 逐条确认是预期的（比如试用模式）。然后提一个小需求演练一遍：[跑通第一个需求](first-run.md)。
