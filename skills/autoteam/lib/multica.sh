# shellcheck shell=bash
# autoteam multica / autoteam runtimes：旧状态迁移、agent、项目、autopilot、部署 webhook。默认只预览。

multica_usage() {
  cat <<'EOF'
用法：autoteam multica [选项]

按 .autoteam/ 下的文件配置 Multica 工作区。默认只预览，加 --apply 才执行。

  --apply                 执行改动
  --profile <名字>        multica CLI 的 profile（默认：环境变量 MULTICA_SERVER_URL + MULTICA_TOKEN，
                          否则已配置的默认 profile，再否则 ~/.multica/profiles 下唯一的 profile；也可用 AUTOTEAM_MULTICA_PROFILE）
  --workspace <slug|ID>   工作区（默认 autoteam.conf 的 AUTOTEAM_MULTICA_WORKSPACE）
  --only <部分>           只处理其中几部分，逗号分隔：statuses,agents,project,autopilots
  --paused                新建的 autopilot 立即暂停（先配好、以后再启用）
  --rotate-webhook        重新生成部署 webhook 地址并写入 GitHub secret

会做的事：
  1. 将旧 shipping 任务迁回 in_review，再归档该状态（这一步需要工作区 owner 或 admin）
  2. 按 registry.yaml 创建或更新 agent，指令优先取 .autoteam/instructions/roles/<角色>.md
     （autoteam eject 落盘的那份），没有就用 autoteam 包内的
  3. 项目（AUTOTEAM_MULTICA_PROJECT），挂上 GitHub 仓库资源并创建运营笔记
  4. 按 autopilot 指令（包内的，加上 .autoteam/instructions/autopilots/ 里 eject 的，同名以后者为准）
     创建或更新 autopilot 和触发器，定时频率取 autoteam.conf 的 AUTOTEAM_CRON_*；
     部署 webhook 地址写进 GitHub secret MULTICA_DEPLOY_HOOK
EOF
}

MC_APP_BIN=/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica

mc_resolve_bin() {
  [ -n "${MC_BIN:-}" ] && return 0
  if [ -n "${AUTOTEAM_MULTICA_BIN:-}" ]; then
    MC_BIN=$AUTOTEAM_MULTICA_BIN
  elif command -v multica >/dev/null 2>&1; then
    MC_BIN=$(command -v multica)
  elif [ -x "$MC_APP_BIN" ]; then
    MC_BIN=$MC_APP_BIN
  else
    die "找不到 multica CLI。安装：brew install multica-ai/tap/multica"
  fi
}

# profile：参数 > AUTOTEAM_MULTICA_PROFILE > 环境变量 MULTICA_SERVER_URL + MULTICA_TOKEN（agent runtime，CLI 自己读）
# > 已配置的默认 profile > ~/.multica/profiles 下唯一的 profile
mc_resolve_profile() {
  local config_out dirs n cfg
  MC_PROFILE=${1:-${AUTOTEAM_MULTICA_PROFILE:-}}
  MC_ARGS=()
  if [ -z "$MC_PROFILE" ] && [ -n "${MULTICA_SERVER_URL:-}" ] && [ -n "${MULTICA_TOKEN:-}" ]; then
    :
  elif [ -z "$MC_PROFILE" ]; then
    config_out=$("$MC_BIN" config show 2>/dev/null) || config_out=""
    if ! grep -Eq '^server_url:[[:space:]]+https?://' <<<"$config_out"; then
      dirs=$(ls -1 "$HOME/.multica/profiles" 2>/dev/null || true)
      n=$(printf '%s\n' "$dirs" | grep -c . || true)
      if [ "$n" = 1 ]; then
        MC_PROFILE=$dirs
      else
        cfg=$(sed -n 's/^Config file:[[:space:]]*//p' <<<"$config_out")
        if [ -z "${MULTICA_TOKEN:-}" ] && [ -z "$dirs" ] && { [ -z "$cfg" ] || [ ! -f "$cfg" ]; }; then
          die "multica 还没登录：先运行 multica login，再运行 autoteam multica"
        fi
        die "multica 默认 profile 没有配置服务器：用 --profile 指定，或先运行 multica setup。现有 profile：$(printf '%s' "$dirs" | tr '\n' ' ')"
      fi
    fi
  fi
  if [ -n "$MC_PROFILE" ]; then
    MC_ARGS=(--profile "$MC_PROFILE")
  fi
}

mc_require_login() {
  local config_out cfg
  if [ -z "${MULTICA_TOKEN:-}" ]; then
    config_out=$("$MC_BIN" ${MC_ARGS[@]+"${MC_ARGS[@]}"} config show 2>/dev/null) || config_out=""
    cfg=$(sed -n 's/^Config file:[[:space:]]*//p' <<<"$config_out")
    if [ -z "$cfg" ] || [ ! -f "$cfg" ] || [ -z "$(jq -r '.token // empty' "$cfg" 2>/dev/null)" ]; then
      die "multica 还没登录：先运行 multica login（使用其他 profile 时加 --profile）"
    fi
  fi
}

mc() {
  local attempts=1 attempt=1 rc out
  if [ "${MC_SYNC_ACTIVE:-0}" = 1 ]; then
    case "${1:-} ${2:-} ${3:-}" in
      "workspace get "*|"runtime list "*|"agent list "*|"agent get "*|"agent tasks "*|"issue list "*|"issue get "*|"project list "*|"project resource list"|"autopilot list "*|"autopilot get "*|"user profile get") attempts=3 ;;
    esac
  fi
  if [ "$attempts" = 1 ]; then
    "$MC_BIN" ${MC_ARGS[@]+"${MC_ARGS[@]}"} "$@"
    return $?
  fi
  out=$(mktemp "$(autoteam_tmpdir)/mc-read.XXXXXX")
  while :; do
    if "$MC_BIN" ${MC_ARGS[@]+"${MC_ARGS[@]}"} "$@" >"$out"; then
      cat "$out"
      return 0
    else
      rc=$?
    fi
    [ "$attempt" -lt "$attempts" ] || { cat "$out"; return "$rc"; }
    attempt=$((attempt + 1))
    printf 'Multica 读取失败，重试 %s/%s\n' "$attempt" "$attempts" >&2
  done
}

