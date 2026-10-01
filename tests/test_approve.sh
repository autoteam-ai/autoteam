# shellcheck shell=bash
# autoteam approve：桩的 issue children 形状取自真实输出（stages[].issues[] 含 status、assignee_id；unstaged 可为 null）。

approve_fixture() {
  setup_ready_repo
  cat > "$WORK/approve-multica" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$APPROVE_LOG"
. "$(dirname "$STUB_FIXTURES")/stubs/strip-multica-args.sh"
issue() { printf '{"id":"%s","identifier":"%s","status":"%s","assignee_type":"agent","assignee_id":"%s","stage":%s}' "$1" "$2" "$3" "$4" "$5"; }
case "$1 $2" in
  'project list') echo '[{"id":"project-1","title":"shop"}]' ;;
  'agent list') echo '[{"id":"planner-1","name":"planner"}]' ;;
  'issue get')
    case $3 in
      HDGCS-125) [ "${APPROVE_DEP:-}" != missing ] || exit 1
        jq -n --arg status "${APPROVE_DEP_STATUS:-in_review}" '{id:"dep",identifier:"HDGCS-125",status:$status,metadata:{}}' ;;
      *) jq -n --arg id "$3" --arg dep "${APPROVE_DEP:-}" '{id:$id,metadata:(if $dep == "" then {} elif $dep == "invalid" then {"autoteam.depends_on":false} else {"autoteam.depends_on":"HDGCS-125"} end)}' ;;
    esac ;;
  'issue children')
    case "${APPROVE_CASE:-two}" in
      two) echo "{\"stages\":[{\"stage\":1,\"total\":2,\"done\":0,\"issues\":[$(issue a1 H-1 backlog planner-1 1),$(issue a2 H-2 backlog planner-1 1)]},{\"stage\":2,\"total\":1,\"done\":0,\"issues\":[$(issue b1 H-3 backlog planner-1 2)]}],\"total\":3,\"unstaged\":null}" ;;
      later) echo "{\"stages\":[{\"stage\":1,\"total\":1,\"done\":0,\"issues\":[$(issue a1 H-1 in_progress impl-1 1)]},{\"stage\":2,\"total\":1,\"done\":0,\"issues\":[$(issue b1 H-3 backlog planner-1 2)]}],\"total\":2,\"unstaged\":null}" ;;
      none) echo "{\"stages\":[{\"stage\":1,\"total\":1,\"done\":1,\"issues\":[$(issue a1 H-1 done planner-1 1)]}],\"total\":1,\"unstaged\":null}" ;;
    esac ;;
  'issue status')
    [ "${APPROVE_FAIL:-}" != "$3" ] || { echo 'boom' >&2; exit 1; }
    : > "$APPROVE_STATE.$3" ;;
  'issue runs')
    if [ -e "$APPROVE_STATE.$3" ] && [ "${APPROVE_NO_RUN:-0}" != 1 ] && ! grep -q "^issue status $3 todo --no-start" "$APPROVE_LOG"; then echo '[{"id":"run-1","status":"queued"}]'; else echo '[]'; fi ;;
  *) exec "$(dirname "$STUB_FIXTURES")/stubs/multica" "$@" ;;
esac
EOF
  chmod +x "$WORK/approve-multica"
  APPROVE_LOG=$WORK/.approve-log; APPROVE_STATE=$WORK/.approve-state
  : > "$APPROVE_LOG"
  export APPROVE_LOG APPROVE_STATE
}

approve_cmd() {
  env -u MULTICA_SERVER_URL -u MULTICA_TOKEN PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" \
    HOME="$WORK/.home" NO_COLOR=1 STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" \
    STUB_FIXTURES="$TESTS_DIR/fixtures" AUTOTEAM_MULTICA_BIN="$WORK/approve-multica" AUTOTEAM_APPROVE_WAIT=0 \
    APPROVE_DEP="${APPROVE_DEP:-}" APPROVE_DEP_STATUS="${APPROVE_DEP_STATUS:-in_review}" \
    APPROVE_LOG="$APPROVE_LOG" APPROVE_STATE="$APPROVE_STATE" APPROVE_CASE="${APPROVE_CASE:-two}" \
    APPROVE_FAIL="${APPROVE_FAIL:-}" APPROVE_NO_RUN="${APPROVE_NO_RUN:-0}" bash "$AUTOTEAM" approve "$@"
}

