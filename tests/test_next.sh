# shellcheck shell=bash

next_fixture() {
  setup_ready_repo
  cat > "$WORK/next-multica" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$NEXT_LOG"
. "$(dirname "$STUB_FIXTURES")/stubs/strip-multica-args.sh"
case "$1 $2" in
  'project list') echo '[{"id":"project-1","title":"shop"}]' ;;
  'agent list') echo '[{"id":"planner-1","name":"planner"}]' ;;
  'issue list')
    if [ -n "${NEXT_ISSUES_FILE:-}" ]; then cat "$NEXT_ISSUES_FILE"; exit; fi
    [ "${NEXT_FAIL:-}" != list ] || exit 1
    case " $* " in
      *)
        if [ "${NEXT_EMPTY:-0}" = 1 ]; then echo '{"issues":[],"has_more":false}'
        else echo '{"issues":[{"id":"ready","identifier":"HDGCS-1","status":"todo","assignee_id":"planner-1","parent_issue_id":"parent","stage":1},{"id":"blocked","identifier":"HDGCS-2","status":"todo","assignee_id":"planner-1","parent_issue_id":"parent","stage":2},{"id":"failed","identifier":"HDGCS-3","status":"todo","assignee_id":"impl-1"},{"id":"running","identifier":"HDGCS-4","status":"in_progress","assignee_id":"impl-1"}],"has_more":false}'; fi ;;
    esac ;;
  'issue wakeup')
    [ "${NEXT_FAIL:-}" != wakeups ] || exit 1
    if [ -n "${NEXT_WAKEUPS:-}" ]; then cat "$NEXT_WAKEUPS"; else echo '[]'; fi ;;
  'issue comment') echo '[]' ;;
  'issue get')
    case $3 in
      HDGCS-125) [ "${NEXT_DEP:-}" != missing ] || exit 1
        jq -n --arg status "${NEXT_DEP_STATUS:-in_review}" '{id:"dep",identifier:"HDGCS-125",status:$status,metadata:{}}' ;;
      *) jq -n --arg id "$3" --arg dep "${NEXT_DEP:-}" '{id:$id,metadata:(if $dep == "" then {} elif $dep == "invalid" then {"autoteam.depends_on":false} else {"autoteam.depends_on":"HDGCS-125"} end)}' ;;
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
  env -u MULTICA_SERVER_URL -u MULTICA_TOKEN PATH="$WORK:$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" \
    HOME="$WORK/.home" NO_COLOR=1 STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" \
    STUB_FIXTURES="$TESTS_DIR/fixtures" AUTOTEAM_MULTICA_BIN="$WORK/next-multica" \
    NEXT_DEP="${NEXT_DEP:-}" NEXT_DEP_STATUS="${NEXT_DEP_STATUS:-in_review}" \
    NEXT_ISSUES_FILE="${NEXT_ISSUES_FILE:-}" NEXT_WAKEUPS="${NEXT_WAKEUPS:-}" NEXT_LOG="$NEXT_LOG" NEXT_EMPTY="${NEXT_EMPTY:-0}" NEXT_FAIL="${NEXT_FAIL:-}" \
    NEXT_NO_OPEN="${NEXT_NO_OPEN:-}" NEXT_GH_LOG="${NEXT_GH_LOG:-}" NEXT_GH_FAIL="${NEXT_GH_FAIL:-}" NEXT_GH_LOOP="${NEXT_GH_LOOP:-}" \
    AUTOTEAM_ISSUE_PREFIX=HDGCS bash "$AUTOTEAM" next "$@"
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

next_github_fixture() {
  next_fixture
  cat > "$WORK/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NEXT_GH_LOG"
[ "${NEXT_GH_FAIL:-}" != 1 ] || exit 1
case " $* " in
  *' --state merged '*)
    echo '[{"number":11,"title":"HDGCS-4 merged","mergedAt":"2020-01-01T00:00:00Z"},{"number":12,"title":"HDGCS-3 merged","mergedAt":"2020-01-01T00:00:00Z"},{"number":10,"title":"HDGCS-4 older","mergedAt":"2020-01-01T00:00:00Z"}]' ;;
  *' --state open '*)
    if [ "${NEXT_NO_OPEN:-}" = 1 ]; then echo '[]'; exit; fi
    echo '[{"number":13,"title":"HDGCS-4 conflict","reviewDecision":"REVIEW_REQUIRED","mergeable":"CONFLICTING","statusCheckRollup":[]},{"number":14,"title":"HDGCS-3 approved","reviewDecision":"APPROVED","mergeable":"MERGEABLE","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}]' ;;
  *' --state all '*)
    if [ "${NEXT_GH_LOOP:-}" = 1 ]; then echo '[{"number":13,"title":"HDGCS-4 loop","state":"OPEN","url":"https://github.com/acme/shop/pull/13","reviews":[{"state":"CHANGES_REQUESTED"},{"state":"CHANGES_REQUESTED"}]}]'
    else echo '[]'; fi ;;
  *'api graphql'*) echo '{"data":{"repository":{"pullRequest":{"state":"OPEN","isInMergeQueue":false,"autoMergeRequest":null}}}}' ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$WORK/gh"
  NEXT_GH_LOG=$WORK/.next-gh-log; export NEXT_GH_LOG
}