# CLI 接受秒数或 Go duration；curl 只接受秒数。无效值直接报错，避免无限等待。
mc_timeout_seconds() {
  LC_ALL=C awk -v value="${MULTICA_HTTP_TIMEOUT:-30s}" '
    BEGIN {
      if (value ~ /^[+]?[0-9]+([.][0-9]+)?$/) total = value + 0
      else {
        sub(/^[+]/, "", value)
        while (length(value)) {
          if (!match(value, /^([0-9]+([.][0-9]*)?|[.][0-9]+)(ns|us|µs|μs|ms|s|m|h)/)) exit 1
          part = substr(value, 1, RLENGTH)
          value = substr(value, RLENGTH + 1)
          unit = part; sub(/^[0-9.]+/, "", unit)
          factor = (unit == "h" ? 3600 : unit == "m" ? 60 : unit == "s" ? 1 : unit == "ms" ? .001 : unit == "ns" ? .000000001 : .000001)
          total += (part + 0) * factor
        }
      }
      if (total <= 0) exit 1
      printf "%.9f\n", total
    }'
}

# EXIT 汇总也覆盖 die / set -e 的提前退出；保留公共临时文件清理。
multica_sync_exit() {
  local rc=$1 part completed="" pending="" failed=$MC_SYNC_FAILED
  [ -z "$MC_SYNC_CURRENT" ] || failed="$failed $MC_SYNC_CURRENT"
  trap - EXIT
  if [ "$rc" -ne 0 ] || [ "$AUTOTEAM_ERRORS" -gt 0 ]; then
    for part in $MC_SYNC_PARTS; do
      case " $MC_SYNC_DONE " in
        *" $part "*) completed="$completed $part" ;;
        *) case " $MC_SYNC_STARTED " in *" $part "*) ;; *) pending="$pending $part" ;; esac ;;
      esac
    done
    section "同步不完整"
    info "已完成：${completed:-无}"
    info "失败或部分完成：${failed:-无}"
    info "未执行：${pending:-无}"
    info "已写入的改动不会回滚；修复错误后重新运行同步。"
    rc=1
  fi
  rm -rf "$AUTOTEAM_TMP"
  exit "$rc"
}

multica_sync_begin() {
  MC_SYNC_CURRENT=$1
  MC_SYNC_STARTED="$MC_SYNC_STARTED $1"
  MC_SYNC_ERRORS=$AUTOTEAM_ERRORS
}

multica_sync_end() {
  if [ "$AUTOTEAM_ERRORS" -eq "$MC_SYNC_ERRORS" ]; then
    MC_SYNC_DONE="$MC_SYNC_DONE $MC_SYNC_CURRENT"
  else
    MC_SYNC_FAILED="$MC_SYNC_FAILED $MC_SYNC_CURRENT"
  fi
  MC_SYNC_CURRENT=""
}

# 工作区 slug / 前缀 / UUID → 工作区 JSON
mc_resolve_workspace() {
  local ws=$1 json
  if [ -z "$ws" ]; then
    ws=$(mc config show 2>/dev/null | sed -n 's/^workspace_id:[[:space:]]*//p' | grep -v '(not set)' || true)
  fi
  [ -n "$ws" ] || die "没有指定 Multica 工作区：在 autoteam.conf 写 AUTOTEAM_MULTICA_WORKSPACE，或用 --workspace"
  json=$(mc workspace get "$ws" --output json 2>&1) || die "找不到工作区 $ws：$json"
  MC_WS_ID=$(jq -r '.id' <<<"$json")
  MC_WS_NAME=$(jq -r '.name' <<<"$json")
  MC_WS_SLUG=$(jq -r '.slug // empty' <<<"$json")
  MC_WS_PREFIX=$(jq -r '.issue_prefix // empty' <<<"$json")
  MC_ARGS+=(--workspace-id "$MC_WS_ID")
}

# init 用：只取工作区的任务编号前缀
mc_workspace_prefix() {
  mc_resolve_bin
  mc_resolve_profile ""
  mc workspace get "$1" --output json | jq -r '.issue_prefix // empty'
}

# API 凭据：MULTICA_TOKEN / MULTICA_SERVER_URL 优先，否则读 profile 的配置文件
mc_resolve_api() {
  local cfg
  cfg=$(mc config show 2>/dev/null | sed -n 's/^Config file:[[:space:]]*//p')
  MC_SERVER=${MULTICA_SERVER_URL:-}
  MC_TOKEN=${MULTICA_TOKEN:-}
  if [ -n "$cfg" ] && [ -f "$cfg" ]; then
    [ -n "$MC_SERVER" ] || MC_SERVER=$(jq -r '.server_url // empty' "$cfg")
    [ -n "$MC_TOKEN" ] || MC_TOKEN=$(jq -r '.token // empty' "$cfg")
  fi
  MC_SERVER=${MC_SERVER%/}
}

# config show 提供 app_url；未单独配置时按 API 主机推导网页主机。
mc_print_links() {
  local config_out app_url server
  [ -n "${MC_WS_SLUG:-}" ] || return 0
  config_out=$(mc config show 2>/dev/null) || return 0
  app_url=$(sed -n 's/^app_url:[[:space:]]*//p' <<<"$config_out" | tail -n 1)
  case $app_url in http://*|https://*) ;; *) app_url="" ;; esac
  if [ -z "$app_url" ]; then
    mc_resolve_api
    server=$MC_SERVER
    case $server in
      http://api.*) app_url="http://${server#http://api.}" ;;
      https://api.*) app_url="https://${server#https://api.}" ;;
      *) app_url=$server ;;
    esac
  fi
  [ -n "$app_url" ] || return 0
  app_url=${app_url%/}
  info "Multica 网页：agents $app_url/$MC_WS_SLUG/agents"
  info "             autopilots $app_url/$MC_WS_SLUG/autopilots"
  info "             项目看板 $app_url/$MC_WS_SLUG/projects"
}

