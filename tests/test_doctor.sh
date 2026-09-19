# shellcheck shell=bash
# aiwf doctor 和装进目标仓库的两个脚本

t_doctor_flags_todo_makefile() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
  out=$(aiwf_offline doctor --skip-github --skip-multica)
  rc=$?
  assert_eq "$rc" 1 "Makefile 还是桩时应失败"
  assert_contains "$out" "AIWF-TODO"
  assert_contains "$out" "工作流文件齐全"
  assert_contains "$out" "registry.yaml：6 个 agent"
}

t_doctor_full_after_setup() {
  setup_ready_repo
  aiwf_stub github --apply >/dev/null
  aiwf_stub multica --apply >/dev/null
  out=$(aiwf_stub doctor)
  rc=$?
  assert_contains "$out" "Makefile 有 check / dev / deploy"
  assert_contains "$out" "规则集生效：必须走 PR、1 个审批、必需检查 check"
  assert_contains "$out" "secret MULTICA_DEPLOY_HOOK 已设置"
  assert_contains "$out" "自定义状态齐全"
  assert_contains "$out" "agent planner（planner）指令一致"
  assert_contains "$out" "agent rev-codex 的 runtime 不在线"
  assert_contains "$out" "autopilot「部署结果」已启用"
  assert_eq "$rc" 0 "配置完整时不应有错误：$(printf '%s' "$out" | grep '❌')"
}

t_doctor_detects_instruction_drift() {
  setup_ready_repo
  aiwf_stub multica --apply >/dev/null
  echo "本地改了但没同步" >> ops/agents/reviewer.md
  out=$(aiwf_stub doctor --skip-github)
  assert_contains "$out" "agent rev-codex 的指令和 ops/agents/reviewer.md 不一致"
}

t_loop_guard_counts_rejections_and_markers() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
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
echo '[{"content":"【验收不通过】导出为空"},{"content":"普通评论"},{"content":"【换人】额度用完"}]'
EOF
  chmod +x bin/gh bin/multica
  out=$(PATH="$WORK/bin:$PATH" bash ops/agents/scripts/loop-guard.sh MUL-7)
  assert_eq "$(jq -r '.review_rejections' <<<"$out")" 2
  assert_eq "$(jq -r '.pull_requests | length' <<<"$out")" 1 "MUL-70 不应算进 MUL-7"
  assert_eq "$(jq -r '.acceptance_failures' <<<"$out")" 1
  assert_eq "$(jq -r '.implementer_switches' <<<"$out")" 1
  assert_eq "$(jq -r '.escalate' <<<"$out")" true
  assert_contains "$(jq -r '.reasons[0]' <<<"$out")" "打回 2 次"
}

t_health_metrics_outputs_json_and_markdown() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
  old=$(( $(date +%s) - 400 * 86400 ))
  mid=$(( $(date +%s) - 20 * 86400 ))
  echo a > old.txt && git add old.txt && GIT_AUTHOR_DATE="@$old" GIT_COMMITTER_DATE="@$old" git commit -qm old
  echo b > hot.txt && git add hot.txt && GIT_AUTHOR_DATE="@$mid" GIT_COMMITTER_DATE="@$mid" git commit -qm mid
  echo a2 >> old.txt && echo b2 >> hot.txt && git add old.txt hot.txt && git commit -qm now
  out=$(env PATH="$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AIWF_SKIP_JSCPD=1 bash ops/agents/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.duplication_pct' <<<"$out")" null
  assert_eq "$(jq -r '.files_changed' <<<"$out")" 2
  assert_eq "$(jq -r '.legacy_touch_pct' <<<"$out")" 50.0
  assert_eq "$(jq -r '.rework_14d_pct' <<<"$out")" 50.0
  md=$(env PATH="$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AIWF_SKIP_JSCPD=1 bash ops/agents/scripts/health-metrics.sh --md)
  assert_contains "$md" "| 老文件改动占比 %（近 30 天，2 个文件） | 50.0 |"
}