t_next_github_categories_and_failure() {
  next_github_fixture
  out=$(next_cmd --output json)
  assert_eq "$(jq '[.[] | select(.category == "merged_unaccepted")] | length' <<<"$out")" 2
  assert_eq "$(jq '[.[] | select(.category == "pr_remediation")] | length' <<<"$out")" 2
  # 同一个事项的多个已合并 PR 只算一次
  assert_eq "$(jq '[.[] | select(.category == "merged_unaccepted" and .identifier == "HDGCS-4")] | length' <<<"$out")" 1
  assert_eq "$(jq '[.[] | select(.category == "merged_unaccepted" and .identifier == "HDGCS-3")] | length' <<<"$out")" 1
  assert_contains "$(cat "$NEXT_GH_LOG")" 'api graphql'
  NEXT_GH_LOOP=1; export NEXT_GH_LOOP
  out=$(next_cmd --output json)
  assert_eq "$(jq '[.[] | select(.category == "loop_limit")] | length' <<<"$out")" 1
  NEXT_GH_FAIL=1; export NEXT_GH_FAIL
  if next_cmd --check > "$WORK/next.out" 2> "$WORK/next.err"; then tfail 'GitHub 读取失败不应成功'; else rc=$?; assert_eq "$rc" 2; fi
  assert_not_contains "$(cat "$WORK/next.out")" '无事可做'
}


t_next_cross_requirement_dependencies() {
  next_fixture
  NEXT_DEP=waiting; export NEXT_DEP
  out=$(next_cmd --check --output json 2> "$WORK/deps.err") || true
  assert_eq "$(jq '[.[] | select(.category == "dispatchable")] | length' <<<"$out")" 0
  assert_contains "$(cat "$WORK/deps.err")" 'HDGCS-125（in_review）'
  NEXT_DEP_STATUS="done"; export NEXT_DEP_STATUS
  out=$(next_cmd --check --output json) || true
  assert_eq "$(jq '[.[] | select(.category == "dispatchable")] | length' <<<"$out")" 1
  for NEXT_DEP in missing invalid; do
    export NEXT_DEP
    out=$(next_cmd --output json 2> "$WORK/deps.err")
    assert_eq "$(jq '[.[] | select(.category == "dispatchable")] | length' <<<"$out")" 0
    assert_contains "$(cat "$WORK/deps.err")" '前提'
  done
}

t_next_future_and_expired_wakeups() {
  next_github_fixture
  NEXT_WAKEUPS=$WORK/wakeups.json; export NEXT_WAKEUPS
  cp "$TESTS_DIR/fixtures/next-wakeup.json" "$NEXT_WAKEUPS"
  out=$(next_cmd --output json)
  assert_eq "$(jq '[.[] | select(.category == "merged_unaccepted")] | length' <<<"$out")" 0
  assert_eq "$(jq '[.[] | select(.category == "pr_remediation")] | length' <<<"$out")" 2
  jq '.[0].next_fire_at = "2020-01-01T00:00:00.123456Z"' "$NEXT_WAKEUPS" > "$WORK/expired.json"
  mv "$WORK/expired.json" "$NEXT_WAKEUPS"
  out=$(next_cmd --output json)
  assert_eq "$(jq '[.[] | select(.category == "merged_unaccepted")] | length' <<<"$out")" 2
  NEXT_FAIL=wakeups; export NEXT_FAIL
  if next_cmd --check > "$WORK/next.out" 2> "$WORK/next.err"; then tfail '唤醒读取失败不应成功'; else rc=$?; assert_eq "$rc" 2; fi
}

t_next_only_waiting_and_blocked_agent() {
  next_github_fixture
  NEXT_ISSUES_FILE=$WORK/issues.json; NEXT_WAKEUPS=$WORK/wakeups.json
  export NEXT_ISSUES_FILE NEXT_WAKEUPS
  echo '{"issues":[{"id":"running","identifier":"HDGCS-4","status":"blocked","assignee_type":"member"},{"id":"failed","identifier":"HDGCS-3","status":"blocked","assignee_type":"agent"}],"has_more":false}' > "$NEXT_ISSUES_FILE"
  cp "$TESTS_DIR/fixtures/next-wakeup.json" "$NEXT_WAKEUPS"
  NEXT_NO_OPEN=1; export NEXT_NO_OPEN
  assert_eq "$(next_cmd --check)" '无事可做'
  jq '.[0].enabled = false' "$NEXT_WAKEUPS" > "$WORK/disabled.json"
  mv "$WORK/disabled.json" "$NEXT_WAKEUPS"
  out=$(next_cmd --output json)
  assert_eq "$(jq 'length' <<<"$out")" 1
  assert_eq "$(jq -r '.[0].identifier' <<<"$out")" HDGCS-3
  jq '.[0].enabled = true | .[0].next_fire_at = "2020-01-01T00:00:00Z"' "$NEXT_WAKEUPS" > "$WORK/expired.json"
  mv "$WORK/expired.json" "$NEXT_WAKEUPS"
  out=$(next_cmd --output json)
  assert_eq "$(jq -r '.[0].identifier' <<<"$out")" HDGCS-3
}