# 调 Multica HTTP API；token 通过 stdin 交给 curl，不出现在进程参数里
mc_api() {
  local attempt=1 attempts=1
  if [ "${MC_SYNC_ACTIVE:-0}" = 1 ] && [ "$1" = GET ]; then attempts=3; fi
  while :; do
    if mc_api_once "$@"; then return 0; fi
    [ "$attempt" -lt "$attempts" ] || return 1
    attempt=$((attempt + 1))
    printf 'Multica API 读取失败，重试 %s/%s\n' "$attempt" "$attempts" >&2
  done
}

mc_api_once() {
  local method=$1 path=$2 body=${3:-} tmp code timeout data_args=()
  timeout=$(mc_timeout_seconds) || { MC_API_OUT="MULTICA_HTTP_TIMEOUT 无效"; return 1; }
  tmp=$(autoteam_tmpdir)
  if [ -n "$body" ]; then
    printf '%s' "$body" > "$tmp/mc-body.json"
    data_args=(--data-binary "@$tmp/mc-body.json")
  fi
  : > "$tmp/mc-resp.json"
  code=$(printf 'header = "Authorization: Bearer %s"\nheader = "X-Workspace-ID: %s"\n' "$MC_TOKEN" "$MC_WS_ID" \
    | curl -sS --max-time "$timeout" -K - -X "$method" -H 'Content-Type: application/json' -o "$tmp/mc-resp.json" -w '%{http_code}' \
        ${data_args[@]+"${data_args[@]}"} "$MC_SERVER$path" 2>"$tmp/mc-err") || code=000
  MC_API_OUT=$(cat "$tmp/mc-resp.json" 2>/dev/null || cat "$tmp/mc-err" 2>/dev/null || true)
  [ -s "$tmp/mc-resp.json" ] || MC_API_OUT=$(cat "$tmp/mc-err")
  case $code in 2??) return 0 ;; *) MC_API_OUT="HTTP $code $MC_API_OUT"; return 1 ;; esac
}

multica_setup() {
  mc_resolve_bin
  mc_resolve_profile "$1"
  mc_require_login
  mc_resolve_workspace "$2"
  info "multica：$MC_BIN（$("$MC_BIN" version 2>/dev/null | head -n1)）"
  info "profile：${MC_PROFILE:-默认}，工作区：$MC_WS_NAME（任务前缀 ${MC_WS_PREFIX:-?}）"
}

cmd_multica() {
  local profile="" ws="" only="" paused=0 rotate=0
  while [ $# -gt 0 ]; do
    case $1 in
      --apply) AUTOTEAM_APPLY=1; shift ;;
      --profile) profile=$2; shift 2 ;;
      --workspace) ws=$2; shift 2 ;;
      --only) only=",$2,"; shift 2 ;;
      --paused) paused=1; shift ;;
      --rotate-webhook) rotate=1; shift ;;
      -h|--help) multica_usage; return 0 ;;
      *) multica_usage >&2; die "未知选项：$1" ;;
    esac
  done
  MC_SYNC_ACTIVE=1 MC_SYNC_STARTED="" MC_SYNC_DONE="" MC_SYNC_FAILED="" MC_SYNC_CURRENT=连接
  MC_SYNC_PARTS=""
  multica_want() { [ -z "$only" ] || case $only in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
  local part
  for part in statuses agents project autopilots; do
    if multica_want "$part" || { [ "$part" = project ] && multica_want autopilots; }; then
      MC_SYNC_PARTS="$MC_SYNC_PARTS $part"
    fi
  done
  trap 'multica_sync_exit "$?"' EXIT
  mc_timeout_seconds >/dev/null || die "MULTICA_HTTP_TIMEOUT 必须是正秒数或 Go duration（如 45s、2m）"
  need_cmd jq
  need_cmd curl
  local root rows
  root=$(repo_root)
  cd "$root" || die "进不去 $root"
  conf_exists "$root" || die "还没有 $AUTOTEAM_CONF_REL，先运行 autoteam init"
  conf_load "$root"
  rows=$(registry_agents)
  registry_validate "$rows" || die "registry.yaml 有问题，改好后重试"

  section "连接 Multica"
  multica_setup "$profile" "${ws:-$AUTOTEAM_MULTICA_WORKSPACE}"

  if multica_want statuses; then
    section "旧状态迁移"
    multica_sync_begin statuses
    multica_migrate_shipping
    multica_sync_end
  fi
  local runtimes
  if multica_want agents; then
    section "agent"
    multica_sync_begin agents
    runtimes=$(mc runtime list --output json) || die "读取 runtime 列表失败"
    multica_agents "$rows" "$runtimes"
    multica_sync_end
  fi
  MC_PROJECT_ID=""
  if multica_want project || multica_want autopilots; then
    section "项目"
    multica_sync_begin project
    multica_project
    multica_sync_end
  fi
  if multica_want autopilots; then
    section "autopilot"
    multica_sync_begin autopilots
    multica_autopilots "$rows" "$paused" "$rotate"
    multica_sync_end
  fi

  section "需要你在 Multica 界面里做的事"
  info "GitHub 集成（可选）：Settings → GitHub 连接仓库后，任务卡片上能看到关联 PR 和 CI 状态"
  preview_footer
  mc_print_links
}

# ---------- 旧状态迁移 ----------

# 读完 issue list 的全部页：$1 是对每页 JSON 应用的 jq 程序（jq -r 输出），其余参数原样传给 issue list。
# 真实 JSON 是 {issues:[...],has_more:bool}，每页最多 100 条；has_more 为真却拿到空页会永远翻不完，直接失败。
mc_issue_pages() {
  local filter=$1 offset=0 page size
  shift
  while :; do
    page=$(mc issue list "$@" --limit 100 --offset "$offset" --output json) || return 1
    jq -e '.issues | type == "array"' <<<"$page" >/dev/null || return 1
    jq -r "$filter" <<<"$page" || return 1
    [ "$(jq -r '.has_more' <<<"$page")" = true ] || break
    size=$(jq '.issues | length' <<<"$page")
    [ "$size" -gt 0 ] || return 1
    offset=$((offset + size))
  done
}