t_approve_preview_changes_nothing() {
  approve_fixture
  out=$(approve_cmd HDGCS-126)
  assert_contains "$out" 'H-1'
  assert_contains "$out" '第 2 批'
  assert_not_contains "$(cat "$APPROVE_LOG")" 'issue status'
}

t_approve_wakes_planner_once() {
  approve_fixture
  out=$(approve_cmd HDGCS-126 --apply)
  log=$(cat "$APPROVE_LOG")
  assert_contains "$log" 'issue status a2 todo --no-start'
  assert_contains "$log" 'issue status b1 todo --no-start'
  assert_contains "$log" 'issue status a1 todo'
  assert_eq "$(grep -c 'issue status' <<<"$log")" 3
  assert_eq "$(grep -c 'issue status [^ ]* todo$' <<<"$log")" 1
  assert_eq "$(grep 'issue status' <<<"$log" | tail -1 | sed 's/.*issue status/issue status/; s/ --output.*//')" 'issue status a1 todo'
  assert_contains "$out" 'H-3'
  assert_contains "$out" 'Planner 的运行已生成'
}

t_approve_later_batch_is_quiet() {
  approve_fixture
  APPROVE_CASE=later; export APPROVE_CASE
  out=$(approve_cmd HDGCS-126 --apply)
  assert_contains "$(cat "$APPROVE_LOG")" 'issue status b1 todo --no-start'
  assert_eq "$(grep -c 'issue status [^ ]* todo$' "$APPROVE_LOG" || true)" 0
  assert_contains "$out" '不会被叫醒'
}

t_approve_nothing_to_do() {
  approve_fixture
  APPROVE_CASE=none; export APPROVE_CASE
  assert_contains "$(approve_cmd HDGCS-126 --apply)" '没有指派给 Planner 的 backlog 子任务'
  assert_not_contains "$(cat "$APPROVE_LOG")" 'issue status'
}

t_approve_reports_failures_and_missing_run() {
  approve_fixture
  APPROVE_FAIL=a2; export APPROVE_FAIL
  if approve_cmd HDGCS-126 --apply > "$WORK/approve.out" 2>&1; then tfail '有任务放行失败应返回非 0'; fi
  assert_contains "$(cat "$WORK/approve.out")" 'H-2'
  assert_contains "$(cat "$WORK/approve.out")" '失败：boom'
  assert_not_contains "$(cat "$APPROVE_LOG")" 'issue status a1 todo'
  assert_contains "$(cat "$WORK/approve.out")" '未叫醒 Planner'
  APPROVE_FAIL=; APPROVE_NO_RUN=1; export APPROVE_FAIL APPROVE_NO_RUN
  if approve_cmd HDGCS-126 --apply > "$WORK/approve.out" 2>&1; then tfail '没有生成运行应返回非 0'; fi
  assert_contains "$(cat "$WORK/approve.out")" '运行没有生成'
  assert_contains "$(cat "$WORK/approve.out")" '补救'
}


t_approve_cross_requirement_dependencies() {
  approve_fixture
  APPROVE_DEP=waiting; export APPROVE_DEP
  out=$(approve_cmd HDGCS-126)
  assert_contains "$out" '等待前提：HDGCS-125（in_review）'
  assert_not_contains "$out" '叫醒 Planner'
  out=$(approve_cmd HDGCS-126 --apply)
  assert_eq "$(grep -c 'issue status [^ ]* todo$' "$APPROVE_LOG" || true)" 0
  APPROVE_DEP_STATUS=done; export APPROVE_DEP_STATUS
  out=$(approve_cmd HDGCS-126)
  assert_contains "$out" '叫醒 Planner'
}
