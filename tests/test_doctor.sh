# shellcheck shell=bash
# autoteam doctor 和装进目标仓库的两个脚本

# 配置完整时 doctor 不应有 ❌：$1 退出码，$2 输出，$3 场景说明
assert_doctor_ok() { assert_eq "$1" 0 "$3：$(printf '%s' "$2" | grep '❌')"; }

# 直接改桩状态里的 JSON：$1 是状态文件名，其余是 jq 的参数（最后一个是过滤式）
stub_json_edit() {
  local f=$STUB_STATE/$1
  shift
  jq "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# 在 Multica 界面上直接改 agent 的字段，模拟没走 PR 的改绑
doctor_edit_agent() {
  stub_json_edit mc-agents.json --arg n "$1" "map(if .name == \$n then $2 else . end)"
}

t_doctor_flags_todo_makefile_and_missing_launcher() {
  setup_init_repo
  out=$(autoteam_offline doctor --skip-github --skip-multica)
  rc=$?
  assert_eq "$rc" 1 "Makefile 还是桩时应失败"
  assert_contains "$out" "AUTOTEAM-TODO"
  assert_contains "$out" "工作流文件齐全"
  assert_contains "$out" "干净 checkout 只检查已提交的 HEAD，不包含未提交的改动"
  assert_contains "$out" "registry.yaml：6 个 agent"
  assert_not_contains "$out" "autoteam init autoteam" "入口还在时不该提示重建"
  rm autoteam
  out=$(autoteam_offline doctor --skip-github --skip-multica)
  rc=$?
  assert_contains "$out" "autoteam init autoteam"
  assert_eq "$rc" 1 "缺少根目录入口时 doctor 应失败"
}

t_doctor_reports_cli_version_other_than_pinned() {
  local pkg
  setup_applied_repo
  pkg=$(mktemp -d "$TEST_BASE/package.XXXXXX")
  cp -R "$ROOT/skills/autoteam/." "$pkg/"
  printf '%s\n' 4519627303be7b76fe058b4857d1d4a5e058295f > "$pkg/source-ref"
  AUTOTEAM=$pkg/bin/autoteam
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "与 ./autoteam 固定的版本"
  assert_contains "$out" "不一致：指令漂移的比对结果不代表"
  assert_eq "$rc" 1 "版本不一致时 doctor 应失败"
}

t_doctor_full_after_setup() {
  setup_applied_repo
  autoteam_stub github --apply >/dev/null
  out=$(autoteam_stub doctor)
  rc=$?
  assert_contains "$out" "与 ./autoteam 固定的版本一致"
  assert_contains "$out" "agent impl-claude（implementer）指令一致"
  assert_not_contains "$out" "指令漂移" "同步后的指令带前言，不算漂移"
  assert_contains "$out" "Makefile 有 check / dev / deploy"
  assert_contains "$out" "规则集生效：必须走 PR、1 个审批、必需检查 check"
  assert_contains "$out" "secret MULTICA_DEPLOY_HOOK 已设置"
  assert_contains "$out" "agent planner（planner）指令一致"
  assert_contains "$out" "agent rev-codex 的 runtime 不在线"
  assert_contains "$out" "autopilot「部署结果」已启用"
  assert_contains "$out" "项目有且只有一条运营笔记"
  assert_not_contains "$out" "与 registry 不一致" "刚同步完，runtime / 模型 / 并发都应一致"
  assert_doctor_ok "$rc" "$out" "配置完整时不应有错误"
  assert_contains "$out" "https://multica.test/test/agents"
  assert_contains "$out" "https://multica.test/test/autopilots"
  assert_contains "$out" "https://multica.test/test/projects"
}

t_doctor_warns_when_codeowners_gate_off() {
  setup_ready_repo
  echo 'AUTOTEAM_CODEOWNERS_GATE=off' >> .autoteam/autoteam.conf
  autoteam_stub github --apply >/dev/null
  out=$(autoteam_stub doctor --skip-multica)
  assert_contains "$out" "AUTOTEAM_CODEOWNERS_GATE=off：规则集不要求 Code Owner 审批"
}

# 运营笔记和 autopilot 的缺失、重复、同名异项目：一次预检出全部，再一次 apply 后复查
t_doctor_checks_project_notes_and_autopilots() {
  setup_applied_repo
  # 同一工作区别的项目有同名 autopilot，本项目的还没建：doctor 不能把别人的当成本项目的
  stub_json_edit mc-autopilots.json 'map(.autopilot.project_id = "proj-other")'
  echo '[]' > "$STUB_STATE/mc-issues-project.json"
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "本项目没有 autopilot「部署结果」"
  assert_contains "$out" '项目缺少运营笔记（autoteam multica --apply --only project）'
  assert_eq "$rc" 1 "本项目缺 autopilot 和运营笔记都算错误"

  # apply 给本项目另建一套后，别的项目排在前面的同名 autopilot 不影响判断；笔记重复则报错
  autoteam_stub multica --apply --only autopilots >/dev/null
  jq -n '[{id:"note-1",title:"运营笔记"},{id:"note-2",title:"运营笔记"}]' > "$STUB_STATE/mc-issues-project.json"
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "autopilot「部署结果」已启用"
  assert_not_contains "$out" "本项目没有 autopilot"
  assert_contains "$out" '项目有 2 条运营笔记，应只有一条'
  assert_eq "$rc" 1 "运营笔记重复应算错误"
}

# 指令漂移的三个来源（本地 eject 后改动、Multica 上改 agent、本地 eject 后改 autopilot）同时出现，一次预检出全部
t_doctor_detects_instruction_drift() {
  setup_applied_repo
  autoteam_stub eject reviewer >/dev/null
  autoteam_stub eject patrol >/dev/null
  out=$(autoteam_stub doctor --skip-github)
  assert_not_contains "$out" "指令漂移" "eject 后文本没变，不算漂移"
  echo "本地改了但没同步" >> .autoteam/instructions/roles/reviewer.md
  echo '尚未同步的新规则' >> .autoteam/instructions/autopilots/patrol.md
  # Multica 上是不带前言的旧文本：doctor 按「前言 + 角色文件」比对，所以要报漂移
  doctor_edit_agent impl-claude ".instructions = $(jq -Rs . < "$ROOT/skills/autoteam/instructions/roles/implementer.md")"
  out=$(autoteam_stub doctor --skip-github)
  assert_contains "$out" "agent rev-codex 的指令和生效文本（.autoteam/instructions/roles/reviewer.md）不一致"
  assert_contains "$out" 'autopilot「推进巡检」的指令和生效文本不一致（指令漂移）'
  assert_contains "$out" "agent impl-claude 的指令和生效文本（autoteam 包内 instructions/roles/implementer.md）不一致（指令漂移）"
  # 删掉 eject 的文件，生效文本回到包内版本，和 Multica 里的一致；重新同步 agent 后，漂移全部消失
  rm .autoteam/instructions/roles/reviewer.md .autoteam/instructions/autopilots/patrol.md
  autoteam_stub multica --apply --only agents >/dev/null
  out=$(autoteam_stub doctor --skip-github)
  assert_not_contains "$out" "指令漂移"
}

# runtime、模型、并发的漂移，以及 runtime 未绑定（空串和 null 两种形状），一次预检出全部
t_doctor_detects_registry_drift() {
  setup_applied_repo
  # 指令没变，只换了 runtime：以前 doctor 照样报"指令一致，runtime 在线"
  doctor_edit_agent impl-claude '.runtime_id = "rt-b-claude-0000" | .model = "claude-opus" | .max_concurrent_tasks = 5'
  doctor_edit_agent rev-codex '.model = "gpt-5"'
  # 实际值为空时比对输出里有相邻的 tab，不能把要求值错读成实际值
  doctor_edit_agent planner '.runtime_id = ""'
  doctor_edit_agent auditor '.runtime_id = null'
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "agent impl-claude 的 runtime 与 registry 不一致：实际 Claude (machine-b) rt-b-cla，registry 要求 claude@machine-a（Claude (machine-a) rt-a-cla）"
  assert_contains "$out" "autoteam multica --apply --only agents"
  assert_contains "$out" "agent planner 的 runtime 与 registry 不一致：实际 未绑定，registry 要求 claude@machine-c"
  assert_contains "$out" "agent auditor 的 runtime 与 registry 不一致：实际 未绑定，registry 要求 rt-c-claude-0000"
  assert_contains "$out" "agent rev-codex 的 模型 与 registry 不一致：实际 gpt-5，registry 要求 gpt-5.5"
  assert_contains "$out" "agent impl-claude 的 模型 与 registry 不一致：实际 claude-opus，registry 要求 default"
  assert_contains "$out" "agent impl-claude 的 并发 与 registry 不一致：实际 5，registry 要求 2"
  assert_not_contains "$out" "agent rev-codex 的 runtime 与 registry 不一致"
  assert_eq "$rc" 1 "runtime / 模型不一致应算错误"
  # 和 autoteam multica 预览是同一份比对
  out=$(autoteam_stub multica --only agents)
  assert_contains "$out" "更新 agent rev-codex： 模型"
  assert_contains "$out" "模型 并发"

  autoteam_stub multica --apply --only agents >/dev/null
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_not_contains "$out" "与 registry 不一致" "apply 之后应恢复一致"
  assert_doctor_ok "$rc" "$out" "恢复后不应有错误"
}

# 读取失败不能当成漂移：autopilot 触发器退出码非 0 但输出合法 JSON、agent 读超时、agent 输出不是 JSON
# （502 页面），分别出一次；上次运行失败和链接用配置的 app url 顺带在第一次核对
t_doctor_reports_read_failures_not_drift() {
  setup_applied_repo
  out=$(STUB_AUTOPILOT_GET=fail STUB_FAILED_RUN=1 STUB_APP_URL=https://app.example.test autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "读不到 autopilot「部署结果」的触发器"
  assert_contains "$out" "MULTICA_HTTP_TIMEOUT"
  assert_not_contains "$out" "autopilot「部署结果」已启用"
  assert_not_contains "$out" "没有触发器"
  assert_eq "$rc" 1 "读不到触发器应算错误"
  assert_contains "$out" "agent rev-codex 最近一次运行失败：Failed to authenticate: OAuth session expired"
  assert_not_contains "$out" "agent planner 最近一次运行失败"
  assert_contains "$out" "https://app.example.test/test/agents"
  assert_not_contains "$out" "https://multica.test/test/agents"
  for mode in fail garbage; do
    out=$(STUB_AGENT_GET=$mode autoteam_stub doctor --skip-github)
    rc=$?
    assert_contains "$out" "读不到 agent rev-codex 的配置" "$mode"
    assert_contains "$out" "MULTICA_HTTP_TIMEOUT" "$mode"
    assert_not_contains "$out" "指令漂移" "$mode"
    assert_not_contains "$out" "autoteam multica --apply）" "$mode 不该建议 --apply"
    assert_eq "$rc" 1 "读不到应算错误（$mode）"
  done
}

t_loop_guard_counts_rejections_and_markers() {
  setup_init_repo
  mkdir -p bin
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[{"number":12,"title":"MUL-7 按日期导出","state":"OPEN","url":"u12","reviews":[
   {"state":"CHANGES_REQUESTED","body":"x"},{"state":"COMMENTED","body":"【阻塞】少了边界处理"},{"state":"COMMENTED","body":"建议"}]},
 {"number":13,"title":"MUL-70 别的任务","state":"OPEN","url":"u13","reviews":[{"state":"CHANGES_REQUESTED","body":""}]}]
JSON
EOF
  cat > bin/multica <<'EOF'
#!/usr/bin/env bash
echo '[{"content":"【验收不通过】导出为空"},{"content":"普通评论"},{"content":"【换人】额度用完"},{"content":"【换人-Reviewer】评审前路由失败"}]'
EOF
  chmod +x bin/gh bin/multica
  out=$(PATH="$WORK/bin:$PATH" bash .autoteam/scripts/loop-guard.sh MUL-7)
  assert_eq "$(jq -r '.review_rejections' <<<"$out")" 2
  assert_eq "$(jq -r '.pull_requests | length' <<<"$out")" 1 "MUL-70 不应算进 MUL-7"
  assert_eq "$(jq -r '.acceptance_failures' <<<"$out")" 1
  assert_eq "$(jq -r '.implementer_switches' <<<"$out")" 1
  assert_eq "$(jq -r '.reviewer_switches' <<<"$out")" 1
  assert_eq "$(jq -r '.limits.reviewer_switches' <<<"$out")" 1
  assert_contains "$(jq -r '.notes[]' <<<"$out")" "已经换过 1 次 Reviewer"
  assert_eq "$(jq -r '.escalate' <<<"$out")" true
  assert_contains "$(jq -r '.reasons[0]' <<<"$out")" "打回 2 次"
  cat > bin/multica <<'EOF'
#!/usr/bin/env bash
echo '[{"content":"【换人-Reviewer】评审前路由失败"}]'
EOF
  out=$(PATH="$WORK/bin:$PATH" bash .autoteam/scripts/loop-guard.sh MUL-7)
  assert_eq "$(jq -r '.implementer_switches' <<<"$out")" 0 "Reviewer 换人不应计入 Implementer"
  assert_eq "$(jq -r '.reviewer_switches' <<<"$out")" 1
}

t_merge_mode_script() {
  setup_init_repo
  mkdir -p bin
  # gh 桩：按 GH_AUTO / GH_RULES 返回仓库设置和分支上生效的规则，并执行 --jq
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
expr=""; path=""
while [ $# -gt 0 ]; do case $1 in --jq) expr=$2; shift 2 ;; api) shift ;; *) path=$1; shift ;; esac; done
case $path in
  */rules/branches/*)
    if [ "$GH_RULES" = 403 ]; then echo '{"message":"Upgrade to GitHub Pro"}'; exit 1; fi
    out=$GH_RULES ;;
  *) out="{\"allow_auto_merge\": $GH_AUTO, \"default_branch\": \"main\"}" ;;
esac
if [ -n "$expr" ]; then jq -r "$expr" <<<"$out"; else echo "$out"; fi
EOF
  chmod +x bin/gh
  run() { PATH="$WORK/bin:$PATH" GH_AUTO=$1 GH_RULES=$2 bash .autoteam/scripts/merge-mode.sh; }
  checks='{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"check"}]}}'
  pr1='{"type":"pull_request","parameters":{"required_approving_review_count":1}}'
  pr0='{"type":"pull_request","parameters":{"required_approving_review_count":0}}'
  assert_eq "$(run true "[$checks,$pr1]")" platform "有必需检查 + 要求审批"
  assert_eq "$(run true "[$checks,$pr0]")" staged "有必需检查但不要求审批（单账号）"
  assert_eq "$(run true "[$checks]")" staged "只有必需检查，没有 pull_request 规则"
  assert_eq "$(run true "[$pr1]")" reviewer "只要求审批、检查不强制，等于没闸门"
  assert_eq "$(run false "[$checks,$pr1]")" reviewer "仓库没开自动合并"
  assert_eq "$(run true '[]')" reviewer "分支上没有任何规则"
  assert_eq "$(run false 403)" reviewer "GitHub Free 私有仓库应该是 reviewer"
}

t_merge_status_script() {
  setup_init_repo
  echo 'AUTOTEAM_REPO=acme/shop' >> .autoteam/autoteam.conf
  mkdir -p bin
  # gh 桩：记下 graphql 的变量，返回 GH_PR 作为 pullRequest；GH_FAIL=1 模拟查询失败
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$GH_LOG"
[ "$GH_FAIL" = 1 ] && { echo "gh: HTTP 502" >&2; exit 1; }
printf '{"data":{"repository":{"pullRequest":%s}}}\n' "$GH_PR"
EOF
  chmod +x bin/gh
  log=$WORK/gh.log
  run() { PATH="$WORK/bin:$PATH" GH_LOG=$log GH_FAIL=${2:-0} GH_PR=$1 bash .autoteam/scripts/merge-status.sh 7; }
  assert_eq "$(run '{"state":"MERGED","isInMergeQueue":false,"autoMergeRequest":null}')" merged "已合并"
  assert_eq "$(run '{"state":"OPEN","isInMergeQueue":true,"autoMergeRequest":null}')" queued "直接入队时 autoMergeRequest 为空"
  assert_eq "$(run '{"state":"OPEN","isInMergeQueue":false,"autoMergeRequest":{"enabledAt":"2026-09-26T00:00:00Z"}}')" auto "已开自动合并"
  assert_eq "$(run '{"state":"OPEN","isInMergeQueue":false,"autoMergeRequest":null}')" none "漏开自动合并"
  assert_eq "$(run '{"state":"CLOSED","isInMergeQueue":false,"autoMergeRequest":null}')" closed "关闭未合并"
  assert_contains "$(cat "$log")" "owner=acme"
  assert_contains "$(cat "$log")" "name=shop"
  assert_contains "$(cat "$log")" "number=7"
  # 查询失败、找不到 PR、参数不对：不输出结果，退出码非 0，不能被当成 none
  out=$(run '{}' 1 2>/dev/null) && tfail "查询失败应返回非 0"
  assert_eq "$out" ""
  out=$(run null 2>/dev/null) && tfail "找不到 PR 应返回非 0"
  assert_eq "$out" ""
  PATH="$WORK/bin:$PATH" bash .autoteam/scripts/merge-status.sh abc 2>/dev/null && tfail "PR 编号不是数字应返回非 0"
  true
}

# open-pr.sh 用 tests/stubs/gh：准备一个在功能分支上的仓库，$1 是 allow_auto_merge，$2 是分支上生效的规则
open_pr_repo() {
  setup_init_repo
  echo 'AUTOTEAM_REPO=acme/shop' >> .autoteam/autoteam.conf
  git checkout -q -b hdgcs-1-demo
  echo '正文' > body.md
  printf '{"allow_auto_merge": %s}' "$1" > "$STUB_STATE/repo-patch.json"
  printf '%s' "$2" > "$STUB_STATE/branch-rules.json"
}
open_pr() {
  env PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" \
    bash .autoteam/scripts/open-pr.sh "$@"
}
OPEN_PR_CHECKS='{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"check"}]}}'
OPEN_PR_APPROVAL='{"type":"pull_request","parameters":{"required_approving_review_count":1}}'

t_open_pr_platform_enables_and_verifies_auto_merge() {
  open_pr_repo true "[$OPEN_PR_CHECKS,$OPEN_PR_APPROVAL]"
  out=$(open_pr --title "HDGCS-1 演示" --body-file body.md) || tfail "platform 开成自动合并应返回 0"
  assert_contains "$out" "PR：https://github.com/acme/shop/pull/12"
  assert_contains "$out" "合并模式：platform"
  assert_contains "$out" "自动合并：auto"
  assert_log "gh pr create --repo acme/shop --base main --head hdgcs-1-demo --title HDGCS-1 演示 --body-file body.md"
  assert_no_log "--draft"
  assert_eq "$(cat "$STUB_STATE/merge-count")" 1 "只开一次自动合并"
  assert_log "gh pr merge 12 --repo acme/shop --auto --squash"
  # 同一分支再跑：不再新开 PR，只核对；已是 auto 就不再 gh pr merge
  out=$(open_pr) || tfail "已有 PR 时核对应返回 0"
  assert_contains "$out" "已有 PR #12"
  assert_contains "$out" "自动合并：auto"
  assert_eq "$(grep -c 'gh pr create' "$STUB_LOG")" 1 "已有 PR 不应再开"
  assert_eq "$(cat "$STUB_STATE/merge-count")" 1
}

t_open_pr_platform_retries_once_when_none() {
  open_pr_repo true "[$OPEN_PR_CHECKS,$OPEN_PR_APPROVAL]"
  # 第一次 gh pr merge 没生效，重试一次开上
  out=$(STUB_AUTO_MERGE_AFTER=2 open_pr --title "HDGCS-1 演示" --body-file body.md) || tfail "重试后开成应返回 0"
  assert_contains "$out" "自动合并：auto"
  assert_eq "$(cat "$STUB_STATE/merge-count")" 2 "none 时重试一次"
  # 重试后仍是 none：返回非 0，只试两次
  rm -f "$STUB_STATE/auto-merge" "$STUB_STATE/merge-count"
  out=$(STUB_AUTO_MERGE_AFTER=9 open_pr 12 2>&1) && tfail "重试后仍是 none 应返回非 0"
  assert_contains "$out" "自动合并：none"
  assert_contains "$out" "仍是 none"
  assert_eq "$(cat "$STUB_STATE/merge-count")" 2 "只重试一次"
  # gh pr merge 报错：原文打印出来
  rm -f "$STUB_STATE/merge-count"
  out=$(STUB_AUTO_MERGE_FAIL=1 open_pr 12 2>&1) && tfail "开不了自动合并应返回非 0"
  assert_contains "$out" "Auto merge is not allowed for this repository"
}

t_open_pr_rejects_non_default_base_or_closed() {
  open_pr_repo true "[$OPEN_PR_CHECKS,$OPEN_PR_APPROVAL]"
  # 合并模式按默认分支 main 判断；目标分支不是 main 的 PR 一律不处理，更不能开自动合并
  jq -n '{number: 12, url: "https://github.com/acme/shop/pull/12", state: "OPEN", baseRefName: "release", isDraft: false}' \
    > "$STUB_STATE/pr.json"
  out=$(open_pr 12 2>&1) && tfail "目标分支不是默认分支应返回非 0"
  assert_contains "$out" "目标分支是 release"
  out=$(open_pr 2>&1) && tfail "当前分支已有指向 release 的 PR 应返回非 0"
  assert_contains "$out" "目标分支是 release"
  assert_no_log "gh pr merge"
  # 已关闭的 PR 同样不处理
  jq -n '{number: 12, url: "https://github.com/acme/shop/pull/12", state: "CLOSED", baseRefName: "main", isDraft: false}' \
    > "$STUB_STATE/pr.json"
  out=$(open_pr 12 2>&1) && tfail "已关闭的 PR 应返回非 0"
  assert_contains "$out" "已关闭"
  assert_no_log "gh pr merge"
}

t_open_pr_staged_opens_draft_without_merge() {
  open_pr_repo true "[$OPEN_PR_CHECKS]"
  out=$(open_pr --title "HDGCS-1 演示" --body-file body.md) || tfail "staged 应返回 0"
  assert_contains "$out" "合并模式：staged"
  assert_contains "$out" "由 Reviewer 批准后放行"
  assert_log "--draft"
  assert_no_log "gh pr merge"
  assert_no_log "graphql"
}

t_open_pr_reviewer_never_merges() {
  open_pr_repo false "[$OPEN_PR_CHECKS,$OPEN_PR_APPROVAL]"
  out=$(open_pr --title "HDGCS-1 演示" --body-file body.md) || tfail "reviewer 应返回 0"
  assert_contains "$out" "合并模式：reviewer"
  assert_log "gh pr create"
  assert_no_log "--draft"
  assert_no_log "gh pr merge"
  # 返工时按编号核对，同样不碰 gh pr merge
  out=$(open_pr 12) || tfail "reviewer 核对应返回 0"
  assert_contains "$out" "合并模式：reviewer"
  assert_no_log "gh pr merge"
}

t_open_pr_help_and_bad_args() {
  open_pr_repo true '[]'
  assert_contains "$(open_pr --help)" "open-pr.sh <PR 编号>"
  open_pr abc >/dev/null 2>&1; assert_eq "$?" 2 "参数不对应返回 2"
  # 选项缺值：不能卡住，返回 2（timeout 兜住死循环）
  for args in "--title" "--body-file" "--title HDGCS-1 --body-file"; do
    # shellcheck disable=SC2086  # 故意按空格拆成多个参数
    out=$(timeout 10 env PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" STUB_LOG="$STUB_LOG" \
      STUB_STATE="$STUB_STATE" bash .autoteam/scripts/open-pr.sh $args 2>&1)
    assert_eq "$?" 2 "[$args] 缺值应立即返回 2"
    assert_contains "$out" "缺少值"
  done
  open_pr --title "HDGCS-1 演示" >/dev/null 2>&1 && tfail "新开 PR 缺 --body-file 应返回非 0"
  assert_no_log "gh pr create"
}

t_instructions_single_auto_merge_fallback() {
  dir=$ROOT/skills/autoteam/instructions
  # 核对自动合并只出现在交付（implementer）和推进 runbook 两处
  assert_eq "$(grep -rl "merge-status.sh" "$dir" | sed "s|$dir/||" | sort | tr '\n' ' ')" \
    "roles/implementer.md runbooks/progress.md " "merge-status.sh 只应出现在 implementer.md 和 progress.md"
  assert_file_contains "$dir/roles/implementer.md" "open-pr.sh --title"
  assert_file_contains "$dir/roles/implementer.md" "open-pr.sh <PR>"
  assert_file_contains "$dir/autopilots/patrol.md" "runbook progress"
  assert_file_contains "$dir/autopilots/deploy-result.md" "runbook progress"
  assert_file_contains "$dir/runbooks/progress.md" "【补开自动合并】"
  assert_file_contains "$dir/runbooks/progress.md" "open-pr.sh <PR>"
  assert_file_contains "$dir/roles/planner.md" "不要用你的身份跑 \`merge-mode.sh\`"
  ! grep -q "gh pr merge <PR> --auto" "$dir/roles/implementer.md" || tfail "implementer.md 不应再手写 gh pr merge --auto"
}

t_health_metrics_outputs_json_and_markdown() {
  setup_init_repo
  old=$(( $(date +%s) - 400 * 86400 ))
  mid=$(( $(date +%s) - 20 * 86400 ))
  echo a > old.txt && git add old.txt && GIT_AUTHOR_DATE="@$old" GIT_COMMITTER_DATE="@$old" git commit -qm old
  echo b > hot.txt && git add hot.txt && GIT_AUTHOR_DATE="@$mid" GIT_COMMITTER_DATE="@$mid" git commit -qm mid
  echo a2 >> old.txt && echo b2 >> hot.txt && git add old.txt hot.txt && git commit -qm now
  echo temporary > zzz-deleted.txt && git add zzz-deleted.txt && git commit -qm temporary
  git rm -q zzz-deleted.txt && git commit -qm deleted
  out=$(env PATH="$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.duplication_pct' <<<"$out")" null
  assert_eq "$(jq -r '.files_changed' <<<"$out")" 2
  assert_eq "$(jq -r '.legacy_touch_pct' <<<"$out")" 50.0
  assert_eq "$(jq -r '.rework_14d_pct' <<<"$out")" 50.0
  # 没有 gh：prs_7d 和 human_7d.reviews 都是 null，归一化比值也应是 null（零分母场景之一）
  assert_eq "$(jq -r '.human_review_per_merged_pr' <<<"$out")" null
  assert_eq "$(jq -r '.approvals_7d' <<<"$out")" null
  md=$(env PATH="$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --md)
  assert_contains "$md" "| 老文件改动占比 %（近 30 天，2 个文件） | 50.0 |"
  assert_contains "$md" "| 人工评审 / 合并 PR 比值（近 7 天） | — |"
}

# 造一个假 gh：merged 场景返回 $1 个 merged PR，reviewed-by 场景返回 $2 个 PR（评审次数）
stub_gh_pr_counts() {
  ghdir=$WORK/.stub-gh
  mkdir -p "$ghdir"
  merged_json=$(jq -n --argjson n "$1" '[range($n) | {number: (. + 1), additions: 1, deletions: 1, reviews: []}]')
  reviewed_json=$(jq -n --argjson n "$2" '[range($n) | {number: (. + 1)}]')
  printf '%s' "$merged_json" > "$ghdir/merged.json"
  printf '%s' "$reviewed_json" > "$ghdir/reviewed.json"
  cat > "$ghdir/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = auth ]; then exit 0; fi
if [ "\$1" = pr ] && [ "\$2" = list ]; then
  for a in "\$@"; do
    case "\$prev" in
      --search) search=\$a ;;
    esac
    prev=\$a
  done
  case "\$search" in
    merged:*) cat "$ghdir/merged.json" ;;
    reviewed-by:*) cat "$ghdir/reviewed.json" ;;
    *) echo '[]' ;;
  esac
  exit 0
fi
echo '[]'
EOF
  chmod +x "$ghdir/gh"
}

# 评审次数 / 合并 PR 数：正常比值，以及合并数为零时比值为 null（零分母）
t_health_metrics_human_review_per_merged_pr() {
  setup_init_repo
  git commit --allow-empty -qm seed
  local gh_path="$WORK/.stub-gh:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin"
  stub_gh_pr_counts 5 4
  out=$(env PATH="$gh_path" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.prs_7d.merged' <<<"$out")" 5
  assert_eq "$(jq -r '.human_7d.reviews' <<<"$out")" 4
  assert_eq "$(jq -r '.human_review_per_merged_pr' <<<"$out")" 0.8
  md=$(env PATH="$gh_path" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --md)
  assert_contains "$md" "| 人工评审 / 合并 PR 比值（近 7 天） | 0.8 |"

  stub_gh_pr_counts 0 3
  out=$(env PATH="$gh_path" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.prs_7d.merged' <<<"$out")" 0
  assert_eq "$(jq -r '.human_7d.reviews' <<<"$out")" 3
  assert_eq "$(jq -r '.human_review_per_merged_pr' <<<"$out")" null
  md=$(env PATH="$gh_path" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --md)
  assert_contains "$md" "| 人工评审 / 合并 PR 比值（近 7 天） | — |"
}

t_health_metrics_approval_comparison() {
  setup_init_repo
  git commit --allow-empty -qm seed
  mkdir -p "$WORK/approval-bin"
  cat > "$WORK/approval-bin/multica" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'project list') echo '[{"id":"proj","title":"autoteam"}]' ;;
  'issue list') echo '{"issues":[{"id":"a","identifier":"TST-1","updated_at":"2099-01-01T00:00:00Z"},{"id":"b","identifier":"TST-2","updated_at":"2099-01-01T00:00:00Z"},{"id":"c","identifier":"TST-3","updated_at":"2099-01-01T00:00:00Z"}],"has_more":false}' ;;
  'issue timeline')
    case "$3" in
      a) echo '[{"action":"status_changed","actor_id":"planner","actor_type":"agent","created_at":"2099-01-01T00:00:01Z","details":{"from":"backlog","to":"todo"}},{"action":"status_changed","actor_type":"member","created_at":"2099-01-01T00:00:03Z","details":{"from":"todo","to":"cancelled"}}]' ;;
      b|c) echo '[{"action":"status_changed","actor_id":"planner","actor_type":"agent","created_at":"2099-01-01T00:00:01Z","details":{"from":"backlog","to":"todo"}}]' ;;
    esac ;;
  'issue comment')
    case "$4" in
      a) echo '[{"author_id":"planner","created_at":"2099-01-01T00:00:00Z","content":"【自主放行】理由"},{"created_at":"2099-01-01T00:00:02Z","content":"【验收不通过】"}]' ;;
      b) echo '[{"author_id":"planner","created_at":"2099-01-01T00:00:00Z","content":"【自主放行】理由"}]' ;;
      c) echo '[{"author_id":"planner","created_at":"2099-01-01T00:00:00Z","content":"【人工授权放行】Song 批准"}]' ;;
    esac ;;
esac
EOF
  cat > "$WORK/approval-bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'auth status') exit 0 ;;
  'pr list') echo '[{"title":"TST-1 change","reviews":[{"state":"CHANGES_REQUESTED"}]}]' ;;
esac
EOF
  chmod +x "$WORK/approval-bin/multica" "$WORK/approval-bin/gh"
  # 模板初始化的项目名由仓库自动识别；与测试桩保持一致。
  sed -i 's/^AUTOTEAM_MULTICA_PROJECT=.*/AUTOTEAM_MULTICA_PROJECT=autoteam/' .autoteam/autoteam.conf
  out=$(env PATH="$WORK/approval-bin:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.approvals_7d.auto.count' <<<"$out")" 2
  assert_eq "$(jq -r '.approvals_7d.human.count' <<<"$out")" 1
  assert_eq "$(jq -r '.approvals_7d.auto.cancelled_pct' <<<"$out")" 50
  assert_eq "$(jq -r '.approvals_7d.auto.review_rejected_pct' <<<"$out")" 50
  assert_eq "$(jq -r '.approvals_7d.auto.acceptance_failed_pct' <<<"$out")" 50
  assert_eq "$(jq -r '.approvals_7d.human.cancelled_pct' <<<"$out")" 0
}

# 私钥检查：registry 里 planner 在 machine-c、impl-claude 在 machine-a、rev-codex 在 machine-b
doctor_keys_repo() {
  setup_ready_repo
  sed -e 's/^AUTOTEAM_IMPLEMENTER_APP_ID=.*/AUTOTEAM_IMPLEMENTER_APP_ID=111/' -e 's/^AUTOTEAM_REVIEWER_APP_ID=.*/AUTOTEAM_REVIEWER_APP_ID=222/' \
    -e 's/^AUTOTEAM_PLANNER_APP_ID=.*/AUTOTEAM_PLANNER_APP_ID=333/' .autoteam/autoteam.conf > .autoteam/autoteam.conf.new
  mv .autoteam/autoteam.conf.new .autoteam/autoteam.conf
  autoteam_stub multica --apply >/dev/null
  mkdir -p .autoteam/local "$WORK/.home/.autoteam"
}

# runtime 在本机时缺私钥算错误，不在本机只提示；私钥可放仓库 .autoteam/local 或 AUTOTEAM_KEYS_DIR。
# 一次 apply，逐步摆放私钥文件和本机 runtime，复用同一个仓库。
t_doctor_checks_private_keys() {
  doctor_keys_repo
  # 1. runtime 都不在本机：缺私钥只是提示，同一台远端机器只提示一条
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_not_contains "$out" "本机没有"
  assert_contains "$out" "远端机器 machine-a 的私钥待检查（角色：implementer"
  assert_contains "$out" "远端机器 rt-c-claude-0000 的私钥待检查（角色：planner"
  assert_doctor_ok "$rc" "$out" "runtime 都不在本机时缺私钥只是提示"

  # 2. implementer 和 auditor 的 runtime 在本机，没有私钥：算错误；auditor 用 planner 的私钥
  export STUB_LOCAL_RUNTIMES=rt-a-claude-0000,rt-c-claude-0000
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_eq "$rc" 1 "本机 runtime 缺私钥应算错误"
  assert_contains "$out" "本机没有 implementer 的私钥，但 agent impl-claude 的 runtime claude@machine-a 在这台机器上"
  assert_contains "$out" "AUTOTEAM_KEYS_DIR"
  # shellcheck disable=SC2088  # doctor 原样输出配置里的 ~/.autoteam，这里要匹配字面量
  assert_contains "$out" "~/.autoteam" "要给出应该放的位置"
  assert_contains "$out" "AUTOTEAM_IMPLEMENTER_APP_KEY"
  assert_not_contains "$out" "本机没有 reviewer 的私钥" "不在本机的 runtime 不判错"
  assert_contains "$out" "远端机器 machine-b 的私钥待检查（角色：reviewer"
  assert_contains "$out" "本机没有 planner 的私钥，但 agent auditor 的 runtime rt-c-claude-0000 在这台机器上（auditor 使用 planner 身份）"
  assert_contains "$out" "AUTOTEAM_PLANNER_APP_KEY"
  assert_contains "$out" "planner.pem"

  # 3. implementer 私钥在仓库本地，planner 私钥在 keys 目录
  : > .autoteam/local/implementer.pem
  : > "$WORK/.home/.autoteam/planner.pem"
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "本机有 implementer 的私钥"
  assert_not_contains "$out" "本机没有 implementer 的私钥"
  assert_contains "$out" "本机有 planner 的私钥（agent auditor 的 runtime 在本机；auditor 使用 planner 身份）"
  assert_not_contains "$out" "本机没有 planner 的私钥"
  assert_doctor_ok "$rc" "$out" "私钥齐全时不应有错误"

  # 4. implementer 私钥改放 keys 目录（带日期的文件名）
  rm .autoteam/local/implementer.pem
  : > "$WORK/.home/.autoteam/autoteam-implementer.2026-01-01.private-key.pem"
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "本机有 implementer 的私钥"
  assert_not_contains "$out" "本机没有 implementer 的私钥"
  assert_doctor_ok "$rc" "$out" "私钥齐全时不应有错误"
  unset STUB_LOCAL_RUNTIMES

  # 5. 两个 runtime 在同一台远端机器：只有一条聚合提示
  sed -i 's/codex@machine-b/claude@machine-a/' .autoteam/registry.yaml
  out=$(autoteam_stub doctor --skip-github)
  assert_contains "$out" "远端机器 machine-a 的私钥待检查（角色：implementer reviewer"
  count=$(printf '%s\n' "$out" | grep -c '远端机器 machine-a 的私钥待检查')
  assert_eq "$count" 1 "同一台远端机器只应有一条私钥提示"
  assert_contains "$out" "AUTOTEAM_KEYS_DIR，当前 ~/.autoteam"
}

# 登录和服务器配置缺失要分开提示
t_doctor_distinguishes_login_and_server_setup() {
  setup_ready_repo
  rm -rf "$WORK/.home/.multica"
  out=$(autoteam_stub doctor --skip-github 2>&1)
  assert_contains "$out" "multica 还没登录：先运行 multica login"
  assert_not_contains "$out" "默认 profile 没有配置服务器"

  mkdir -p "$WORK/.home/.multica"
  printf '{"token":"mul_test_token"}\n' > "$WORK/.home/.multica/config.json"
  out=$(autoteam_stub doctor --skip-github 2>&1)
  assert_contains "$out" "默认 profile 没有配置服务器"
  assert_contains "$out" "multica setup"
  assert_not_contains "$out" "multica 还没登录"
}

# 本地配置和文件层面的告警：已废弃的 cron 键、孤立的 eject 文件、已提交的入口
t_doctor_warns_local_config_issues() {
  setup_ready_repo
  autoteam_stub eject example >/dev/null
  out=$(autoteam_stub doctor --skip-github --skip-multica)
  assert_not_contains "$out" "已合并到"
  assert_not_contains "$out" "在 autoteam 包内已不存在"
  assert_not_contains "$out" "干净 checkout 预跑只检查已提交的 HEAD"

  printf 'AUTOTEAM_CRON_SCORECARD=0 8 * * 1\nAUTOTEAM_CRON_FRONTIER=0 11 * * 1\n' >> .autoteam/autoteam.conf
  cp .autoteam/instructions/runbooks/example.md .autoteam/instructions/runbooks/gone.md
  git add .
  git commit -qm "测试已提交的入口"
  out=$(autoteam_stub doctor --skip-github --skip-multica)
  assert_contains "$out" "AUTOTEAM_CRON_SCORECARD 已合并到 AUTOTEAM_CRON_HEALTH，旧键被忽略"
  assert_contains "$out" "AUTOTEAM_CRON_FRONTIER 已合并到 AUTOTEAM_CRON_DIRECTION，旧键被忽略"
  assert_contains "$out" ".autoteam/instructions/runbooks/gone.md 在 autoteam 包内已不存在"
  assert_contains "$out" "干净 checkout 预跑只检查已提交的 HEAD，不包含未提交的改动"
}

# list 的真实 CLI 形状为 {autopilots:[{id,title,project_id,status,...}],total:N}。
# 没有暂停标记时每个 paused autopilot 单独报；项目有暂停标记时合成一条暂停提醒
t_doctor_reports_project_pause() {
  setup_applied_repo
  stub_json_edit mc-autopilots.json 'map(.autopilot.status = "paused")'
  out=$(autoteam_stub doctor --skip-github)
  assert_eq "$?" 0
  assert_eq "$(grep -c '是 paused 状态' <<<"$out")" "$(jq length "$STUB_STATE/mc-autopilots.json")"
  assert_not_contains "$out" '项目已暂停'

  stub_json_edit mc-issues-project.json 'map(.metadata = {"autoteam.paused": ({at:"2026-09-29T04:00:00Z",operator:{id:"person-1",name:"Tester"},active_autopilots:[]} | tojson)})'
  out=$(autoteam_stub doctor --skip-github)
  assert_eq "$?" 0
  assert_eq "$(grep -c '项目已暂停' <<<"$out")" 1
  assert_contains "$out" '2026-09-29T04:00:00Z'
  assert_contains "$out" 'Tester'
  assert_contains "$out" 'autoteam resume --apply'
  assert_not_contains "$out" '是 paused 状态'
}

# 大对象分别越过 Linux 单参数上限，避免前一处失败掩盖后一处。
t_health_metrics_large_payloads() {
  local payload out rc md
  setup_init_repo
  git commit --allow-empty -qm seed
  mkdir -p "$WORK/large-bin"
  cat > "$WORK/large-bin/multica" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'project list') echo '[{"id":"proj","title":"autoteam"}]' ;;
  'issue list') echo '{"issues":[{"id":"a","identifier":"TST-1","updated_at":"2099-01-01T00:00:00Z"}],"has_more":false}' ;;
  'issue timeline') cat "$METRICS_FIXTURES/history.json" ;;
  'issue comment') cat "$METRICS_FIXTURES/comments.json" ;;
esac
EOF
  cat > "$WORK/large-bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'auth status') exit 0 ;;
  'pr list')
    case "$*" in
      *title,reviews*) cat "$METRICS_FIXTURES/reviews.json" ;;
      *) echo '[]' ;;
    esac ;;
