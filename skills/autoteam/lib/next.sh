# shellcheck shell=bash
# Read-only Multica work queue. Later patrol sources can append items to the NDJSON file.

next_usage() {
  cat <<'EOF'
用法：autoteam next [--check] [--output json] [--profile <名字>]

列出 Planner 可派发的 todo，以及最近一次运行失败的 todo / in_progress。
--check：空清单打印「无事可做」并返回 0；有事返回 1；读取失败返回 2。
EOF
}

next_read_error() { printf 'autoteam next：读取%s失败\n' "$1" >&2; return 2; }

next_collect_page() {
  local status=$1 offset=0 page count more
  while :; do
    page=$(mc issue list --project "$NEXT_PROJECT_ID" --status "$status" --limit 100 --offset "$offset" \
      --fields id,identifier,status,assignee_type,assignee_id,parent_issue_id,stage --output json) || { next_read_error "${status} 任务"; return 2; }
    jq -e 'type == "object" and (.issues | type == "array") and (.has_more | type == "boolean")' <<<"$page" >/dev/null || { next_read_error "${status} 任务格式"; return 2; }
    jq -c '.issues[]' <<<"$page" >> "$NEXT_ISSUES" || return 2
    more=$(jq -r '.has_more' <<<"$page")
    [ "$more" = true ] || break
    count=$(jq '.issues | length' <<<"$page")
    [ "$count" -gt 0 ] || { next_read_error "${status} 分页"; return 2; }
    offset=$((offset + count))
  done
}

next_collect() {
  local profile=$1 root projects agents rows planner_name issue id identifier status assignee parent stage runs failure children ready reason
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
  NEXT_ISSUES="$(autoteam_tmpdir)/next-issues.jsonl"
  NEXT_ITEMS="$(autoteam_tmpdir)/next-items.jsonl"
  : > "$NEXT_ISSUES"; : > "$NEXT_ITEMS"
  next_collect_page todo || return 2
  next_collect_page in_progress || return 2
  while IFS= read -r issue; do
    id=$(jq -r '.id // empty' <<<"$issue")
    identifier=$(jq -r '.identifier // empty' <<<"$issue")
    status=$(jq -r '.status // empty' <<<"$issue")
    assignee=$(jq -r '.assignee_id // empty' <<<"$issue")
    parent=$(jq -r '.parent_issue_id // empty' <<<"$issue")
    stage=$(jq -r '.stage // empty' <<<"$issue")
    [ -n "$id" ] && [ -n "$identifier" ] || { next_read_error '任务字段'; return 2; }
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
