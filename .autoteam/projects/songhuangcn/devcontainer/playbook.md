# songhuangcn/devcontainer 的经验

Planner 用 `autoteam playbook` 读到团队的 playbook 和这一份。这里只记本项目特有的经验；跨项目通用的写进团队的 .autoteam/playbook.md。

## 技术栈和检查

- 仓库是 agent runtime 的镜像：`Dockerfile`（mise 装 agent CLI 和工具，版本在 `mise.toml`）、`dockerfiles/Dockerfile.java`、`docker-compose.yml`（本地）、`deploy/` + 根 `kustomization.yaml`（k3s 上的 devcontainer-cloud）。
- `make check`：docker 里跑 shellcheck（`scripts/`、`dockerfiles/` 下的 `*.sh`）、`docker compose config -q`、hadolint（只看 error，DL3004 有意忽略）。
- 「上线」= 镜像构建成功：`make deploy` 跑 `scripts/wait-build.sh`，等本次提交触发的 `build-devcontainer*.yml` 成功；k3s 部署在 build-devcontainer 的 deploy job 里，随构建触发。两个构建工作流有 paths 过滤，120 秒内没出现运行视为本次提交不触发。
- 回滚：对旧提交跑 `make deploy` 只会确认旧构建成功，不会重新部署到 k3s；要回滚得重新跑旧提交的构建，没有统一的 rollback 工作流。

## 踩过的坑

- agent 沙箱里 `make dev` 起不来 `app` 容器（Docker daemon 看不到沙箱文件系统，`./data` 挂载为空）：验证 `make dev` 只看命令能重复执行，容器内效果到真实宿主上看（HDGCS-220）。
- runtime 镜像就是 agent 自己跑的地方：升级 agent CLI、multica、autoteam 启动器都改这里，合并后要等 k3s 滚动完成、`multica runtime list` 显示 runtime 在线再验收（HDGCS-231）。
