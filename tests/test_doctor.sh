# shellcheck shell=bash
# autoteam doctor 和装进目标仓库的两个脚本

t_doctor_flags_todo_makefile() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  out=$(autoteam_offline doctor --skip-github --skip-multica)
  rc=$?
  assert_eq "$rc" 1 "Makefile 还是桩时应失败"
  assert_contains "$out" "AUTOTEAM-TODO"
  assert_contains "$out" "工作流文件齐全"
  assert_contains "$out" "registry.yaml：6 个 agent"
}

t_doctor_full_after_setup() {
  setup_ready_repo
  autoteam_stub github --apply >/dev/null
  autoteam_stub multica --apply >/dev/null
  out=$(autoteam_stub doctor)
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

t_doctor_warns_when_codeowners_gate_off() {
  setup_ready_repo
  echo 'AUTOTEAM_CODEOWNERS_GATE=off' >> .autoteam/autoteam.conf
  autoteam_stub github --apply >/dev/null
  autoteam_stub multica --apply >/dev/null
  out=$(autoteam_stub doctor)
  assert_contains "$out" "AUTOTEAM_CODEOWNERS_GATE=off：规则集不要求 Code Owner 审批"
}

t_doctor_detects_autopilot_bound_to_other_project() {
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
  # 项目改名后会新建一个项目，老的 autopilot 还绑在旧项目上：它照常运行，
  # 只是在旧项目里找任务，什么都找不到，Planner 一直报"无待验收任务"
  jq 'map(.autopilot.project_id = "旧项目")' "$STUB_STATE/mc-autopilots.json" > "$STUB_STATE/mc-autopilots.tmp"
  mv "$STUB_STATE/mc-autopilots.tmp" "$STUB_STATE/mc-autopilots.json"
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "autopilot「部署结果」绑的是别的项目"
  assert_eq "$rc" 1 "绑错项目应该算错误"

  # 再 apply 一次要能改回来
  autoteam_stub multica --apply >/dev/null
  out=$(autoteam_stub doctor --skip-github)
  assert_contains "$out" "autopilot「部署结果」已启用"
}

t_doctor_detects_instruction_drift() {
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
  autoteam_stub eject reviewer >/dev/null
  out=$(autoteam_stub doctor --skip-github)
  assert_not_contains "$out" "指令漂移" "eject 后文本没变，不算漂移"
  echo "本地改了但没同步" >> .autoteam/instructions/roles/reviewer.md
  out=$(autoteam_stub doctor --skip-github)
  assert_contains "$out" "agent rev-codex 的指令和生效文本（.autoteam/instructions/roles/reviewer.md）不一致"
  # 删掉 eject 的文件，生效文本回到包内版本，和 Multica 里的一致，漂移消失
  rm .autoteam/instructions/roles/reviewer.md
  out=$(autoteam_stub doctor --skip-github)
  assert_not_contains "$out" "指令漂移"
}

t_doctor_reports_read_failure_not_drift() {
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
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

t_doctor_reports_autopilot_read_failure_with_valid_json() {
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
  # 退出码非 0 但输出是合法 JSON：不能当成读取成功
  out=$(STUB_AUTOPILOT_GET=fail autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "读不到 autopilot「部署结果」的触发器"
  assert_contains "$out" "MULTICA_HTTP_TIMEOUT"
  assert_not_contains "$out" "autopilot「部署结果」已启用"
  assert_not_contains "$out" "没有触发器"
  assert_eq "$rc" 1 "读不到触发器应算错误"
}

t_doctor_reports_failed_last_run() {
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
  out=$(STUB_FAILED_RUN=1 autoteam_stub doctor --skip-github)
  assert_contains "$out" "agent rev-codex 最近一次运行失败：Failed to authenticate: OAuth session expired"
  assert_not_contains "$out" "agent planner 最近一次运行失败"
}

t_loop_guard_counts_rejections_and_markers() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
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
  out=$(PATH="$WORK/bin:$PATH" bash .autoteam/scripts/loop-guard.sh MUL-7)
  assert_eq "$(jq -r '.review_rejections' <<<"$out")" 2
  assert_eq "$(jq -r '.pull_requests | length' <<<"$out")" 1 "MUL-70 不应算进 MUL-7"
  assert_eq "$(jq -r '.acceptance_failures' <<<"$out")" 1
  assert_eq "$(jq -r '.implementer_switches' <<<"$out")" 1
  assert_eq "$(jq -r '.escalate' <<<"$out")" true
  assert_contains "$(jq -r '.reasons[0]' <<<"$out")" "打回 2 次"
}

t_merge_mode_script() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
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

t_health_metrics_outputs_json_and_markdown() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  old=$(( $(date +%s) - 400 * 86400 ))
  mid=$(( $(date +%s) - 20 * 86400 ))
  echo a > old.txt && git add old.txt && GIT_AUTHOR_DATE="@$old" GIT_COMMITTER_DATE="@$old" git commit -qm old
  echo b > hot.txt && git add hot.txt && GIT_AUTHOR_DATE="@$mid" GIT_COMMITTER_DATE="@$mid" git commit -qm mid
  echo a2 >> old.txt && echo b2 >> hot.txt && git add old.txt hot.txt && git commit -qm now
  out=$(env PATH="$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.duplication_pct' <<<"$out")" null
  assert_eq "$(jq -r '.files_changed' <<<"$out")" 2
  assert_eq "$(jq -r '.legacy_touch_pct' <<<"$out")" 50.0
  assert_eq "$(jq -r '.rework_14d_pct' <<<"$out")" 50.0
  # 没有 gh：prs_7d 和 human_7d.reviews 都是 null，归一化比值也应是 null（零分母场景之一）
  assert_eq "$(jq -r '.human_review_per_merged_pr' <<<"$out")" null
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

t_health_metrics_human_review_per_merged_pr_normal() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  git commit --allow-empty -qm seed
  stub_gh_pr_counts 5 4
  out=$(env PATH="$ghdir:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.prs_7d.merged' <<<"$out")" 5
  assert_eq "$(jq -r '.human_7d.reviews' <<<"$out")" 4
  assert_eq "$(jq -r '.human_review_per_merged_pr' <<<"$out")" 0.8
  md=$(env PATH="$ghdir:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --md)
  assert_contains "$md" "| 人工评审 / 合并 PR 比值（近 7 天） | 0.8 |"
}

t_health_metrics_human_review_per_merged_pr_zero_denominator() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  git commit --allow-empty -qm seed
  stub_gh_pr_counts 0 3
  out=$(env PATH="$ghdir:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --json)
  assert_eq "$(jq -r '.prs_7d.merged' <<<"$out")" 0
  assert_eq "$(jq -r '.human_7d.reviews' <<<"$out")" 3
  assert_eq "$(jq -r '.human_review_per_merged_pr' <<<"$out")" null
  md=$(env PATH="$ghdir:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" AUTOTEAM_SKIP_JSCPD=1 bash .autoteam/scripts/health-metrics.sh --md)
  assert_contains "$md" "| 人工评审 / 合并 PR 比值（近 7 天） | — |"
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

t_doctor_keys_missing_on_local_runtime_fails() {
  doctor_keys_repo
  out=$(STUB_LOCAL_RUNTIMES=rt-a-claude-0000 autoteam_stub doctor --skip-github)
  rc=$?
  assert_eq "$rc" 1 "本机 runtime 缺私钥应算错误"
  assert_contains "$out" "本机没有 implementer 的私钥，但 agent impl-claude 的 runtime claude@machine-a 在这台机器上"
  assert_contains "$out" "AUTOTEAM_KEYS_DIR"
  # shellcheck disable=SC2088  # doctor 原样输出配置里的 ~/.autoteam，这里要匹配字面量
  assert_contains "$out" "~/.autoteam" "要给出应该放的位置"
  assert_contains "$out" "AUTOTEAM_IMPLEMENTER_APP_KEY"
  assert_not_contains "$out" "本机没有 reviewer 的私钥" "不在本机的 runtime 不判错"
  assert_contains "$out" "agent rev-codex 的 runtime codex@machine-b 不在本机"
}

t_doctor_keys_in_repo_local_passes() {
  doctor_keys_repo
  : > .autoteam/local/implementer.pem
  out=$(STUB_LOCAL_RUNTIMES=rt-a-claude-0000 autoteam_stub doctor --skip-github)
  assert_contains "$out" "本机有 implementer 的私钥"
  assert_not_contains "$out" "本机没有 implementer 的私钥"
}

t_doctor_keys_in_keys_dir_passes() {
  doctor_keys_repo
  : > "$WORK/.home/.autoteam/autoteam-implementer.2026-01-01.private-key.pem"
  out=$(STUB_LOCAL_RUNTIMES=rt-a-claude-0000 autoteam_stub doctor --skip-github)
  rc=$?
  assert_contains "$out" "本机有 implementer 的私钥"
  assert_not_contains "$out" "本机没有 implementer 的私钥"
  assert_eq "$rc" 0 "私钥齐全时不应有错误：$(printf '%s' "$out" | grep '❌')"
}

t_doctor_keys_remote_runtime_only_hints() {
  doctor_keys_repo
  out=$(autoteam_stub doctor --skip-github)
  rc=$?
  assert_not_contains "$out" "本机没有"
  assert_contains "$out" "agent impl-claude 的 runtime claude@machine-a 不在本机"
  assert_eq "$rc" 0 "runtime 都不在本机时缺私钥只是提示：$(printf '%s' "$out" | grep '❌')"
}
