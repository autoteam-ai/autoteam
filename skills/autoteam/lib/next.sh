# shellcheck shell=bash
# Read-only Multica and GitHub patrol queue.

next_usage() {
  cat <<'EOF'
用法：autoteam next [--check] [--output json] [--profile <名字>]

列出待派发、失败运行、已合并未验收、待补救 PR 和打转到上限、停滞和唤醒异常的任务。
--check：空清单打印「无事可做」并返回 0；有事返回 1；读取失败返回 2。
EOF
}

next_read_error() { printf 'autoteam next：读取%s失败\n' "$1" >&2; return 2; }

# 输出空串表示前提满足，否则输出等待原因；读取或解析失败一律阻止派发。
depends_on_reason() {
  local issue value keys key dependency status reasons="" error_code=${2:-0}
  issue=$(mc issue get "$1" --output json) || { printf '读取任务前提失败'; return "$error_code"; }
  if ! jq -e --arg id "$1" 'type == "object" and .id == $id and (.metadata | type == "object")' <<<"$issue" >/dev/null; then
    printf '任务前提格式错误'; return "$error_code"
  fi
  value=$(jq -er 'if .metadata | has("autoteam.depends_on") then .metadata["autoteam.depends_on"] | if type == "string" then . else error("前提必须为字符串") end else "" end' <<<"$issue") || { printf 'autoteam.depends_on 必须为字符串'; return "$error_code"; }
  [ -n "$value" ] || return 0
  keys=$(jq -nr --arg value "$value" '$value | split(",") | map(gsub("^\\s+|\\s+$"; "")) | if all(.[]; test("^[A-Z][A-Z0-9]*-[1-9][0-9]*$")) then unique[] else error("无效编号") end') || { printf 'autoteam.depends_on 编号解析失败'; return "$error_code"; }
  while IFS= read -r key; do
    if dependency=$(mc issue get "$key" --output json) &&
      jq -e --arg key "$key" 'type == "object" and .identifier == $key and (.status | type == "string")' <<<"$dependency" >/dev/null; then
      status=$(jq -r '.status' <<<"$dependency")
      [ "$status" != "done" ] || continue
      reasons="${reasons}${key}（${status}）；"
    else
      reasons="${reasons}${key}（不存在或读取失败）；"
      [ "$error_code" = 0 ] || { printf '%s\n' "$reasons" >&2; return "$error_code"; }
    fi
  done <<<"$keys"
  [ -z "$reasons" ] || printf '等待前提：%s' "$reasons"
}

next_collect_page() {
  local offset=0 page count more
  while :; do
    page=$(mc issue list --project "$NEXT_PROJECT_ID" --limit 100 --offset "$offset" \
      --fields id,identifier,status,assignee_type,assignee_id,parent_issue_id,stage,status_category,last_activity_at,updated_at,created_at,metadata --output json) || { next_read_error '任务'; return 2; }
    jq -e 'type == "object" and (.issues | type == "array") and (.has_more | type == "boolean")' <<<"$page" >/dev/null || { next_read_error '任务格式'; return 2; }
    jq -c '.issues[]' <<<"$page" >> "$NEXT_ISSUES" || return 2
    more=$(jq -r '.has_more' <<<"$page")
    [ "$more" = true ] || break
    count=$(jq '.issues | length' <<<"$page")
    [ "$count" -gt 0 ] || { next_read_error '任务分页'; return 2; }
    offset=$((offset + count))
  done
}

