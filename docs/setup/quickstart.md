---
title: 快速上手
---

# 快速上手

从零到跑通，按顺序做。每一步的细节在对应文档里。

## 1. 安装 autoteam

二选一：

```bash
# 让编码 agent 来装：之后在项目里说“帮我在这个项目里搭好自管理 agent 团队”
npx skills add autoteam-ai/autoteam --skill autoteam

# 或者自己用
git clone https://github.com/autoteam-ai/autoteam ~/.autoteam
```

下面用 `autoteam` 指代 `~/.autoteam/autoteam`（用 skill 时是 `bash ${CLAUDE_SKILL_DIR}/bin/autoteam`）。

## 2. 生成文件

在项目根目录：

```bash
autoteam init --workspace <Multica 工作区 slug>
```

`init` 还会在根目录生成可执行的 `./autoteam`，agent 用 `bash ./autoteam status --check` 检查暂停状态。入口只使用版本与固定提交一致的本机 skill（HOME 下别的版本会被忽略并提示）；没有一致版本时，从固定的 GitHub 提交下载 CLI 到 `~/.cache/autoteam/cli/`。把入口和其他生成文件一起提交。已有的文件不会被覆盖，AGENTS.md、CODEOWNERS、.gitignore 只追加一个受管块。被跳过的文件用 `autoteam diff <文件>` 看差异，手动合并。清单见[生成的文件](../reference/files.md)；角色指令不落盘，随 autoteam 包走。


## 3. 适配

1. `Makefile` 的 `check` / `dev` / `deploy` 改成真实命令，删掉 `AUTOTEAM-TODO`（[第 0 步](repo.md)）；
2. `.github/workflows/gate.yml`、`deploy.yml`、`rollback.yml` 补上需要的运行时和 secrets；
3. `.autoteam/registry.yaml` 按你的订阅账号和机器填，`autoteam runtimes` 列出 runtime（[按额度选 agent](../concepts/quota-routing.md)）；
4. `.autoteam/autoteam.conf` 填 `AUTOTEAM_HUMAN`（负责批准的 Multica 成员）和三个 `AUTOTEAM_*_APP_ID`。

检查本地部分：

```bash
autoteam doctor --skip-github --skip-multica
```

## 4. 提交

开 PR，审阅后合并。之后这些规则文件受 CODEOWNERS 保护，改动都要人批准。

## 5. 配置 GitHub 和 Multica

```bash
autoteam setup  # 一次预览两边；交互终端确认一次后执行
```

非交互终端默认只预览，确认后运行 `autoteam setup --apply`。命令依次执行 GitHub、Multica，最后自动运行 doctor；中途失败会说明已完成的步骤和继续方式。先建好三个 GitHub App、放好私钥：可用 `autoteam github --create-apps --apply` 一键创建，也可手工建（[GitHub 设置](github.md)）。还没建 App 时可加 `--trial` 试用；想先暂停新建的定时任务可加 `--paused`。

Multica 会同步 registry 里的 agent、一个项目、包内定义的 autopilot，并把部署 webhook 地址写进 GitHub secret（[Multica 设置](multica.md)）。执行结束会列出工作区的 agents、autopilots、项目看板链接。如果提示尚未登录，运行 `multica login`；如果默认 profile 未配置服务器，运行 `multica setup`，或用 `--profile` 指定已经配置的 profile。

### 分步操作（进阶）

```bash
autoteam github             # 预览 GitHub
autoteam github --apply     # 执行 GitHub；可加 --trial 或 --apps
autoteam multica            # 预览 Multica
autoteam multica --apply    # 执行 Multica；可加 --paused
autoteam doctor             # 验收
```

## 6. 验收

查看 `autoteam setup` 末尾的 doctor 结果。所有 ❌ 处理掉，⚠️ 逐条确认是预期的（比如试用模式）。然后提一个小需求演练一遍：[跑通第一个需求](first-run.md)。
`doctor` 结尾也会列出当前工作区的网页链接。同一台远端机器需要检查的 App 私钥会合成一条提示，列出角色与 `AUTOTEAM_KEYS_DIR`。