# 先收齐各页，再写状态；边翻页边迁移会让 offset 跳过任务。
mc_shipping_issues() {
  mc_issue_pages '.issues[] | {id,identifier,title} | tojson' --status shipping --fields id,identifier,title
}

multica_migrate_shipping() {
  mc_resolve_api
  if [ -z "$MC_TOKEN" ] || [ -z "$MC_SERVER" ]; then
    fail "读不到 multica 的登录 token，不能归档旧状态"
    return 0
  fi
  if ! mc_api GET /api/issue-statuses; then
    fail "读取状态列表失败：$MC_API_OUT"
    return 0
  fi
  local entry id issues issue issue_id label failed=0
  entry=$(jq -c '[.statuses[] | select(.key == "shipping" and (.archived_at // null) == null)][0] // empty' <<<"$MC_API_OUT")
  [ -n "$entry" ] || { ok "旧状态 shipping 不存在或已归档"; return 0; }
  id=$(jq -r '.id // empty' <<<"$entry")
  [ -n "$id" ] || { fail "旧状态 shipping 没有 API id，无法归档"; return 0; }
  issues=$(mc_shipping_issues) || { fail "读取 shipping 任务失败；为安全起见未归档"; return 0; }
  while IFS= read -r issue; do
    [ -n "$issue" ] || continue
    issue_id=$(jq -r '.id' <<<"$issue")
    label=$(jq -r '"\(.identifier // .id) \(.title)"' <<<"$issue")
    planned "迁移 $label：shipping → in_review"
    [ "$AUTOTEAM_APPLY" = 1 ] || continue
    if mc issue status "$issue_id" in_review --no-start >/dev/null; then
      ok "已迁移 $label"
    else
      fail "迁移 $label 失败；未归档 shipping"
      failed=1
    fi
  done <<<"$issues"
  [ "$failed" = 0 ] || return 0
  planned "归档旧状态 shipping"
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  if mc_api DELETE "/api/issue-statuses/$id"; then
    ok "已归档旧状态 shipping"
  else
    fail "归档旧状态 shipping 失败：$MC_API_OUT"
  fi
}

# ---------- runtime ----------

# 把 provider@设备 或 runtime ID 解析成 runtime ID；找不到返回 1
mc_runtime_id() {
  local runtimes=$1 sel=$2 provider device
  if jq -e --arg id "$sel" '.[] | select(.id == $id)' <<<"$runtimes" >/dev/null 2>&1; then
    printf '%s' "$sel"; return 0
  fi
  case $sel in *@*) ;; *) return 1 ;; esac
  provider=$(lower "${sel%%@*}") device=${sel#*@}
  jq -r --arg p "$provider" --arg d "$device" \
    '[.[] | select((.provider | ascii_downcase) == $p and (.name | endswith("(" + $d + ")")))][0].id // empty' <<<"$runtimes" | grep .
}

mc_runtime_selectors() {
  jq -r '.[] | ((.name | capture("\\((?<d>[^()]*)\\)$").d) // "?") as $d
    | "\(.provider | ascii_downcase)@\($d)\t\(.status)\t\(.id)\t\(.name)"' <<<"$1"
}

runtimes_usage() {
  cat <<'EOF'
用法：autoteam runtimes [--profile <名字>] [--workspace <slug>]

列出工作区里的 runtime。registry.yaml 的 runtime 字段写第一列（provider@设备），也可以直接写 ID。
EOF
}

cmd_runtimes() {
  local profile="" ws=""
  while [ $# -gt 0 ]; do
    case $1 in
      --profile) profile=$2; shift 2 ;;
      --workspace) ws=$2; shift 2 ;;
      -h|--help) runtimes_usage; return 0 ;;
      *) runtimes_usage >&2; die "未知选项：$1" ;;
    esac
  done
  need_cmd jq
  if git rev-parse --show-toplevel >/dev/null 2>&1 && conf_exists; then conf_load; fi
  mc_resolve_bin
  mc_resolve_profile "$profile"
  mc_resolve_workspace "${ws:-${AUTOTEAM_MULTICA_WORKSPACE:-}}"
  # 表头用 ASCII：printf 按字节算宽度，中文会把列挤歪
  info "registry.yaml 的 runtime 字段写第一列（或者直接写 ID）"
  printf '%-36s %-8s %s\n' "RUNTIME" "STATUS" "ID"
  mc_runtime_selectors "$(mc runtime list --output json)" | while IFS=$'\t' read -r sel status id _; do
    printf '%-36s %-8s %s\n' "$sel" "$status" "$id"
  done
}

# ---------- agent ----------

multica_agents() {
  local rows=$1 runtimes=$2 agents name role runtime model max mcp envf rid existing id
  agents=$(mc agent list --output json) || die "读取 agent 列表失败"
  while IFS=$'\t' read -r name role _ runtime model max mcp envf; do
    [ -n "$name" ] || continue
    rid=$(mc_runtime_id "$runtimes" "$runtime" || true)
    if [ -z "$rid" ]; then
      fail "agent $name：找不到 runtime $runtime。可选："
      mc_runtime_selectors "$runtimes" | awk -F'\t' '{printf "       %s（%s）\n", $1, $2}'
      continue
    fi
    if [ "$(jq -r --arg id "$rid" '.[] | select(.id == $id) | .status' <<<"$runtimes")" != online ]; then
      warn "agent $name 的 runtime $runtime 现在不在线，任务会排队等它上线"
    fi
    existing=$(jq -c --arg n "$name" '[.[] | select(.name == $n)][0] // empty' <<<"$agents")
    if [ -z "$existing" ]; then
      multica_agent_create "$name" "$role" "$rid" "$model" "$max" "$mcp" "$envf"
    else
      id=$(jq -r '.id' <<<"$existing")
      multica_agent_update "$id" "$name" "$role" "$rid" "$model" "$max" "$mcp" "$envf"
    fi
  done <<EOF
$rows
EOF
}