next_collect_github() {
  local merged open pr number identifier merged_at status reason hours id wakeups observing
  local seen="|"
  command -v gh >/dev/null 2>&1 || { next_read_error 'gh 命令'; return 2; }
  [ -n "$AUTOTEAM_REPO" ] && [ -n "$AUTOTEAM_ISSUE_PREFIX" ] || { next_read_error 'GitHub 仓库或任务前缀配置'; return 2; }
  hours=$AUTOTEAM_ACCEPT_RECHECK_HOURS
  [[ $hours =~ ^[0-9]+$ ]] || { next_read_error 'AUTOTEAM_ACCEPT_RECHECK_HOURS 配置'; return 2; }
  merged=$(gh pr list --repo "$AUTOTEAM_REPO" --state merged --limit 100 --json number,title,mergedAt) || { next_read_error '已合并 PR'; return 2; }
  jq -e 'type == "array" and all(.[]; (.number | type == "number") and (.title | type == "string") and (.mergedAt | type == "string"))' <<<"$merged" >/dev/null || { next_read_error '已合并 PR 格式'; return 2; }
  while IFS= read -r pr; do
    identifier=$(jq -r --arg prefix "$AUTOTEAM_ISSUE_PREFIX" '.title | (capture("^(?<key>" + $prefix + "-[0-9]+)([^0-9]|$)")? | .key) // empty' <<<"$pr")
    [ -n "$identifier" ] || continue
    case $seen in *"|$identifier|"*) continue ;; esac
    seen="$seen$identifier|"
    status=$(jq -r --arg key "$identifier" 'select(.identifier == $key) | .status' "$NEXT_ISSUES")
    [ -n "$status" ] && [ "$status" != 'done' ] && [ "$status" != cancelled ] || continue
    id=$(jq -r --arg key "$identifier" 'select(.identifier == $key) | select((.status_category // .status) != "done" and (.status_category // .status) != "cancelled") | .id' "$NEXT_ISSUES")
    [ -n "$id" ] || continue
    merged_at=$(jq -r '.mergedAt' <<<"$pr")
    if ! jq -en --arg at "$merged_at" --argjson hours "$hours" '($at | fromdateiso8601) < (now - $hours * 3600)' >/dev/null; then
      jq -en --arg at "$merged_at" '$at | fromdateiso8601' >/dev/null || { next_read_error '合并时间格式'; return 2; }
      continue
    fi
    if jq -e --arg id "$id" 'select(.id == $id) | .status == "blocked" and .assignee_type == "member"' "$NEXT_ISSUES" >/dev/null; then
      continue
    fi
    wakeups=$(next_wakeups "$id") || return 2
    jq -e 'type == "array" and all(.[]; (.enabled | type == "boolean") and (.next_fire_at == null or (.next_fire_at | type == "string")))' <<<"$wakeups" >/dev/null || { next_read_error "$identifier 唤醒格式"; return 2; }
    # 有限观察期从合并时刻计算，注册/续期不能重置上限；持续定时巡检不算观察期。
    observing=$(jq -r --arg at "$merged_at" --argjson cap "$AUTOTEAM_ACCEPT_OBSERVE_MAX_HOURS" '
      def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
      ($at | epoch) > (now - $cap * 3600) and
      any(.[]; .enabled and (.expires_at == null or (.expires_at | epoch) > now) and (.kind != "every" and .kind != "cron") and
        ((.next_fire_at != null and (.next_fire_at | epoch) > now) or
         (.kind == "event" and .expires_at != null and (.expires_at | epoch) > now)))
    ' <<<"$wakeups") || { next_read_error "$identifier 观察期"; return 2; }
    [ "$observing" != true ] || continue
    number=$(jq -r '.number' <<<"$pr")
    jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "PR #$number 已合并超过 $hours 小时，任务仍为 $status" \
      '{id:$id,identifier:$identifier,category:"merged_unaccepted",reason:$reason}' >> "$NEXT_ITEMS"
  done < <(jq -c 'sort_by(.mergedAt) | reverse | .[]' <<<"$merged")

  open=$(gh pr list --repo "$AUTOTEAM_REPO" --state open --limit 100 --json number,title,reviewDecision,statusCheckRollup,mergeable) || { next_read_error '开放 PR'; return 2; }
  jq -e 'type == "array" and all(.[]; (.number | type == "number") and (.title | type == "string") and (.statusCheckRollup | type == "array") and (.mergeable | type == "string"))' <<<"$open" >/dev/null || { next_read_error '开放 PR 格式'; return 2; }
  while IFS= read -r pr; do
    identifier=$(jq -r --arg prefix "$AUTOTEAM_ISSUE_PREFIX" '.title | (capture("^(?<key>" + $prefix + "-[0-9]+)([^0-9]|$)")? | .key) // empty' <<<"$pr")
    [ -n "$identifier" ] || continue
    id=$(jq -r --arg key "$identifier" 'select(.identifier == $key) | select((.status_category // .status) != "done" and (.status_category // .status) != "cancelled") | .id' "$NEXT_ISSUES")
    [ -n "$id" ] || continue
    if jq -e 'any(.statusCheckRollup[]; if .state != null then .state == "PENDING" or .state == "EXPECTED" else .status != "COMPLETED" and (.conclusion == null) end)' <<<"$pr" >/dev/null; then
      printf '%s\n' "$id" >> "$NEXT_CHECKS"
    fi
    number=$(jq -r '.number' <<<"$pr")
    if [ "$(jq -r '.mergeable' <<<"$pr")" = CONFLICTING ]; then
      reason="PR #$number 与主分支冲突"
    elif jq -e '.reviewDecision == "APPROVED" and (.statusCheckRollup | length > 0) and all(.statusCheckRollup[]; .status == "COMPLETED" and ((.conclusion == "SUCCESS") or (.conclusion == "SKIPPED") or (.conclusion == "NEUTRAL")))' <<<"$pr" >/dev/null; then
      status=$(bash "$(repo_root)/.autoteam/scripts/merge-status.sh" "$number") || { next_read_error "PR #$number 自动合并状态"; return 2; }
      [ "$status" = none ] || continue
      reason="PR #$number 已批准且检查通过，但未开自动合并"
    else
      continue
    fi
    jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "$reason" \
      '{id:$id,identifier:$identifier,category:"pr_remediation",reason:$reason}' >> "$NEXT_ITEMS"
  done < <(jq -c '.[]' <<<"$open")
}

