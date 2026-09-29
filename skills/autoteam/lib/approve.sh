# shellcheck shell=bash
# 一次放行一个父任务下所有 backlog 的子任务：只有第一个可派发批次的一个任务会叫醒 Planner。

approve_usage() {
  cat <<'EOF'
用法：autoteam approve <父任务> [--apply] [--profile <名字>]

把父任务下所有指派给 Planner、状态为 backlog 的子任务改成 todo（放行）。默认只预览；--apply 执行。
- 第一个可派发的批次（前面批次的任务都已 done）：只有其中一个任务的状态变更会叫醒 Planner，
  其余带 --no-start，避免同一批叫醒多次；
- 后续批次一律带 --no-start，由批次屏障在前一批完成后叫醒 Planner；
- 执行后核对那个任务的运行已生成（multica issue runs），没生成就报错并给出补救办法。
EOF
}

# 输出每行：任务 ID、编号、批次（无批次为 0）、start|quiet。start 至多一行，且排在最后。
approve_plan() {
  jq -r --arg planner "$1" '
    ([.stages[] | .stage as $s | .issues[] | . + {stage: $s}] + [(.unstaged // [])[] | . + {stage: 0}]) as $all
    | [$all[] | select(.status == "backlog" and .assignee_id == $planner)] | sort_by(.stage) as $cands
    | if ($cands | length) == 0 then empty else
        $cands[0].stage as $first
        | ([$all[] | select(.stage > 0 and .stage < $first and .status != "done")] | length == 0) as $open
        | $cands | to_entries
        | (map(select(.key > 0 or ($open | not))) + map(select(.key == 0 and $open)))[]
        | [.value.id, .value.identifier, .value.stage, (if .key == 0 and $open then "start" else "quiet" end)]
      end
    | @tsv' <<<"$2"
}

approve_set_todo() { # <任务 ID> <编号> [--no-start]
  local out
  if out=$(mc issue status "$1" todo "${@:3}" 2>&1); then
    printf '%s\t已放行\n' "$2"
  else
    printf '%s\t失败：%s\n' "$2" "$(tr '\n' ' ' <<<"$out" | cut -c1-160)"
    return 1
  fi
}

approve_run_count() { mc issue runs "$1" --output json | jq -e 'if type == "array" then length else empty end'; }

cmd_approve() {
  local parent="" apply=0 profile="" children plan id ident stage mode start_id="" start_ident="" before after failed=0
  while [ $# -gt 0 ]; do
    case $1 in
      --apply) apply=1; shift ;;
      --profile) [ $# -ge 2 ] || die '--profile 需要名字'; profile=$2; shift 2 ;;
      -h|--help) approve_usage; return ;;
      -*) die "未知选项：$1" ;;
      *) [ -z "$parent" ] || die "多余的参数：$1"; parent=$1; shift ;;
    esac
  done
  [ -n "$parent" ] || { approve_usage >&2; die '需要父任务'; }
  next_resolve "$profile" || return 2
  children=$(mc issue children "$parent" --output json) || die "读取 $parent 的子任务失败"
  jq -e 'type == "object" and (.stages | type == "array") and all(.stages[]; (.issues | type == "array"))' <<<"$children" >/dev/null || die "$parent 的子任务格式不对"
  plan=$(approve_plan "$NEXT_PLANNER_ID" "$children") || die "解析 $parent 的子任务失败"
  [ -n "$plan" ] || { info "$parent 下没有指派给 Planner 的 backlog 子任务"; return; }
  while IFS=$'\t' read -r id ident stage mode; do
    if [ "$mode" = start ]; then
      start_id=$id; start_ident=$ident
    elif [ "$apply" = 1 ]; then
      approve_set_todo "$id" "$ident" --no-start || failed=1
    fi
    if [ "$apply" != 1 ]; then
      printf '%s\t第 %s 批\t将改为 todo%s\n' "$ident" "$stage" "$([ "$mode" = start ] && echo '（叫醒 Planner）' || echo '（--no-start）')"
    fi
  done <<<"$plan"
  [ "$apply" = 1 ] || { info "预览完成；加 --apply 执行"; return; }
  if [ "$failed" != 0 ]; then
    printf 'autoteam approve：有任务放行失败，未叫醒 Planner（批次尚未全部获批）。处理失败原因后重跑 autoteam approve --apply；已放行的不会重复处理。\n' >&2
    return 1
  fi
  if [ -z "$start_id" ]; then
    info "没有可立即派发的批次，Planner 不会被叫醒；前面批次完成后由批次屏障叫醒"
    return
  fi
  # 会叫醒 Planner 的那个排在最后放行，Planner 醒来时整个拆分都已是 todo。
  before=$(approve_run_count "$start_id") || die "读取 $start_ident 的运行失败"
  approve_set_todo "$start_id" "$start_ident" || return 1
  after=$before
  for _ in 1 2 3 4 5; do
    after=$(approve_run_count "$start_id") || die "读取 $start_ident 的运行失败"
    [ "$after" -gt "$before" ] && break
    sleep "${AUTOTEAM_APPROVE_WAIT:-2}"
  done
  if [ "$after" -le "$before" ]; then
    printf 'autoteam approve：%s 已改为 todo，但 Planner 的运行没有生成。补救：在 %s 下评论并 @Planner 叫醒一次；其余任务已放行，不必重做。\n' "$start_ident" "$start_ident" >&2
    return 1
  fi
  info "$start_ident：Planner 的运行已生成"
}
