# 0002：共享 agent 团队

采用 HDGCS-213 方案 C：一个 Multica 工作区共用一套 agent，服务多个 GitHub 仓库。

团队仓库（首个为 `autoteam-ai/autoteam`）持有权威 registry 和角色指令，只在团队仓库运行 `autoteam multica --apply` 创建、更新 agent。团队仓库的 `AUTOTEAM_TEAM_HOME` 为空；此时命令行为与原来完全一致。

成员仓库设置 `AUTOTEAM_TEAM_HOME=owner/name`，保存自己的配置、闸门、playbook、项目、运营笔记和 autopilot。registry 只需要角色到共享 agent 名的映射。成员仓库不能同步 agent；doctor 核对 agent 存在及其实际 runtime 在线，指令、runtime、模型、并发差异由团队仓库负责。本机 autoteam 版本无法和团队仓库比较，不额外检查。

「本项目」是任务所属 Multica 项目挂载的 GitHub 仓库。Planner 在 Chat 收需求时先确定项目，无法确定时问人；子任务建在同一项目。三个 GitHub App 必须安装到每个成员仓库，私钥共用 `~/.keys`。

暂停和停止的目标作用域是本项目：只取消本项目任务的运行，不影响共享 agent 在其他项目的运行。成员仓库自己的 autopilot 和暂停记录仍属于自己的项目。

本任务只实现共享团队配置、同步边界、doctor 和文档。角色指令及 runbook 的项目定义由 HDGCS-217 负责；stop 的跨项目运行隔离、个人账号仓库的 App 安装核对和试点接入及端到端验收由后续任务负责。本任务不修改 stop、init 或角色指令，不支持多个团队仓库，也不自动发现成员。
