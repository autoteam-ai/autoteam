# shellcheck shell=bash
# setup 复用两端预览和执行，并在执行后运行 doctor。

t_setup_preview_only() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub setup)
  assert_contains "$out" "第 1/2 步：预览 GitHub"
  assert_contains "$out" "第 2/2 步：预览 Multica"
  assert_contains "$out" "[预览] PATCH repos/acme/shop"
  assert_contains "$out" "[预览] 新建 agent planner"
  assert_contains "$out" "两端预览完成，未执行改动"
  assert_no_log 'agent create'
  assert_no_log 'gh secret set'
  assert_no_log 'BODY PATCH'
}

t_setup_apply_and_doctor() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub setup --apply)
  rc=$?
  assert_eq "$rc" 0 "setup 应通过：$out"
  assert_contains "$out" "执行 GitHub"
  assert_contains "$out" "执行 Multica"
  assert_contains "$out" "运行 doctor"
  assert_contains "$out" "规则集生效：必须走 PR"
  assert_contains "$out" "项目有且只有一条运营笔记"
  assert_log 'BODY PATCH repos/acme/shop'
  assert_log 'agent create --name planner'
  assert_eq "$(jq length "$STUB_STATE/mc-agents.json")" 4
}

t_setup_stops_on_multica_apply_failure() {
  setup_ready_repo
  touch "$STUB_STATE/mc-fail-agent-create"
  : > "$STUB_LOG"
  out=$(autoteam_stub setup --apply 2>&1)
  rc=$?
  assert_eq "$rc" 1 "中途失败应返回非零"
  assert_contains "$out" "GitHub 已完成，Multica 执行失败，doctor 未执行"
  assert_contains "$out" "autoteam multica --apply"
  assert_not_contains "$out" "运行 doctor"
  assert_log 'BODY PATCH repos/acme/shop'
  assert_eq "$(jq length "$STUB_STATE/mc-agents.json")" 0
}