# 缓存任务级规则，避免 GitHub 和健康巡检读到不同快照。
next_wakeups() {
  local file data
  file="$(autoteam_tmpdir)/next-wakeups-$1.json"
  if [ ! -f "$file" ]; then
    data=$(mc issue wakeup list "$1" --output json) || { next_read_error "$1 唤醒"; return 2; }
    jq -e 'def epoch: sub("\\.[0-9]+Z$";"Z") | fromdateiso8601; type == "array" and all(.[]; (.enabled | type == "boolean") and ([.next_fire_at,.expires_at,.timed_out_at,.updated_at] | all(.[]; . == null or (epoch | type == "number"))))' <<<"$data" >/dev/null || { next_read_error "$1 唤醒格式"; return 2; }
    printf '%s\n' "$data" > "$file"
  fi
  cat "$file"
}

next_collect_health() {
  local issue id identifier status runs wakeups activity reason deps key dependency waiting matched checks
  while IFS= read -r issue; do
    status=$(jq -r '.status_category // .status' <<<"$issue")
    case $status in done|cancelled) continue ;; esac
    id=$(jq -r '.id' <<<"$issue"); identifier=$(jq -r '.identifier' <<<"$issue")
    runs=$(mc issue runs "$id" --output json) || { next_read_error "$identifier 运行"; return 2; }
    jq -e 'type == "array" and all(.[]; (.status | type == "string"))' <<<"$runs" >/dev/null || { next_read_error "$identifier 运行格式"; return 2; }
    wakeups=$(next_wakeups "$id") || return 2
    activity=$(jq -en --argjson issue "$issue" --argjson runs "$runs" '
      def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
      [$issue.last_activity_at,$issue.updated_at,$issue.created_at,
       ($runs[] | .created_at,.started_at,.completed_at)] | map(select(. != null) | epoch) | if length == 0 then error("缺少活动时间") else max end
    ') || { next_read_error "$identifier 活动时间"; return 2; }
    reason=$(jq -r --argjson activity "$activity" --argjson grace "$AUTOTEAM_WAKEUP_OVERDUE_HOURS" --argjson runs "$runs" '
      def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
      [.[] | . as $w |
        (if (.last_error // "") != "" or .last_task_status == "failed" then
           ([$runs[] | select(.id == $w.last_task_id) | .completed_at] | first) // .updated_at
         elif .timed_out_at != null then .timed_out_at
         elif .expires_at != null and (.enabled or (.fire_count // 0) == 0) and (.expires_at | epoch) < now then .expires_at
         elif .enabled and .kind != "event" and .next_fire_at != null and (.next_fire_at | epoch) < now then .next_fire_at
         else null end) as $at |
        select($at != null) | ($at | epoch) as $time |
        select($time < now - $grace * 3600 and $activity <= $time)] |
      if length > 0 then "唤醒过期、超时或触发失败后任务未推进" else empty end
    ' <<<"$wakeups") || { next_read_error "$identifier 唤醒时间"; return 2; }
    if [ -n "$reason" ]; then
      jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "$reason" '{id:$id,identifier:$identifier,category:"wakeup_overdue",reason:$reason}' >> "$NEXT_ITEMS"
    fi
    deps=$(jq -er 'if .metadata | has("autoteam.depends_on") then .metadata["autoteam.depends_on"] else "" end | if type == "string" then . else error("前提必须为字符串") end' <<<"$issue") || { next_read_error "$identifier 前提格式"; return 2; }
    waiting=""
    if [ -n "$deps" ]; then
      deps=$(jq -nr --arg deps "$deps" '$deps | split(",") | map(gsub("^\\s+|\\s+$"; "")) | if all(.[]; test("^[A-Z][A-Z0-9]*-[1-9][0-9]*$")) then unique[] else error("前提编号") end') || { next_read_error "$identifier 前提编号"; return 2; }
      while IFS= read -r key; do
        dependency=$(mc issue get "$key" --output json) || { next_read_error "$identifier 前提 $key"; return 2; }
        jq -e --arg key "$key" '.identifier == $key and (.status | type == "string")' <<<"$dependency" >/dev/null || { next_read_error "$identifier 前提 $key 格式"; return 2; }
        [ "$(jq -r '.status_category // .status' <<<"$dependency")" != "done" ] || continue
        matched=$(jq -r --arg dep "$(jq -r '.id' <<<"$dependency")" '
          def live: .enabled and (.expires_at == null or (.expires_at | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) > now);
          any(.[]; live and .condition.type == "other_issue" and
             .condition.issue_id == $dep and .condition.state == "done")' <<<"$wakeups") || { next_read_error "$identifier 依赖唤醒"; return 2; }
        [ "$matched" = true ] || waiting="$waiting$key；"
      done <<<"$deps"
    fi
    checks=false
    if grep -q -x "$id" "$NEXT_CHECKS"; then
      checks=$(jq -r 'any(.[]; .enabled and .condition.type == "pull_request" and .condition.event == "checks_finished" and
        (.expires_at == null or (.expires_at | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) > now))' <<<"$wakeups") || { next_read_error "$identifier 检查唤醒"; return 2; }
      [ "$checks" = true ] || waiting="${waiting}PR 检查；"
    fi
    if [ -n "$waiting" ]; then
      jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "等待 $waiting 但无对应启用唤醒" '{id:$id,identifier:$identifier,category:"missing_wakeup",reason:$reason}' >> "$NEXT_ITEMS"
    fi
    case $(jq -r '.status' <<<"$issue") in
      in_progress|in_review) ;;
      todo) jq -e --arg planner "$NEXT_PLANNER_ID" '.assignee_type == "agent" or .assignee_id == $planner' <<<"$issue" >/dev/null || continue ;;
      blocked) jq -e '.assignee_type == "agent"' <<<"$issue" >/dev/null || continue ;;
      *) continue ;;
    esac
    jq -e 'any(.[]; .status == "running" or .status == "queued" or .status == "dispatched" or .status == "waiting_local_directory")' <<<"$runs" >/dev/null && continue
    if jq -en --argjson at "$activity" --argjson hours "$AUTOTEAM_STALLED_HOURS" '$at < now - $hours * 3600' >/dev/null; then
      jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "超过 $AUTOTEAM_STALLED_HOURS 小时无评论、运行或状态变化" '{id:$id,identifier:$identifier,category:"stalled",reason:$reason}' >> "$NEXT_ITEMS"
    fi
  done < "$NEXT_ISSUES"
}

next_resolve() {
  local profile=$1 root projects agents rows planner_name
  root=$(repo_root)
  conf_exists "$root" || { next_read_error "配置 $AUTOTEAM_CONF_REL"; return 2; }
  conf_load "$root"
  local key
  for key in AUTOTEAM_STALLED_HOURS AUTOTEAM_WAKEUP_OVERDUE_HOURS AUTOTEAM_ACCEPT_OBSERVE_MAX_HOURS; do
    [[ ${!key} =~ ^[0-9]+$ ]] || { next_read_error "$key 配置"; return 2; }
  done
  [ -n "$AUTOTEAM_MULTICA_PROJECT" ] || { next_read_error 'AUTOTEAM_MULTICA_PROJECT 配置'; return 2; }
  command -v jq >/dev/null 2>&1 || { next_read_error 'jq 命令'; return 2; }
  # shellcheck disable=SC2034 # mc() in multica.sh reads this flag.
  MC_SYNC_ACTIVE=1
  mc_resolve_bin
  mc_resolve_profile "$profile"
  mc_resolve_workspace "$AUTOTEAM_MULTICA_WORKSPACE"
  projects=$(mc project list --output json) || { next_read_error '项目列表'; return 2; }
  NEXT_PROJECT_ID=$(jq -er --arg title "$AUTOTEAM_MULTICA_PROJECT" 'if type == "array" then [.[] | select(.title == $title)][0].id // empty else empty end' <<<"$projects") || { next_read_error '项目'; return 2; }
  rows=$(registry_agents) || return 2
  planner_name=$(awk -F '\t' '$2 == "planner" {print $1}' <<<"$rows")
  [ -n "$planner_name" ] || { next_read_error 'Planner 配置'; return 2; }
  agents=$(mc agent list --output json) || { next_read_error 'agent 列表'; return 2; }
  NEXT_PLANNER_ID=$(jq -er --arg name "$planner_name" 'if type == "array" then [.[] | select(.name == $name)][0].id // empty else empty end' <<<"$agents") || { next_read_error 'Planner agent'; return 2; }
}

next_collect() {
  local profile=$1 issue id identifier status assignee parent stage runs failure children ready reason guard
  next_resolve "$profile" || return 2
  NEXT_ISSUES="$(autoteam_tmpdir)/next-issues.jsonl"
  NEXT_ITEMS="$(autoteam_tmpdir)/next-items.jsonl"
  : > "$NEXT_ISSUES"; : > "$NEXT_ITEMS"
  NEXT_CHECKS="$(autoteam_tmpdir)/next-checks"
  : > "$NEXT_CHECKS"
  next_collect_page || return 2
  next_collect_github || return 2
  next_collect_health || return 2
  while IFS= read -r issue; do
    id=$(jq -r '.id // empty' <<<"$issue")
    identifier=$(jq -r '.identifier // empty' <<<"$issue")
    status=$(jq -r '.status // empty' <<<"$issue")
    assignee=$(jq -r '.assignee_id // empty' <<<"$issue")
    parent=$(jq -r '.parent_issue_id // empty' <<<"$issue")
    stage=$(jq -r '.stage // empty' <<<"$issue")
    [ -n "$id" ] && [ -n "$identifier" ] || { next_read_error '任务字段'; return 2; }
    case $(jq -r '.status_category // .status' <<<"$issue") in done|cancelled) continue ;; esac
    if [ "$status" = in_progress ] || [ "$status" = in_review ]; then
      guard=$(MULTICA_BIN="$MC_BIN" AUTOTEAM_MULTICA_PROFILE="$MC_PROFILE" bash "$(repo_root)/.autoteam/scripts/loop-guard.sh" "$identifier") || { next_read_error "$identifier 打转次数"; return 2; }
      jq -e 'type == "object" and (.escalate | type == "boolean") and (.reasons | type == "array") and (.notes | type == "array")' <<<"$guard" >/dev/null || { next_read_error "$identifier 打转次数格式"; return 2; }
      reason=$(jq -r 'if .escalate or (.notes | length > 0) then ((.reasons + .notes) | join("；")) else empty end' <<<"$guard")
      if [ -n "$reason" ]; then
        jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "$reason" \
          '{id:$id,identifier:$identifier,category:"loop_limit",reason:$reason}' >> "$NEXT_ITEMS"
      fi
    fi
    [ "$status" = todo ] || [ "$status" = in_progress ] || continue
    runs=$(mc issue runs "$id" --output json) || { next_read_error "$identifier 运行"; return 2; }
    jq -e 'type == "array"' <<<"$runs" >/dev/null || { next_read_error "$identifier 运行格式"; return 2; }
    failure=$(jq -r 'if (.[0].status // "") == "failed" then (.[0].error // .[0].failure_reason // "原因未知") | tostring | gsub("[\\r\\n]+"; " ") | .[0:160] else empty end' <<<"$runs") || return 2
    if [ -n "$failure" ]; then
      jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "最近一次运行失败：$failure" \
        '{id:$id,identifier:$identifier,category:"failed_run",reason:$reason}' >> "$NEXT_ITEMS"
      continue
    fi
    [ "$status" = todo ] && [ "$assignee" = "$NEXT_PLANNER_ID" ] || continue
    ready=true
    if [ -n "$parent" ] && [ -n "$stage" ]; then
      children=$(mc issue children "$parent" --output json) || { next_read_error "$identifier 前置批次"; return 2; }
      jq -e 'type == "object" and (.stages | type == "array") and all(.stages[]; (.issues | type == "array"))' <<<"$children" >/dev/null || { next_read_error "$identifier 前置批次格式"; return 2; }
      ready=$(jq -r --argjson stage "$stage" '[.stages[] | select(.stage < $stage) | .issues[] | select(.status != "done")] | length == 0' <<<"$children") || return 2
    fi
    [ "$ready" = true ] || continue
    reason=$(depends_on_reason "$id" 2) || { next_read_error "$identifier 前提"; return 2; }
    if [ -n "$reason" ]; then
      printf '%s\t%s\n' "$identifier" "$reason" >&2
      continue
    fi
    reason='已指派 Planner，前置批次及跨需求前提全部完成'
    jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "$reason" \
      '{id:$id,identifier:$identifier,category:"dispatchable",reason:$reason}' >> "$NEXT_ITEMS"
  done < "$NEXT_ISSUES"
  # 每个任务只出现一次，按最具体且最紧急的原因保留。
  jq -s 'group_by(.id) | map(sort_by(.category as $c | ["merged_unaccepted","pr_remediation","loop_limit","wakeup_overdue","missing_wakeup","failed_run","stalled","dispatchable"] | index($c))[0]) | sort_by(.identifier)' "$NEXT_ITEMS"
}

cmd_next() {
  local profile="" output=text check=0 items
  while [ $# -gt 0 ]; do
    case $1 in
      --check) check=1; shift ;;
      --output) [ $# -ge 2 ] || die '--output 需要格式'; output=$2; shift 2 ;;
      --profile) [ $# -ge 2 ] || die '--profile 需要名字'; profile=$2; shift 2 ;;
      -h|--help) next_usage; return ;;
      *) die "未知选项：$1" ;;
    esac
  done
  case $output in text|json) ;; *) die "未知输出格式：$output" ;; esac
  items=$(next_collect "$profile") || return 2
  if [ "$output" = json ]; then
    printf '%s\n' "$items"
  elif [ "$(jq 'length' <<<"$items")" = 0 ]; then
    printf '无事可做\n'
  else
    jq -r '.[] | "\(.identifier)\t\(.category)\t\(.reason)"' <<<"$items"
  fi
  [ "$check" = 0 ] || [ "$(jq 'length' <<<"$items")" = 0 ]
}