esac
EOF
  chmod +x "$WORK/large-bin/gh" "$WORK/large-bin/multica"
  sed -i 's/^AUTOTEAM_MULTICA_PROJECT=.*/AUTOTEAM_MULTICA_PROJECT=autoteam/' .autoteam/autoteam.conf
  for payload in comments reviews history; do
    jq -n '[{action:"status_changed", actor_id:"planner", actor_type:"agent", created_at:"2099-01-01T00:00:01Z", details:{from:"backlog",to:"todo"}}]' > history.json
    jq -n '[{author_id:"planner",created_at:"2099-01-01T00:00:00Z",content:"【自主放行】"}]' > comments.json
    jq -n '[{title:"TST-1 修改",reviews:[{state:"CHANGES_REQUESTED"}]}]' > reviews.json
    jq --arg payload "$payload" '
      ("x" * 140000) as $padding
      | if $payload == "comments" then .[0].content += $padding
        elif $payload == "reviews" then .[0].reviews[0].body = $padding
        else .[0].details.padding = $padding end' "$payload.json" > large.json
    cp large.json "$payload.json"
    [ "$(wc -c < "$payload.json")" -gt 131072 ] || tfail "测试数据未超过 128KB"
    out=$(env PATH="$WORK/large-bin:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" METRICS_FIXTURES="$WORK" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
    rc=$?
    assert_eq "$rc" 0 "$payload 大数据 JSON 退出码"
    assert_eq "$(jq -r '.approvals_7d.auto.count' <<<"$out")" 1
    assert_eq "$(jq -r '.approvals_7d.auto.review_rejected_pct' <<<"$out")" 100
    md=$(env PATH="$WORK/large-bin:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" METRICS_FIXTURES="$WORK" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --md)
    assert_eq "$?" 0 "$payload 大数据 Markdown 退出码"
    assert_contains "$md" '| 自主放行 / 人批准数（近 7 天） | 1 / 0 |'
  done
}
