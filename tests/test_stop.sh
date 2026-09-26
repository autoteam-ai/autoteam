# shellcheck shell=bash

stop_fixture() {
  setup_ready_repo
  cat > "$WORK/stop-multica" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$STOP_LOG"
args=()
while [ $# -gt 0 ]; do
  case $1 in --profile|--workspace-id|--output) shift 2 ;; *) args+=("$1"); shift ;; esac
done
set -- "${args[@]}"
case "$1 $2" in
  'project list') echo '[{"id":"project-1","title":"shop"}]' ;;
  'issue list') echo '{"issues":[{"id":"note-1","title":"运营笔记"}],"has_more":false}' ;;
  'issue get')
    if [ -f "$STOP_STATE/marker" ]; then jq -n --argjson marker "$(cat "$STOP_STATE/marker")" '{metadata:{"autoteam.paused":$marker}}';
    else echo '{"metadata":{}}'; fi ;;
  'issue metadata')
    case $3 in
      set) while [ $# -gt 0 ]; do if [ "$1" = --value ]; then printf '%s' "$2" > "$STOP_STATE/marker"; break; fi; shift; done ;;
      delete) rm "$STOP_STATE/marker" ;;
    esac
    echo '{}' ;;
  'autopilot list') jq -n --slurpfile a "$STOP_STATE/autopilots" '{autopilots:$a[0]}' ;;
  'autopilot update')
    id=$3; status=$5
    jq --arg id "$id" --arg status "$status" 'map(if .id==$id then .status=$status else . end)' "$STOP_STATE/autopilots" > "$STOP_STATE/next"
    mv "$STOP_STATE/next" "$STOP_STATE/autopilots"
    echo '{}' ;;
  'agent list') echo '[{"id":"agent-planner","name":"planner"},{"id":"agent-impl","name":"impl-claude"},{"id":"agent-rev","name":"rev-codex"},{"id":"agent-auditor","name":"auditor"}]' ;;
  'agent tasks') cat "$STOP_STATE/tasks-$3" ;;
  'issue cancel-task') echo '{}' ;;
  'user profile') echo '{"id":"person-1","name":"Tester"}' ;;
  *) exec "$(dirname "$STUB_FIXTURES")/stubs/multica" "$@" ;;
esac
EOF
  chmod +x "$WORK/stop-multica"
  STOP_STATE=$WORK/.stop STOP_LOG=$WORK/.stop/log
  mkdir -p "$STOP_STATE"
  export STOP_STATE STOP_LOG
  cat > "$STOP_STATE/autopilots" <<'EOF'
[{"id":"ap-active","title":"巡检","project_id":"project-1","status":"active"},{"id":"ap-old-paused","title":"旧暂停","project_id":"project-1","status":"paused"},{"id":"ap-other","title":"别的项目","project_id":"project-2","status":"active"}]
EOF
  echo '[{"id":"run-chat","status":"running","issue_id":"issue-chat"}]' > "$STOP_STATE/tasks-agent-planner"
  echo '[{"id":"run-work","status":"running","issue_id":"issue-work"},{"id":"run-next","status":"queued","issue_id":"issue-next"}]' > "$STOP_STATE/tasks-agent-impl"
  echo '[]' > "$STOP_STATE/tasks-agent-rev"
  echo '[]' > "$STOP_STATE/tasks-agent-auditor"
}

# shellcheck disable=SC2153 # STUB_LOG / STUB_STATE 来自 tests/lib.sh
stop_cmd() {
  env -u MULTICA_SERVER_URL -u MULTICA_TOKEN PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" HOME="$WORK/.home" NO_COLOR=1 \
    STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" STUB_FIXTURES="$TESTS_DIR/fixtures" \
    AUTOTEAM_MULTICA_BIN="$WORK/stop-multica" bash "$AUTOTEAM" "$@"
}

t_stop_preview_and_apply() {
  stop_fixture
  : > "$STOP_LOG"
  out=$(stop_cmd stop --keep-run run-chat)
  assert_contains "$out" 'run-work'
  assert_contains "$out" 'run-next'
  assert_not_contains "$out" 'run-chat'
  assert_no_file "$STOP_STATE/marker"
  assert_not_contains "$(cat "$STOP_LOG")" 'autopilot update'
  out=$(stop_cmd stop --apply --keep-run run-chat)
  assert_contains "$out" '已停止本项目'
  assert_eq "$(jq -r '.active_autopilots[0]' "$STOP_STATE/marker")" ap-active
  assert_eq "$(jq -r '.[] | select(.id=="ap-active") | .status' "$STOP_STATE/autopilots")" paused
  assert_contains "$(cat "$STOP_LOG")" 'issue cancel-task run-work'
  assert_not_contains "$(cat "$STOP_LOG")" 'issue cancel-task run-chat'
  assert_contains "$(stop_cmd status)" '已暂停'
  if stop_cmd status --check >/dev/null; then tfail '暂停时 --check 应失败'; fi
}

t_stop_repeat_preserves_original_and_resume() {
  stop_fixture
  stop_cmd stop --apply --keep-run run-chat >/dev/null
  stop_cmd stop --apply --keep-run run-chat >/dev/null
  assert_eq "$(jq -r '.active_autopilots | join(",")' "$STOP_STATE/marker")" ap-active
  out=$(stop_cmd resume)
  assert_contains "$out" '巡检'
  assert_file "$STOP_STATE/marker"
  stop_cmd resume --apply >/dev/null
  assert_no_file "$STOP_STATE/marker"
  assert_eq "$(jq -r '.[] | select(.id=="ap-active") | .status' "$STOP_STATE/autopilots")" active
  assert_eq "$(jq -r '.[] | select(.id=="ap-old-paused") | .status' "$STOP_STATE/autopilots")" paused
  assert_eq "$(jq -r '.[] | select(.id=="ap-other") | .status' "$STOP_STATE/autopilots")" active
  assert_contains "$(stop_cmd status --check)" '未暂停'
  assert_contains "$(stop_cmd resume --apply)" '无需恢复'
}
