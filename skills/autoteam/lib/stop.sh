# shellcheck shell=bash
# Emergency switch stored on this project's 运营笔记 issue in Multica.

stop_usage() {
  cat <<'EOF'
用法：autoteam stop [--apply] [--keep-run <运行 ID>] [--profile <名字>]
      autoteam resume [--apply] [--profile <名字>]
      autoteam status [--check] [--profile <名字>]

默认只预览；--apply 执行。--check 在已暂停时返回 1，供 agent 开工检查。
EOF
}

stop_setup() {
  local profile=$1 root projects issues offset=0 more=true
  root=$(repo_root)
  conf_exists "$root" || die "还没有 $AUTOTEAM_CONF_REL"
  conf_load "$root"
  [ -n "$AUTOTEAM_MULTICA_PROJECT" ] || die "AUTOTEAM_MULTICA_PROJECT 未配置"
  need_cmd jq
  # shellcheck disable=SC2034 # mc() 在 multica.sh 中读取
  MC_SYNC_ACTIVE=1
  mc_resolve_bin
  mc_resolve_profile "$profile"
  mc_resolve_workspace "$AUTOTEAM_MULTICA_WORKSPACE"
  projects=$(mc project list --output json) || die "读取项目列表失败"
  STOP_PROJECT_ID=$(jq -r --arg title "$AUTOTEAM_MULTICA_PROJECT" '[.[] | select(.title == $title)][0].id // empty' <<<"$projects")
  [ -n "$STOP_PROJECT_ID" ] || die "找不到项目 $AUTOTEAM_MULTICA_PROJECT"
  STOP_NOTE_ID=""
  while [ "$more" = true ]; do
    issues=$(mc issue list --project "$STOP_PROJECT_ID" --limit 100 --offset "$offset" --fields id,title --output json) || die "读取项目任务失败"
    STOP_NOTE_ID=$(jq -r '.issues[] | select(.title == "运营笔记") | .id' <<<"$issues" | head -n 1)
    [ -z "$STOP_NOTE_ID" ] || break
    more=$(jq -r '.has_more' <<<"$issues")
    offset=$((offset + $(jq '.issues | length' <<<"$issues")))
  done
  [ -n "$STOP_NOTE_ID" ] || die "项目没有运营笔记任务；先让 Planner 创建"
  stop_read_marker
}

stop_read_marker() {
  local issue
  issue=$(mc issue get "$STOP_NOTE_ID" --output json) || die "读取运营笔记失败"
  STOP_MARKER=$(jq -c '.metadata["autoteam.paused"] // empty' <<<"$issue")
  if [ -n "$STOP_MARKER" ]; then
    jq -e 'type == "object" and (.active_autopilots | type == "array")' <<<"$STOP_MARKER" >/dev/null || die "暂停标记格式错误，停止操作"
  fi
}

stop_agents() {
  local agents rows name _role _rest id
  rows=$(registry_agents)
  registry_validate "$rows" || die "registry.yaml 有问题"
  agents=$(mc agent list --output json) || die "读取 agent 列表失败"
  STOP_AGENT_IDS=""
  while IFS=$'\t' read -r name _role _rest; do
    [ -n "$name" ] || continue
    id=$(jq -r --arg n "$name" '[.[] | select(.name == $n)][0].id // empty' <<<"$agents")
    [ -n "$id" ] || die "registry agent $name 不在 Multica 中"
    STOP_AGENT_IDS="$STOP_AGENT_IDS $id"
  done <<<"$rows"
}

stop_runs() {
  local id tasks run_id status issue_id
  STOP_RUNS=""
  for id in $STOP_AGENT_IDS; do
    tasks=$(mc agent tasks "$id" --output json) || die "读取 agent $id 的运行失败"
    while IFS=$'\t' read -r run_id status issue_id; do
      [ -n "$run_id" ] || continue
      [ "$run_id" = "$STOP_KEEP_RUN" ] && continue
      STOP_RUNS="$STOP_RUNS$run_id"$'\t'"$status"$'\t'"$issue_id"$'\n'
    done < <(jq -r '.[] | select(.status == "running" or .status == "queued") | [.id,.status,(.issue_id // "-")] | @tsv' <<<"$tasks")
  done
}

