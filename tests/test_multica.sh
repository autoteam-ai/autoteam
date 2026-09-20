# shellcheck shell=bash
# autoteam multica / runtimes：预览、新建、再跑变成无改动、runtime 找不到、webhook 写 secret

t_multica_preview_makes_no_writes() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub multica)
  assert_contains "$out" "profile：test"
  assert_contains "$out" "[预览] 新建状态 approved（已批准，类别 unstarted）"
  assert_contains "$out" "[预览] 新建 agent planner（planner，runtime rt-c-cla，模型 default，并发 1）"
  assert_contains "$out" "[预览] 新建 agent rev-codex（reviewer，runtime rt-b-cod，模型 gpt-5.5，并发 2）"
  assert_contains "$out" "runtime codex@machine-b 现在不在线"
  assert_contains "$out" "[预览] 新建项目 shop"
  assert_contains "$out" "[预览] 新建 autopilot「推进巡检」（planner，run_only，0 */2 * * *）"
  assert_no_log "agent create"
  assert_no_log "curl POST"
}

t_multica_apply_creates_everything() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply)
  assert_contains "$out" "已新建状态 shipping"
  assert_log 'BODY POST /api/issue-statuses {"key":"approved","name":"已批准","category":"unstarted","color":"#3b82f6"'
  assert_log "curl POST https://api.multica.test/api/issue-statuses auth=ok"
  assert_eq "$(jq length "$STUB_STATE/mc-agents.json")" 4
  assert_eq "$(jq -r '.[] | select(.name == "impl-claude") | .runtime_id' "$STUB_STATE/mc-agents.json")" rt-a-claude-0000
  assert_eq "$(jq -r '.[] | select(.name == "auditor") | .runtime_id' "$STUB_STATE/mc-agents.json")" rt-c-claude-0000
  assert_eq "$(jq -r '.[] | select(.name == "rev-codex") | .instructions' "$STUB_STATE/mc-agents.json" | head -n 1)" "$(head -n 1 ops/agents/reviewer.md)"
  assert_log "agent create --name rev-codex --runtime-id rt-b-codex-00000"
  assert_log "--model gpt-5.5"
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 8
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "每日摘要") | .triggers[0].cron_expression' "$STUB_STATE/mc-autopilots.json")" "0 9 * * *"
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "每日摘要") | .triggers[0].timezone' "$STUB_STATE/mc-autopilots.json")" "Asia/Shanghai"
  assert_log "autopilot create --title 每日摘要 --agent planner --mode create_issue"
  assert_log "--issue-title-template 每日摘要 {{date}}"
  assert_log "--subscriber Alice"
  assert_log "autopilot create --title agent 成绩单 --agent auditor"
  assert_eq "$(cat "$STUB_STATE/secret-MULTICA_DEPLOY_HOOK")" "https://api.multica.test/api/webhooks/SECRET-TOKEN-123"
  assert_not_contains "$out" "SECRET-TOKEN-123" "webhook 地址含凭据，不应打印"
  assert_not_contains "$out" "mul_test_token" "token 不应打印"
  assert_no_log "mul_test_token"
}

t_multica_second_apply_is_noop() {
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply)
  assert_contains "$out" "状态 approved（已批准）已存在"
  assert_contains "$out" "agent planner 已是最新"
  assert_contains "$out" "autopilot「推进巡检」已是最新"
  assert_contains "$out" "定时触发已是 0 */2 * * *（Asia/Shanghai）"
  assert_contains "$out" "部署 webhook 已存在，GitHub secret MULTICA_DEPLOY_HOOK 已设置"
  assert_no_log "agent create"
  assert_no_log "autopilot create"
  assert_no_log "trigger-add"
  assert_no_log "curl POST"
}

t_multica_updates_changed_instructions() {
  setup_ready_repo
  autoteam_stub multica --apply --only agents >/dev/null
  echo "新增一条规则" >> ops/agents/planner.md
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply --only agents)
  assert_contains "$out" "更新 agent planner： 指令"
  assert_log "agent update agent-planner"
  assert_contains "$out" "agent impl-claude 已是最新"
}

t_multica_reports_missing_runtime() {
  setup_ready_repo
  sed -i.bak 's/claude@machine-a/claude@nowhere/' ops/agents/registry.yaml && rm -f ops/agents/registry.yaml.bak
  out=$(autoteam_stub multica --only agents)
  assert_contains "$out" "agent impl-claude：找不到 runtime claude@nowhere"
  assert_contains "$out" "claude@machine-a（online）"
}

t_multica_paused_flag() {
  setup_ready_repo
  autoteam_stub multica --apply --paused >/dev/null
  assert_eq "$(jq '[.[] | select(.autopilot.status == "paused")] | length' "$STUB_STATE/mc-autopilots.json")" 8
}

t_runtimes_lists_selectors() {
  setup_ready_repo
  out=$(autoteam_stub runtimes)
  assert_contains "$out" "claude@machine-a"
  assert_contains "$out" "codex@machine-b"
  assert_contains "$out" "offline"
}
