---
description: 接入一个新的 GitHub 仓库：在团队仓库登记，成员仓库只加调用文件和 Makefile，同步 Multica 和 GitHub 设置
---
人要求接入一个还没出现在 `autoteam projects` 里的仓库时用。接入是普通需求：按 `intake` 建父任务（建在团队仓库的项目里），拆成下面两个子任务，按 `release` 放行（都改规则文件，通常由人放行）。`<身份>` = `autoteam token --run planner`。

1. **登记**（团队仓库，第 1 批）：`autoteam project add <owner/repo>`；`project.conf` 只写和团队默认不同的键（默认分支、PR 行数上限、自主放行等），`playbook.md` 写这个仓库的技术栈和检查方式。验收：合并后 `autoteam projects` 列出它。
2. **接入**（成员仓库，第 2 批）：在成员仓库 checkout 里 `autoteam init`，只生成 `.github/workflows/autoteam.yml` 和 Makefile 的 check / dev / deploy；三个目标改成真实命令（`make deploy` 要等线上换成本次提交再返回，没有线上环境就写明“上线”指什么），跑通 `make check`。不在成员仓库建 `.autoteam/`、`./autoteam` 或别的 autoteam 文件。

第 1 个子任务合并后，你在团队仓库 main 上同步（搬已合并的配置，不算改规则）：
- `<身份> autoteam multica --apply`：建 Multica 项目、挂仓库、建运营笔记，把团队「部署结果」的 webhook 写进新仓库的 secret；
- `<身份> autoteam -P <owner/repo> github --apply`：仓库设置和规则集（必需检查 `autoteam / check`）。报权限不足时按 `escalate`：请人给 planner App 加 Administration、Secrets 写权限，或请人自己跑这条命令。

三个 App 和 Multica 的 GitHub App 都要装在仓库所在的账号或组织上（选全部仓库，以后新建的仓库自动覆盖）；第 2 个子任务里 `autoteam doctor` 报没装、或 `multica issue pull-requests <任务>` 关联不到 PR 时，按 `escalate` 请人安装。第 2 个子任务合并、部署成功后，在成员仓库跑 `autoteam doctor` 无 ❌ 即整体验收通过。