multica_agent_args() {
  local role=$1 rid=$2 model=$3 max=$4 mcp=$5 instr
  instr=$(instructions_role_text "$role") || die "找不到角色指令 $role.md"
  MC_AGENT_ARGS=(--runtime-id "$rid" --instructions "$instr"
    --description "autoteam 的 $role（由 autoteam 管理，指令源文件 $(instructions_source roles "$role.md")）")
  [ "$max" = "-" ] || MC_AGENT_ARGS+=(--max-concurrent-tasks "$max")
  if [ "$model" != "-" ] && [ "$model" != default ]; then MC_AGENT_ARGS+=(--model "$model"); fi
  if [ "$mcp" != "-" ]; then
    local mcp_file
    mcp_file=$(instructions_path "" "$mcp") || die "找不到 MCP 配置 $mcp"
    MC_AGENT_ARGS+=(--mcp-config-file "$mcp_file")
  fi
}

multica_agent_create() {
  local name=$1 role=$2 rid=$3 model=$4 max=$5 mcp=$6 envf=$7 out
  multica_agent_args "$role" "$rid" "$model" "$max" "$mcp"
  if [ "$AUTOTEAM_AGENT_ACCESS" = workspace ]; then
    MC_AGENT_ARGS+=(--permission-mode public_to --public-to-workspace)
  fi
  if [ "$envf" != "-" ]; then
    [ -f "$envf" ] || die "agent $name 的 env_file 不存在：$envf"
    MC_AGENT_ARGS+=(--custom-env-file "$envf")
  fi
  local show_model=$model show_max=$max
  [ "$show_model" = "-" ] && show_model=default
  [ "$show_max" = "-" ] && show_max=默认
  planned "新建 agent $name（$role，runtime ${rid:0:8}，模型 $show_model，并发 $show_max）"
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  if out=$(mc agent create --name "$name" "${MC_AGENT_ARGS[@]}" --output json 2>&1); then
    ok "已新建 agent $name（$(jq -r '.id' <<<"$out" 2>/dev/null | cut -c1-8)）"
  else
    fail "新建 agent $name 失败：$out"
  fi
}

# agent 在 Multica 上的 runtime / 模型 / 并发和 registry 解析出的值逐项比对，不一致的每项输出一行：
# 字段<TAB>实际值<TAB>registry 要求的值。autoteam multica 和 autoteam doctor 共用这一份比对。
mc_agent_config_diff() {
  local cur=$1 rid=$2 model=$3 max=$4 have
  have=$(jq -r '.runtime_id // ""' <<<"$cur")
  [ "$have" = "$rid" ] || printf 'runtime\t%s\t%s\n' "$have" "$rid"
  { [ "$model" = "-" ] || [ "$model" = default ]; } && model=""
  have=$(jq -r '.model // ""' <<<"$cur")
  [ "$have" = "$model" ] || printf '模型\t%s\t%s\n' "${have:-default}" "${model:-default}"
  [ "$max" != "-" ] || return 0
  have=$(jq -r '.max_concurrent_tasks' <<<"$cur")
  [ "$have" = "$max" ] || printf '并发\t%s\t%s\n' "$have" "$max"
}

multica_agent_update() {
  local id=$1 name=$2 role=$3 rid=$4 model=$5 max=$6 mcp=$7 envf=$8 cur changes="" want_instr want_model out field
  cur=$(mc agent get "$id" --output json) || { fail "读取 agent $name 失败"; return 0; }
  want_instr=$(instructions_role_text "$role") || { fail "找不到角色指令 $role.md"; return 0; }
  [ "$(jq -r '.instructions' <<<"$cur")" = "${want_instr%$'\n'}" ] || [ "$(jq -r '.instructions' <<<"$cur")" = "$want_instr" ] || changes="$changes 指令"
  while IFS=$'\t' read -r field _; do
    [ -z "$field" ] || changes="$changes $field"
  done <<EOF
$(mc_agent_config_diff "$cur" "$rid" "$model" "$max")
EOF
  want_model=$model; { [ "$want_model" = "-" ] || [ "$want_model" = default ]; } && want_model=""
  if [ "$(jq -r '.archived_at // empty' <<<"$cur")" != "" ]; then
    fail "agent $name 已归档：在界面里恢复（multica agent restore $id）后再运行"
    return 0
  fi
  # MCP 配置和环境变量都读不回来（平台不返回明文），没法比对，所以只要 registry 里
  # 写了就每次重写一遍。漏掉这一条的后果很隐蔽：换了 Reviewer 的机器账号 token，
  # agent 其他字段都没变，这里报"已是最新"，token 根本没同步过去。
  if [ -z "$changes" ] && [ "$mcp" = "-" ] && [ "$envf" = "-" ]; then
    ok "agent $name 已是最新"
    return 0
  fi
  multica_agent_args "$role" "$rid" "$model" "$max" "$mcp"
  if [ -z "$want_model" ] && [ -n "$(jq -r '.model // ""' <<<"$cur")" ]; then MC_AGENT_ARGS+=(--model ""); fi
  if [ -z "$changes" ]; then
    local rewrite=""
    [ "$mcp" != "-" ] && rewrite="MCP 配置"
    [ "$envf" != "-" ] && rewrite="${rewrite:+$rewrite和}环境变量"
    info "agent $name 已是最新（$rewrite会重新写入）"
  else
    planned "更新 agent $name：$changes"
  fi
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  if out=$(mc agent update "$id" "${MC_AGENT_ARGS[@]}" --output json 2>&1); then
    ok "已更新 agent $name"
  else
    fail "更新 agent $name 失败：$out"
  fi
  if [ "$envf" != "-" ] && [ -f "$envf" ]; then
    if mc agent env set "$id" --custom-env-file "$envf" --output json >/dev/null 2>&1; then
      ok "已更新 agent $name 的环境变量"
    else
      fail "更新 agent $name 的环境变量失败"
    fi
  fi
}

# ---------- 项目 ----------