cmd_stop() {
  local profile="" apply=0 keep="" list ids marker actor run_id _run_status _issue_id
  while [ $# -gt 0 ]; do
    case $1 in
      --apply) apply=1; shift ;;
      --keep-run) [ $# -ge 2 ] && [ -n "$2" ] || die "--keep-run 需要运行 ID"; keep=$2; shift 2 ;;
      --profile) [ $# -ge 2 ] || die "--profile 需要名字"; profile=$2; shift 2 ;;
      -h|--help) stop_usage; return ;;
      *) die "未知选项：$1" ;;
    esac
  done
  stop_setup "$profile"
  STOP_KEEP_RUN=$keep
  stop_agents
  stop_runs
  list=$(mc autopilot list --output json) || die "读取 autopilot 列表失败"
  if [ -n "$STOP_MARKER" ]; then
    ids=$(jq -c '.active_autopilots' <<<"$STOP_MARKER")
    info "已暂停；保留原始恢复列表，不覆盖标记"
  else
    ids=$(jq -c --arg p "$STOP_PROJECT_ID" '[.autopilots[] | select(.project_id == $p and .status == "active") | .id]' <<<"$list")
  fi
  info "停止前 active 的 autopilot："
  jq -r --argjson ids "$ids" '.autopilots[] | select(.id as $id | $ids | index($id)) | "  \(.title) (\(.id))"' <<<"$list"
  info "将暂停的 autopilot："
  jq -r --arg p "$STOP_PROJECT_ID" '.autopilots[] | select(.project_id == $p and .status == "active") | "  \(.title) (\(.id))"' <<<"$list"
  info "将取消的运行："
  if [ -n "$STOP_RUNS" ]; then printf '%s' "$STOP_RUNS" | tr '\t' ' '; else info "  无"; fi
  [ "$apply" = 1 ] || { info "预览完成；加 --apply 执行"; return; }
  if [ -z "$STOP_MARKER" ]; then
    actor=$(mc user profile get --output json) || die "读取操作人失败"
    marker=$(jq -nc --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson actor "$(jq -c '{id,name}' <<<"$actor")" --argjson ids "$ids" '{at:$at,operator:$actor,active_autopilots:$ids}')
    mc issue metadata set "$STOP_NOTE_ID" --key autoteam.paused --value "$marker" --output json >/dev/null || die "写入暂停标记失败"
  fi
  while IFS= read -r run_id; do
    [ -n "$run_id" ] || continue
    mc autopilot update "$run_id" --status paused --output json >/dev/null || die "暂停 autopilot $run_id 失败"
  done < <(jq -r --arg p "$STOP_PROJECT_ID" '.autopilots[] | select(.project_id == $p and .status == "active") | .id' <<<"$list")
  while IFS=$'\t' read -r run_id _run_status _issue_id; do
    [ -n "$run_id" ] || continue
    mc issue cancel-task "$run_id" --output json >/dev/null || die "取消运行 $run_id 失败"
  done <<<"$STOP_RUNS"
  info "已停止本项目"
}

cmd_resume() {
  local profile="" apply=0 id list
  while [ $# -gt 0 ]; do
    case $1 in
      --apply) apply=1; shift ;;
      --profile) [ $# -ge 2 ] || die "--profile 需要名字"; profile=$2; shift 2 ;;
      -h|--help) stop_usage; return ;;
      *) die "未知选项：$1" ;;
    esac
  done
  stop_setup "$profile"
  [ -n "$STOP_MARKER" ] || { info "项目未暂停，无需恢复"; return; }
  list=$(mc autopilot list --output json) || die "读取 autopilot 列表失败"
  info "将恢复的 autopilot："
  jq -r --arg p "$STOP_PROJECT_ID" --argjson ids "$(jq -c '.active_autopilots' <<<"$STOP_MARKER")" '.autopilots[] | select(.project_id == $p and .status == "paused") | select(.id as $id | $ids | index($id)) | "  \(.title) (\(.id))"' <<<"$list"
  [ "$apply" = 1 ] || { info "预览完成；加 --apply 执行"; return; }
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    mc autopilot update "$id" --status active --output json >/dev/null || die "恢复 autopilot $id 失败；标记保留供重试"
  done < <(jq -r --arg p "$STOP_PROJECT_ID" --argjson ids "$(jq -c '.active_autopilots' <<<"$STOP_MARKER")" '.autopilots[] | select(.project_id == $p and .status == "paused") | select(.id as $id | $ids | index($id)) | .id' <<<"$list")
  mc issue metadata delete "$STOP_NOTE_ID" --key autoteam.paused --output json >/dev/null || die "恢复成功，但清除暂停标记失败；请重试"
  info "已恢复本项目；取消的运行不会自动重跑"
}

cmd_status() {
  local profile="" check=0
  while [ $# -gt 0 ]; do
    case $1 in
      --check) check=1; shift ;;
      --profile) [ $# -ge 2 ] || die "--profile 需要名字"; profile=$2; shift 2 ;;
      -h|--help) stop_usage; return ;;
      *) die "未知选项：$1" ;;
    esac
  done
  stop_setup "$profile"
  if [ -n "$STOP_MARKER" ]; then
    info "已暂停：$(jq -r '.at' <<<"$STOP_MARKER")，操作人 $(jq -r '.operator.name' <<<"$STOP_MARKER")"
    [ "$check" = 0 ] || return 1
  else
    info "运行中：未暂停"
  fi
}
