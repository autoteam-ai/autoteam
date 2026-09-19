# AGENTS.md

本仓库是 ai-workflow：把自管理 agent 团队流程装进用户项目的工具（`aiwf`）、Agent Skill 和中文文档。

## 目录

- `skills/ai-workflow/` 是唯一的实现，必须自包含：`npx skills add` 只会拷贝这个目录。
  - `scripts/aiwf` 入口，`scripts/lib/*.sh` 各命令的实现；
  - `assets/templates/` 装进用户项目的文件，占位符写 `{{AIWF_名字}}`；
  - `SKILL.md`、`references/` 是给编码 agent 看的。
- `bin/aiwf` 只是薄包装，不要在这里加逻辑。
- `docs/` 是给人看的文档，`tests/` 是测试（`stubs/` 下是 gh、multica、curl 的桩）。

## 约定

- 脚本要兼容 macOS 自带的 bash 3.2：不用关联数组、`mapfile`、`${var,,}`；空数组用 `${arr[@]+"${arr[@]}"}` 展开。
- `$(函数)` 里调用会 `die` 的函数时，`|| true` 要写在命令替换外面：`x=$(f) || true`。写成 `$(f || true)` 挡不住 `exit`，会在 `set -e` 下把整个脚本带退。
- 模板渲染不要用 `${var//pat/rep}`：bash 5.2 起替换串里的 `&` 有特殊含义。
- aiwf 只新建和更新，不删除任何文件或远端资源；改动 GitHub、Multica 的命令默认只预览，`--apply` 才执行。
- 不打印 token 和 webhook 地址。
- 改了模板、命令行为或配置项，同一个 PR 里更新 `docs/` 和 `skills/ai-workflow/SKILL.md` 里对应的说明。

## 检查

```bash
make check   # shellcheck + actionlint + tests/run.sh；本机没装 linter 时用 docker 镜像
bash tests/run.sh multica   # 只跑名字里带 multica 的测试
```

不要声称检查通过，除非你真的跑了。