multica_project() {
  local title=${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}} url="https://github.com/$AUTOTEAM_REPO" projects out res
  projects=$(mc project list --output json) || die "读取项目列表失败"
  MC_PROJECT_ID=$(jq -r --arg t "$title" '[.[] | select(.title == $t)][0].id // empty' <<<"$projects")
  if [ -z "$MC_PROJECT_ID" ]; then
    planned "新建项目 $title（挂上仓库 $url）"
    [ "$AUTOTEAM_APPLY" = 1 ] || { planned "新建运营笔记（指派 Planner，不触发运行）"; return 0; }
    if out=$(mc project create --title "$title" --repo "$url" --description "autoteam 管理的项目，仓库 $AUTOTEAM_REPO" --output json 2>&1); then
      MC_PROJECT_ID=$(jq -r '.id' <<<"$out")
      ok "已新建项目 $title（${MC_PROJECT_ID:0:8}）"
    else
      die "新建项目失败：$out"
    fi
  else
    res=$(mc project resource list "$MC_PROJECT_ID" --output json) || die "读取项目仓库资源失败"
    if jq -e --arg u "$url" '.[] | select(.resource_type == "github_repo" and ((.resource_ref.url // "") | sub("\\.git$"; "") | ascii_downcase) == ($u | ascii_downcase))' <<<"$res" >/dev/null; then
      ok "项目 $title 已存在，已挂仓库"
    else
      planned "给项目 $title 挂上仓库 $url"
      if [ "$AUTOTEAM_APPLY" = 1 ]; then
        if out=$(mc project resource add "$MC_PROJECT_ID" --type github_repo --url "$url" --output json 2>&1); then
          ok "已挂上仓库"
        else
          case $out in
            *"Request conflict: this resource is already attached"*) ok "项目 $title 仓库已是最新" ;;
            *) fail "挂仓库失败：$out" ;;
          esac
        fi
      fi
    fi
  fi
  multica_project_note
}

mc_project_note_ids() {
  mc_issue_pages '.issues[] | select(.title == "运营笔记") | .id' --project "$1" --fields id,title
}

multica_project_note() {
  local ids count planner out id
  ids=$(mc_project_note_ids "$MC_PROJECT_ID") || die "读取项目运营笔记失败"
  count=$(grep -c . <<<"$ids" || true)
  if [ "$count" -gt 0 ]; then
    ok "运营笔记已存在（$count 条）"
    return 0
  fi
  planned "新建运营笔记（指派 Planner，不触发运行）"
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  planner=$(registry_agent_by_role "$(registry_agents)" planner)
  [ -n "$planner" ] || die "registry.yaml 缺少 Planner agent"
  planner=$(mc_agent_id "$planner") || die "读取 Planner agent 失败"
  [ -n "$planner" ] || die "Planner agent 尚未创建；先运行 autoteam multica --apply --only agents"
  out=$(mc issue create --title "运营笔记" --project "$MC_PROJECT_ID" --status backlog --output json) || die "新建运营笔记失败：$out"
  id=$(jq -r '.id // empty' <<<"$out")
  [ -n "$id" ] || die "新建运营笔记未返回 ID"
  mc issue assign "$id" --to-id "$planner" --no-start --output json >/dev/null || die "运营笔记已创建，但指派 Planner 失败：$id"
  mc issue status "$id" in_progress --no-start --output json >/dev/null || die "运营笔记已指派，但设置 in_progress 失败：$id"
  ok "已新建运营笔记（${id:0:8}），指派 Planner、状态 in_progress；未触发运行"
}

# ---------- autopilot ----------

# 配置按文件名选择要新建的 autopilot；旧配置没有该键时，已有的也算启用。
autopilot_selected() {
  local name=$1 existing_id=$2 item
  local -a selected
  IFS=, read -r -a selected <<<"$AUTOTEAM_AUTOPILOTS"
  for item in "${selected[@]}"; do
    [ "$(trim "$item")" = "$name" ] && return 0
  done
  [ "${AUTOTEAM_AUTOPILOTS_CONFIGURED:-1}" = 0 ] && [ -n "$existing_id" ]
}

autopilot_unlisted_hint() {
  warn "autopilot「$1」未在 AUTOTEAM_AUTOPILOTS 里，要保留就加上，不要就到 Multica 界面删除"
}

# 按生效定义的标题识别；eject 的自定义定义仍有效，别的项目不参与判断。
mc_obsolete_autopilots() {
  local list=$1 project=$2 f titles
  titles=$(
    while IFS= read -r f; do fm_get "$f" title; done <<EOF
$(instructions_list autopilots)
EOF
  )
  jq -c --arg p "$project" --arg titles "$titles" '
    ($titles | split("\n")) as $defined
    | [.autopilots[]? | select($p != "" and .project_id == $p)
       | select(.title as $t | $defined | index($t) | not)]' <<<"$list"
}

mc_obsolete_autopilots_hint() {
  local obsolete=$1 id title status message
  while IFS=$'\t' read -r id title status; do
    [ -n "$id" ] || continue
    message="autopilot「$title」（$id，$status）已无生效定义；请暂停（multica autopilot update $id --status paused），或到 Multica 界面删除"
    if [ "$status" = active ]; then warn "$message"; else info "$message"; fi
  done < <(jq -r '.[] | [.id,.title,.status] | @tsv' <<<"$obsolete")
}

# autopilot 的 cron：front matter 的 cron_key 指向 autoteam.conf 里的 AUTOTEAM_CRON_* 配置项
autopilot_cron() {
  local key re='^AUTOTEAM_CRON_[A-Z0-9_]+$'
  key=$(fm_get "$1" cron_key)
  [ -n "$key" ] || return 0
  [[ $key =~ $re ]] || die "$1 的 cron_key 不合法：$key"
  printf '%s' "${!key:-}"
}

# 读 front matter 里的一个字段
fm_get() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { on = 1; next }
    on && $0 == "---" { exit }
    on {
      key = $0; sub(/:.*/, "", key)
      if (key == k) { v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); gsub(/^["\047]|["\047]$/, "", v); print v; exit }
    }
  ' "$1"
}

# front matter 之后的正文
fm_body() {
  awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { on = 0; body = 1; next } body { print }' "$1" \
    | sed -e '/./,$!d'
}

