# shellcheck shell=bash
# Read-only Multica and GitHub patrol queue.

next_usage() {
  cat <<'EOF'
用法：autoteam next [--check] [--output json] [--profile <名字>]

列出待派发、失败运行、已合并未验收、待补救 PR 和打转到上限的任务。
--check：空清单打印「无事可做」并返回 0；有事返回 1；读取失败返回 2。
EOF
}

next_read_error() { printf 'autoteam next：读取%s失败\n' "$1" >&2; return 2; }

next_collect_page() {
  local offset=0 page count more
  while :; do
    page=$(mc issue list --project "$NEXT_PROJECT_ID" --limit 100 --offset "$offset" \
      --fields id,identifier,status,assignee_type,assignee_id,parent_issue_id,stage --output json) || { next_read_error '任务'; return 2; }
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
  local merged open pr number identifier merged_at status reason hours id
  local -A seen=()
  command -v gh >/dev/null 2>&1 || { next_read_error 'gh 命令'; return 2; }
  [ -n "$AUTOTEAM_REPO" ] && [ -n "$AUTOTEAM_ISSUE_PREFIX" ] || { next_read_error 'GitHub 仓库或任务前缀配置'; return 2; }
  hours=$AUTOTEAM_ACCEPT_RECHECK_HOURS
  [[ $hours =~ ^[0-9]+$ ]] || { next_read_error 'AUTOTEAM_ACCEPT_RECHECK_HOURS 配置'; return 2; }
  merged=$(gh pr list --repo "$AUTOTEAM_REPO" --state merged --limit 100 --json number,title,mergedAt) || { next_read_error '已合并 PR'; return 2; }
  jq -e 'type == "array" and all(.[]; (.number | type == "number") and (.title | type == "string") and (.mergedAt | type == "string"))' <<<"$merged" >/dev/null || { next_read_error '已合并 PR 格式'; return 2; }
  while IFS= read -r pr; do
    identifier=$(jq -r --arg prefix "$AUTOTEAM_ISSUE_PREFIX" '.title | (capture("^(?<key>" + $prefix + "-[0-9]+)([^0-9]|$)")? | .key) // empty' <<<"$pr")
    [ -n "$identifier" ] || continue
    [ -z "${seen[$identifier]:-}" ] || continue
    seen[$identifier]=1
    status=$(jq -r --arg key "$identifier" 'select(.identifier == $key) | .status' "$NEXT_ISSUES")
    [ -n "$status" ] && [ "$status" != 'done' ] && [ "$status" != cancelled ] || continue
    id=$(jq -r --arg key "$identifier" 'select(.identifier == $key) | .id' "$NEXT_ISSUES")
    merged_at=$(jq -r '.mergedAt' <<<"$pr")
    if ! jq -en --arg at "$merged_at" --argjson hours "$hours" '($at | fromdateiso8601) < (now - $hours * 3600)' >/dev/null; then
      jq -en --arg at "$merged_at" '$at | fromdateiso8601' >/dev/null || { next_read_error '合并时间格式'; return 2; }
      continue
    fi
    number=$(jq -r '.number' <<<"$pr")
    jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "PR #$number 已合并超过 $hours 小时，任务仍为 $status" \
      '{id:$id,identifier:$identifier,category:"merged_unaccepted",reason:$reason}' >> "$NEXT_ITEMS"
  done < <(jq -c 'sort_by(.mergedAt) | reverse | .[]' <<<"$merged")

  open=$(gh pr list --repo "$AUTOTEAM_REPO" --state open --limit 100 --json number,title,reviewDecision,statusCheckRollup,mergeable) || { next_read_error '开放 PR'; return 2; }
  jq -e 'type == "array" and all(.[]; (.number | type == "number") and (.title | type == "string") and (.statusCheckRollup | type == "array") and (.mergeable | type == "string"))' <<<"$open" >/dev/null || { next_read_error '开放 PR 格式'; return 2; }
  while IFS= read -r pr; do
    identifier=$(jq -r --arg prefix "$AUTOTEAM_ISSUE_PREFIX" '.title | (capture("^(?<key>" + $prefix + "-[0-9]+)([^0-9]|$)")? | .key) // empty' <<<"$pr")
    [ -n "$identifier" ] || continue
    id=$(jq -r --arg key "$identifier" 'select(.identifier == $key) | .id' "$NEXT_ISSUES")
    [ -n "$id" ] || continue
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

next_resolve() {
  local profile=$1 root projects agents rows planner_name
  root=$(repo_root)
  conf_exists "$root" || { next_read_error "配置 $AUTOTEAM_CONF_REL"; return 2; }
  conf_load "$root"
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
  next_collect_page || return 2
  while IFS= read -r issue; do
    id=$(jq -r '.id // empty' <<<"$issue")
    identifier=$(jq -r '.identifier // empty' <<<"$issue")
    status=$(jq -r '.status // empty' <<<"$issue")
    assignee=$(jq -r '.assignee_id // empty' <<<"$issue")
    parent=$(jq -r '.parent_issue_id // empty' <<<"$issue")
    stage=$(jq -r '.stage // empty' <<<"$issue")
    [ -n "$id" ] && [ -n "$identifier" ] || { next_read_error '任务字段'; return 2; }
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
    reason='已指派 Planner，前置批次全部完成'
    jq -nc --arg id "$id" --arg identifier "$identifier" --arg reason "$reason" \
      '{id:$id,identifier:$identifier,category:"dispatchable",reason:$reason}' >> "$NEXT_ITEMS"
  done < "$NEXT_ISSUES"
  next_collect_github || return 2
  jq -s '.' "$NEXT_ITEMS"
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
