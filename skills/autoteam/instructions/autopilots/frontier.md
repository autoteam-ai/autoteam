---
title: 前沿扫描
role: auditor
mode: create_issue
cron_key: AUTOTEAM_CRON_FRONTIER
issue_title: 前沿扫描 {{date}}
subscriber: human
---

**开工先检查暂停：**先取得本项目仓库，在仓库运行 `bash ./autoteam status --check`。如果已暂停，立即结束本次运行，不读写任务、不执行 runbook、不发评论；检查失败也先停止并报告给人。仅人与 Planner 的 Chat 对话可以跳过此检查，以便执行恢复。

做一次前沿扫描，写在本任务的评论里，然后把本任务设为 done。

这套流程的指令和参数是在某个时间点的模型能力和平台能力下定的。模型变强、平台加了新能力之后，有些约束会变得多余，有些做法会变得过时——**不主动查，项目就会一直在旧知识下演进**。

## 查什么

1. **agent CLI**：registry.yaml 里用到的每个 CLI（Claude Code、Codex 等）的当前版本和最近的变更，和机器上装的版本对比。
2. **模型**：这些 CLI 现在默认用什么模型，上下文窗口、能力、价格有没有变化。
3. **额度和计费规则**：registry.yaml 的 accounts 段写的窗口和上限还对不对（这类规则变得很勤）。
4. **Multica**：CLI 和平台有没有改行为，尤其是任务状态、唤醒规则、autopilot。
5. **GitHub**：规则集、合并队列、App 权限有没有新增能力。

查不到就写"查不到"，不要猜。没有联网检索能力时，至少查本地版本号和已经装在机器上的 changelog，并在报告里写明这次只查了哪些。

## 怎么给结论

只写**会导致改动**的发现，每条三段：

- 变了什么（带来源和日期）；
- 因此现在哪里不适配，具体到 `<文件>:<行>` 或某个 `AUTOTEAM_*` 参数；
- 建议怎么改。

举例（格式示意，不要照抄结论）：某 CLI 的上下文窗口翻倍了 → `autoteam.conf` 的 `AUTOTEAM_PR_MAX_LINES` 是按旧窗口定的，可以放宽 → 建议改成多少、依据是什么。

平台新增了某个能力，能把现在只靠指令约束的一条变成硬约束的，**优先报**——这类改进最值钱，对照 `docs/concepts/invariants.md` 的四条不变量看。

没有值得改的，只回复“本周无需调整”，不要建任务。

最后按 .autoteam/auditor.md 提及 Planner。你只出报告，不建任务、不改代码。