multica_autopilots() {
  local rows=$1 paused=$2 rotate=$3 list f
  list=$(mc autopilot list --output json) || die "读取 autopilot 列表失败"
  mc_obsolete_autopilots_hint "$(mc_obsolete_autopilots "$list" "$MC_PROJECT_ID")"
  while IFS= read -r f; do
    multica_autopilot "$f" "$rows" "$list" "$paused" "$rotate"
  done <<EOF
$(instructions_list autopilots)
EOF
}

# autopilot 列表 $1 里绑在项目 $3 上、标题为 $2 的 autopilot ID。项目还没建（$3 为空）时没有
mc_autopilot_id() {
  jq -r --arg t "$2" --arg p "$3" \
    '[.autopilots[]? | select($p != "" and .title == $t and .project_id == $p)][0].id // empty' <<<"$1"
}

# agent 名字 -> ID。精确匹配，避免 Multica 的模糊解析把 planner 匹配到 ex-planner
mc_agent_id() {
  mc agent list --output json 2>/dev/null | jq -r --arg n "$1" '[.[] | select(.name == $n)][0].id // empty'
}

multica_autopilot() {
  local f=$1 rows=$2 list=$3 paused=$4 rotate=$5
  local title role mode cron trigger issue_title subscriber agent body id out args name newly_created=0
  name=${f##*/} name=${name%.md}
  title=$(fm_get "$f" title) role=$(fm_get "$f" role) mode=$(fm_get "$f" mode)
  id=$(mc_autopilot_id "$list" "$title" "$MC_PROJECT_ID")
  if ! autopilot_selected "$name" "$id"; then
    if [ -z "$id" ]; then
      info "跳过未启用的 autopilot「$title」（$name）"
      return 0
    fi
    autopilot_unlisted_hint "$title"
  fi
  cron=$(autopilot_cron "$f") trigger=$(fm_get "$f" trigger) issue_title=$(fm_get "$f" issue_title)
  subscriber=$(fm_get "$f" subscriber)
  if [ -z "$title" ] || [ -z "$role" ] || [ -z "$mode" ]; then
    fail "$f 缺少 title / role / mode"
    return 0
  fi
  [ -n "$trigger" ] || trigger=schedule
  agent=$(registry_agent_by_role "$rows" "$role")
  [ -n "$agent" ] || { fail "$f 要求角色 $role，但 registry.yaml 里没有"; return 0; }
  body=$(instructions_with_preamble "$(fm_body "$f")")

  # 传 ID 不传名字：Multica 按名字解析是模糊匹配，工作区里只要有另一个 agent 的名字
  # 包含这个名字（比如 ex-planner 之于 planner），就会报 ambiguous agent
  local agent_ref
  agent_ref=$(mc_agent_id "$agent") || { fail "读取 agent $agent 失败，未执行 autopilot 同步"; return 0; }
  [ -n "$agent_ref" ] || agent_ref=$agent

  args=(--agent "$agent_ref" --mode "$mode" --description "$body")
  [ -n "$MC_PROJECT_ID" ] && args+=(--project "$MC_PROJECT_ID")
  if [ "$mode" = create_issue ]; then
    [ -n "$issue_title" ] && args+=(--issue-title-template "$issue_title")
    if [ "$subscriber" = human ]; then
      subscriber=${AUTOTEAM_HUMAN:-}
      if [ -z "$subscriber" ]; then
        subscriber=$(mc user profile get --output json | jq -r '.name // empty') || {
          fail "读取订阅人失败，未执行 autopilot「$title」同步"; return 0;
        }
      fi
    fi
    [ -n "$subscriber" ] && args+=(--subscriber "$subscriber")
  fi

  # 按 (标题, 项目) 找：Multica 允许同一工作区里 autopilot 重名，同一工作区的别的项目
  # 也会有「推进巡检」等同名 autopilot，只按标题找会把别人的改成本项目的配置
  if [ -z "$id" ]; then
    if jq -e --arg t "$title" '.autopilots[]? | select(.title == $t)' <<<"$list" >/dev/null; then
      info "工作区里另有同名 autopilot「$title」不属于本项目，不改动它"
    fi
    planned "新建 autopilot「$title」（$agent，$mode，${cron:-$trigger}）"
    if [ "$AUTOTEAM_APPLY" = 1 ]; then
      if out=$(mc autopilot create --title "$title" "${args[@]}" --output json 2>&1); then
        id=$(jq -r '.id // .autopilot.id // empty' <<<"$out")
        newly_created=1
        ok "已新建 autopilot「$title」"
      else
        fail "新建 autopilot「$title」失败：$out"; return 0
      fi
    fi
  else
    local same_rc=0
    multica_autopilot_same "$id" "$agent" "$mode" "$body" || same_rc=$?
    if [ "$same_rc" = 2 ]; then
      fail "读取 autopilot「$title」失败，未执行更新"
      return 0
    elif [ "$same_rc" = 3 ]; then
      fail "autopilot「$title」（$id）已不属于本项目，未执行该项；重新运行同步"
      return 0
    elif [ "$same_rc" = 0 ]; then
      ok "autopilot「$title」已是最新"
    else
      planned "更新 autopilot「$title」"
      if [ "$AUTOTEAM_APPLY" = 1 ]; then
        if out=$(mc autopilot update "$id" "${args[@]}" --output json 2>&1); then
          ok "已更新 autopilot「$title」"
        else
          fail "更新 autopilot「$title」失败：$out"
        fi
      fi
    fi
  fi

  [ -n "$id" ] || return 0
  case $trigger in
    schedule) multica_schedule_trigger "$id" "$title" "$cron" ;;
    webhook) multica_webhook_trigger "$id" "$title" "$rotate" ;;
    *) fail "$f 的 trigger 只能是 schedule 或 webhook：$trigger" ;;
  esac
  if [ "$paused" = 1 ] && [ "$newly_created" = 1 ]; then
    if mc autopilot update "$id" --status paused --output json >/dev/null 2>&1; then
      info "已暂停「$title」"
    else
      fail "暂停「$title」失败"
    fi
  fi
}

