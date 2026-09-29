# shellcheck shell=bash

next_fixture() {
  setup_ready_repo
  cat > "$WORK/next-multica" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$NEXT_LOG"
args=()
while [ $# -gt 0 ]; do
  case $1 in --profile|--workspace-id|--output) shift 2 ;; *) args+=("$1"); shift ;; esac
done
set -- "${args[@]}"
case "$1 $2" in
  'project list') echo '[{"id":"project-1","title":"shop"}]' ;;
  'agent list') echo '[{"id":"planner-1","name":"planner"}]' ;;
  'issue list')
    [ "${NEXT_FAIL:-}" != list ] || exit 1
    case " $* " in
      *' --status todo '*)
        if [ "${NEXT_EMPTY:-0}" = 1 ]; then echo '{"issues":[],"has_more":false,"limit":100,"offset":0,"total":0}'
        else echo '{"issues":[{"id":"ready","identifier":"HDGCS-1","status":"todo","assignee_type":"agent","assignee_id":"planner-1","parent_issue_id":"parent","stage":1},{"id":"blocked","identifier":"HDGCS-2","status":"todo","assignee_type":"agent","assignee_id":"planner-1","parent_issue_id":"parent","stage":2},{"id":"failed","identifier":"HDGCS-3","status":"todo","assignee_type":"agent","assignee_id":"impl-1","parent_issue_id":null,"stage":null}],"has_more":false,"limit":100,"offset":0,"total":3}'; fi ;;
      *' --status in_progress '*)
        if [ "${NEXT_EMPTY:-0}" = 1 ]; then echo '{"issues":[],"has_more":false,"limit":100,"offset":0,"total":0}'
        else echo '{"issues":[{"id":"running","identifier":"HDGCS-4","status":"in_progress","assignee_type":"agent","assignee_id":"impl-1","parent_issue_id":null,"stage":null}],"has_more":false,"limit":100,"offset":0,"total":1}'; fi ;;
    esac ;;
  'issue children')
    echo '{"stages":[{"stage":1,"total":1,"done":0,"issues":[{"id":"ready","status":"todo"}]},{"stage":2,"total":1,"done":0,"issues":[{"id":"blocked","status":"todo"}]}],"total":2,"unstaged":[]}' ;;
  'issue runs')
    [ "${NEXT_FAIL:-}" != runs ] || exit 1
    case $3 in
      failed) echo '[{"id":"run-3","status":"failed","failure_reason":"runtime_recovery","error":"daemon restarted"},{"id":"run-2","status":"completed"}]' ;;
      running) echo '[{"id":"run-4","status":"failed","error":"login expired"}]' ;;
      *) echo '[]' ;;
    esac ;;
  *) exec "$(dirname "$STUB_FIXTURES")/stubs/multica" "$@" ;;
esac
EOF
  chmod +x "$WORK/next-multica"
  NEXT_LOG=$WORK/.next-log
  export NEXT_LOG
}

next_cmd() {
  env -u MULTICA_SERVER_URL -u MULTICA_TOKEN PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" \
    HOME="$WORK/.home" NO_COLOR=1 STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" \
    STUB_FIXTURES="$TESTS_DIR/fixtures" AUTOTEAM_MULTICA_BIN="$WORK/next-multica" \
    NEXT_LOG="$NEXT_LOG" NEXT_EMPTY="${NEXT_EMPTY:-0}" NEXT_FAIL="${NEXT_FAIL:-}" bash "$AUTOTEAM" next "$@"
}

t_next_items_and_stage_barrier() {
  next_fixture
  out=$(next_cmd --output json)
  assert_eq "$(jq 'length' <<<"$out")" 3
  assert_eq "$(jq -r '.[0].category' <<<"$out")" dispatchable
  assert_eq "$(jq -r '.[1].reason' <<<"$out")" '最近一次运行失败：daemon restarted'
  assert_eq "$(jq -r '.[2].reason' <<<"$out")" '最近一次运行失败：login expired'
  assert_not_contains "$out" 'HDGCS-2'
  if next_cmd --check > "$WORK/next.out"; then tfail '有事项时 --check 应返回 1'; fi
  assert_contains "$(cat "$WORK/next.out")" 'HDGCS-1'
  assert_contains "$(cat "$NEXT_LOG")" 'issue children parent --output json'
}

t_next_empty_and_read_failure() {
  next_fixture
  NEXT_EMPTY=1; export NEXT_EMPTY
  assert_eq "$(next_cmd --check)" '无事可做'
  out=$(next_cmd --output json)
  assert_eq "$(jq 'length' <<<"$out")" 0
  NEXT_FAIL=list; export NEXT_FAIL
  if next_cmd --check > "$WORK/next.out" 2> "$WORK/next.err"; then tfail '读取失败不应成功'; else rc=$?; assert_eq "$rc" 2; fi
  assert_not_contains "$(cat "$WORK/next.out")" '无事可做'
  NEXT_EMPTY=0; NEXT_FAIL=runs; export NEXT_EMPTY NEXT_FAIL
  if next_cmd --check > "$WORK/next.out" 2> "$WORK/next.err"; then tfail '运行读取失败不应成功'; else rc=$?; assert_eq "$rc" 2; fi
  assert_not_contains "$(cat "$WORK/next.out")" 'HDGCS-1'
}
