# shellcheck shell=bash

stop_fixture() {
  setup_ready_repo
  cat > "$WORK/stop-multica" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$STOP_LOG"
. "$(dirname "$STUB_FIXTURES")/stubs/strip-multica-args.sh"
case "$1 $2" in
  'project list') echo '[{"id":"project-1","title":"shop"}]' ;;
  'issue list')
    if [ "${STOP_NO_NOTE:-0}" = 1 ]; then echo '{"issues":[],"has_more":false}'
    elif [[ " $* " == *" --offset 0 "* ]]; then
      echo '{"issues":[{"id":"note-1","title":"运营笔记"},{"id":"issue-work","title":"工作"}],"has_more":true}'
    else echo '{"issues":[{"id":"issue-next","title":"排队"}],"has_more":false}'; fi ;;
  'issue get')
    if [ -f "$STOP_STATE/marker" ]; then jq -n --argjson marker "$(cat "$STOP_STATE/marker")" '{metadata:{"autoteam.paused":$marker}}';
    else echo '{"metadata":{}}'; fi ;;
  'issue metadata')
    case $3 in
      set) while [ $# -gt 0 ]; do if [ "$1" = --value ]; then jq -n --arg value "$2" '$value' > "$STOP_STATE/marker"; break; fi; shift; done ;;
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
[{"id":"ap-active","title":"推进巡检","project_id":"project-1","status":"active","last_run_at":"2026-09-29T04:00:00Z"},{"id":"ap-old-paused","title":"旧暂停","project_id":"project-1","status":"paused","last_run_at":null},{"id":"ap-other","title":"别的项目","project_id":"project-2","status":"active"}]
EOF
  echo '[{"id":"run-chat","status":"running","issue_id":null}]' > "$STOP_STATE/tasks-agent-planner"
  echo '[{"id":"run-work","status":"running","issue_id":"issue-work"},{"id":"run-next","status":"queued","issue_id":"issue-next"},{"id":"run-other","status":"running","issue_id":"issue-other"}]' > "$STOP_STATE/tasks-agent-impl"
  echo '[]' > "$STOP_STATE/tasks-agent-rev"
  echo '[]' > "$STOP_STATE/tasks-agent-auditor"
}

# shellcheck disable=SC2153 # STUB_LOG / STUB_STATE 来自 tests/lib.sh
stop_cmd() {
  env -u MULTICA_SERVER_URL -u MULTICA_TOKEN PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" HOME="$WORK/.home" NO_COLOR=1 \
    STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" STUB_FIXTURES="$TESTS_DIR/fixtures" \
    AUTOTEAM_MULTICA_BIN="$WORK/stop-multica" bash "$AUTOTEAM" "$@"
}