# 已有 autopilot 的指派、模式、runbook 是否和文件一致：0 一致，1 不一致，2 读取失败，
# 3 已不属于本项目（列表和详情是两次请求，其间可能被改绑，改绑后的不能再动）
multica_autopilot_same() {
  local id=$1 agent=$2 mode=$3 body=$4 json agent_id
  json=$(mc autopilot get "$id" --output json) || return 2
  jq -e --arg p "$MC_PROJECT_ID" '((.autopilot // .).project_id // "") == $p' <<<"$json" >/dev/null 2>&1 || return 3
  agent_id=$(mc_agent_id "$agent") || return 2
  jq -e --arg a "$agent_id" --arg m "$mode" --arg b "$body" '
    (.autopilot // .) as $ap
    | ($ap.assignee_id == $a)
      and ($ap.execution_mode == $m)
      and ((($ap.description // "") | rtrimstr("\n")) == ($b | rtrimstr("\n")))
  ' <<<"$json" >/dev/null 2>&1
}

mc_autopilot_triggers() {
  mc autopilot get "$1" --output json 2>/dev/null | jq -c '.triggers // (.autopilot.triggers // [])'
}

multica_schedule_trigger() {
  local id=$1 title=$2 cron=$3 triggers tid have_cron have_tz out
  [ -n "$cron" ] || { fail "「$title」是定时触发，但没写 cron"; return 0; }
  triggers=$(mc_autopilot_triggers "$id") || { fail "读取「$title」触发器失败，未执行触发器同步"; return 0; }
  tid=$(jq -r '[.[] | select(.kind == "schedule")][0].id // empty' <<<"$triggers")
  if [ -z "$tid" ]; then
    planned "给「$title」加定时触发 $cron（$AUTOTEAM_TIMEZONE）"
    [ "$AUTOTEAM_APPLY" = 1 ] || return 0
    if out=$(mc autopilot trigger-add "$id" --kind schedule --cron "$cron" --timezone "$AUTOTEAM_TIMEZONE" --output json 2>&1); then
      ok "已加定时触发 $cron"
    else
      fail "加定时触发失败：$out"
    fi
    return 0
  fi
  have_cron=$(jq -r --arg t "$tid" '.[] | select(.id == $t) | (.cron_expression // .cron // "")' <<<"$triggers")
  have_tz=$(jq -r --arg t "$tid" '.[] | select(.id == $t) | (.timezone // "")' <<<"$triggers")
  if [ "$have_cron" = "$cron" ] && [ "$have_tz" = "$AUTOTEAM_TIMEZONE" ]; then
    ok "定时触发已是 $cron（$AUTOTEAM_TIMEZONE）"
    return 0
  fi
  planned "把「$title」的定时触发从 ${have_cron:-?}（${have_tz:-?}）改为 $cron（$AUTOTEAM_TIMEZONE）"
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  if out=$(mc autopilot trigger-update "$id" "$tid" --cron "$cron" --timezone "$AUTOTEAM_TIMEZONE" --output json 2>&1); then
    ok "已更新定时触发"
  else
    fail "更新定时触发失败：$out"
  fi
}

multica_webhook_trigger() {
  local id=$1 title=$2 rotate=$3 triggers tid out url secrets
  triggers=$(mc_autopilot_triggers "$id") || { fail "读取「$title」触发器失败，未执行触发器同步"; return 0; }
  tid=$(jq -r '[.[] | select(.kind == "webhook")][0].id // empty' <<<"$triggers")
  if [ -n "$tid" ] && [ "$rotate" != 1 ]; then
    if secrets=$(gh secret list --repo "$AUTOTEAM_REPO" --json name --jq '.[].name' 2>/dev/null) && grep -qx MULTICA_DEPLOY_HOOK <<<"$secrets"; then
      ok "部署 webhook 已存在，GitHub secret MULTICA_DEPLOY_HOOK 已设置"
    else
      fail "部署 webhook 已存在，但 GitHub 上没有 secret MULTICA_DEPLOY_HOOK：加 --rotate-webhook 重新生成并写入"
    fi
    return 0
  fi
  if [ -n "$tid" ]; then
    planned "重新生成「$title」的 webhook 地址，写入 GitHub secret MULTICA_DEPLOY_HOOK"
    [ "$AUTOTEAM_APPLY" = 1 ] || return 0
    out=$(mc autopilot trigger-rotate-url "$id" "$tid" --yes --output json 2>&1) || { fail "重新生成 webhook 失败：$out"; return 0; }
  else
    planned "给「$title」加 webhook 触发，地址写入 GitHub secret MULTICA_DEPLOY_HOOK"
    [ "$AUTOTEAM_APPLY" = 1 ] || return 0
    out=$(mc autopilot trigger-add "$id" --kind webhook --label "GitHub 部署结果" --output json 2>&1) || { fail "加 webhook 触发失败：$out"; return 0; }
  fi
  url=$(jq -r '.webhook_url // (.trigger.webhook_url) // empty' <<<"$out" 2>/dev/null)
  if [ -z "$url" ]; then
    local path
    path=$(jq -r '.webhook_path // (.trigger.webhook_path) // empty' <<<"$out" 2>/dev/null)
    [ -n "$path" ] && { mc_resolve_api; url=$MC_SERVER$path; }
  fi
  if [ -z "$url" ]; then
    url=$(mc autopilot get "$id" --show-secrets --output json 2>/dev/null | jq -r '[.triggers[]? | select(.kind == "webhook") | .webhook_url][0] // empty')
  fi
  if [ -z "$url" ]; then
    fail "拿不到 webhook 地址：在 Multica 界面的 autopilot「$title」里复制地址，执行 gh secret set MULTICA_DEPLOY_HOOK --repo $AUTOTEAM_REPO"
    return 0
  fi
  if printf '%s' "$url" | gh secret set MULTICA_DEPLOY_HOOK --repo "$AUTOTEAM_REPO" >/dev/null 2>&1; then
    ok "webhook 地址已写入 GitHub secret MULTICA_DEPLOY_HOOK（地址含凭据，不在这里显示）"
  else
    fail "写 GitHub secret 失败：检查 gh 是否有仓库 admin 权限"
  fi
}
