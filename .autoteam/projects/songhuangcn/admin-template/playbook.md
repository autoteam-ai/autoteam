# songhuangcn/admin-template 的经验

Planner 用 `autoteam playbook` 读到团队的 playbook 和这一份。这里只记本项目特有的经验；跨项目通用的写进团队的 .autoteam/playbook.md。

## 技术栈和检查

- 后台管理模板：`backend/`（Rails）+ `frontend/`（Vue，pnpm），本地开发用 `docker-compose.dev.yml`（rails、vuejs、mysql），根 Makefile 已有 setup / up / down 等目标。
- 原来的 CI/CD 在 GitLab（`.gitlab-ci.yml`：构建镜像、测试、部署），GitHub 上还没有工作流。接入（`onboard`）时要定下 `make check` 跑哪些测试和 lint、「上线」指什么；GitLab 的部署能否继续用、要不要迁到 GitHub Actions，先问人。