# 一个仓库走完 stop 的生命周期：预览 → 执行 → 重复执行 → 恢复 → 没有运营笔记
t_stop_lifecycle_preview_apply_repeat_resume() {
  stop_fixture
  : > "$STOP_LOG"
  out=$(stop_cmd stop --keep-run run-chat)
  assert_eq "$(grep -c '推进巡检 (ap-active)' <<<"$out")" 1
  assert_contains "$out" 'run-work'
  assert_contains "$out" 'run-next'
  assert_not_contains "$out" 'run-chat'
  assert_no_file "$STOP_STATE/marker"
  assert_not_contains "$(cat "$STOP_LOG")" 'autopilot update'

  out=$(stop_cmd stop --apply --keep-run run-chat)
  assert_contains "$out" '已停止本项目'
  assert_contains "$out" '下次运行时间可以忽略'
  assert_contains "$out" '部署通知会丢失'
  assert_contains "$out" 'resume 后巡检会补查'
  assert_eq "$(jq -r 'fromjson | .active_autopilots[0]' "$STOP_STATE/marker")" ap-active
  assert_eq "$(jq -r '.[] | select(.id=="ap-active") | .status' "$STOP_STATE/autopilots")" paused
  assert_contains "$(cat "$STOP_LOG")" 'issue cancel-task run-work'
  assert_not_contains "$(cat "$STOP_LOG")" 'issue cancel-task run-chat'
  assert_eq "$(jq -r 'type' "$STOP_STATE/marker")" string 'CLI 将 JSON 对象存为字符串'
  assert_contains "$(cat "$STOP_LOG")" 'metadata set note-1 --key autoteam.paused --type string'
  out=$(stop_cmd status)
  assert_contains "$out" '已暂停'
  assert_contains "$out" '推进巡检 (ap-active)：paused，最后运行 2026-09-29T04:00:00Z'
  if stop_cmd status --check >/dev/null; then tfail '暂停时 --check 应失败'; fi

  # 暂停期间再 stop：预览提示保留原始恢复列表，执行也不覆盖它
  assert_contains "$(stop_cmd stop --keep-run run-chat)" '保留原始恢复列表'
  stop_cmd stop --apply --keep-run run-chat >/dev/null
  assert_eq "$(jq -r 'fromjson | .active_autopilots | join(",")' "$STOP_STATE/marker")" ap-active

  out=$(stop_cmd resume)
  assert_contains "$out" '巡检'
  assert_file "$STOP_STATE/marker"
  stop_cmd resume --apply >/dev/null
  assert_no_file "$STOP_STATE/marker"
  assert_eq "$(jq -r '.[] | select(.id=="ap-active") | .status' "$STOP_STATE/autopilots")" active
  assert_eq "$(jq -r '.[] | select(.id=="ap-old-paused") | .status' "$STOP_STATE/autopilots")" paused
  assert_eq "$(jq -r '.[] | select(.id=="ap-other") | .status' "$STOP_STATE/autopilots")" active
  out=$(stop_cmd status --check)
  assert_contains "$out" '未暂停'
  assert_not_contains "$out" 'autopilot：'
  out=$(stop_cmd status)
  assert_contains "$out" '推进巡检 (ap-active)：active，最后运行 2026-09-29T04:00:00Z'
  assert_contains "$out" '旧暂停 (ap-old-paused)：paused，最后运行 未运行'
  assert_not_contains "$out" '别的项目'
  assert_contains "$(stop_cmd resume --apply)" '无需恢复'

  # 项目里没有运营笔记：status 视为未暂停，stop 只能预览
  STOP_NO_NOTE=1; export STOP_NO_NOTE
  assert_contains "$(stop_cmd status --check)" '未暂停'
  assert_contains "$(stop_cmd stop)" '预览完成'
  if stop_cmd stop --apply >/dev/null 2>&1; then tfail '没有运营笔记时不能执行 stop'; fi
}

t_resume_skips_removed_definition_after_upgrade() {
  stop_fixture
  mkdir -p .autoteam/instructions/autopilots
  printf '%s\n' '---' 'title: 旧报告' '---' '旧指令' > .autoteam/instructions/autopilots/old.md
  jq '. + [{id:"ap-obsolete",title:"旧报告",project_id:"project-1",status:"active"}]' "$STOP_STATE/autopilots" > "$STOP_STATE/next"
  mv "$STOP_STATE/next" "$STOP_STATE/autopilots"
  stop_cmd stop --apply >/dev/null
  rm .autoteam/instructions/autopilots/old.md
  out=$(stop_cmd resume)
  assert_contains "$out" '跳过 autopilot「旧报告」（ap-obsolete）：已无生效定义，不恢复'
  : > "$STOP_LOG"
  out=$(stop_cmd resume --apply)
  assert_contains "$out" '已无生效定义，不恢复'
  assert_eq "$(jq -r '.[] | select(.id=="ap-obsolete") | .status' "$STOP_STATE/autopilots")" paused
  assert_not_contains "$(cat "$STOP_LOG")" 'autopilot update ap-obsolete'
  assert_eq "$(jq -r '.[] | select(.id=="ap-active") | .status' "$STOP_STATE/autopilots")" active
  assert_no_file "$STOP_STATE/marker"
}

t_stop_only_cancels_project_issue_runs() {
  stop_fixture
  : > "$STOP_LOG"
  out=$(stop_cmd stop)
  assert_contains "$out" '只处理项目 shop 的运行'
  cancel_list=${out#*将取消的运行：}
  cancel_list=${cancel_list%%其他项目任务的运行、不取消：*}
  assert_contains "$cancel_list" 'run-work'
  assert_contains "$cancel_list" 'run-next'
  assert_not_contains "$cancel_list" 'run-other'
  assert_not_contains "$cancel_list" 'run-chat'
  assert_contains "$out" 'run-other running issue-other'
  assert_contains "$out" '未关联任务、不取消：'
  assert_contains "$out" 'run-chat running'
  out=$(stop_cmd stop --apply --keep-run run-work)
  assert_contains "$out" '只处理项目 shop 的运行'
  log=$(cat "$STOP_LOG")
  assert_contains "$log" 'issue cancel-task run-next'
  assert_not_contains "$log" 'issue cancel-task run-work'
  assert_not_contains "$log" 'issue cancel-task run-other'
  assert_not_contains "$log" 'issue cancel-task run-chat'
  assert_not_contains "$log" 'issue get issue-'
}
