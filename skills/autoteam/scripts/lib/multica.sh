# shellcheck shell=bash
# autoteam multica / autoteam runtimes：自定义状态、agent、项目、autopilot、部署 webhook。默认只预览。

multica_usage() {
  cat <<'EOF'
用法：autoteam multica [选项]

按 ops/agents/ 下的文件配置 Multica 工作区。默认只预览，加 --apply 才执行。

  --apply                 执行改动
  --profile <名字>        multica CLI 的 profile（默认：环境变量 MULTICA_SERVER_URL + MULTICA_TOKEN，
                          否则已配置的默认 profile，再否则 ~/.multica/profiles 下唯一的 profile；也可用 AUTOTEAM_MULTICA_PROFILE）
  --workspace <slug|ID>   工作区（默认 autoteam.conf 的 AUTOTEAM_MULTICA_WORKSPACE）
  --only <部分>           只处理其中几部分，逗号分隔：statuses,agents,project,autopilots
  --paused                新建的 autopilot 立即暂停（先配好、以后再启用）
  --rotate-webhook        重新生成部署 webhook 地址并写入 GitHub secret

会做的事：
  1. 自定义状态 approved / code_review / rework / shipping（调 Multica API，需要工作区 owner 或 admin）
  2. 按 registry.yaml 创建或更新 agent，指令取 ops/agents/<角色>.md
  3. 项目（AUTOTEAM_MULTICA_PROJECT），挂上 GitHub 仓库资源
  4. 按 ops/agents/autopilots/*.md 创建或更新 autopilot 和触发器；部署 webhook 地址写进
     GitHub secret MULTICA_DEPLOY_HOOK
EOF
}

MC_APP_BIN=/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica

# 自定义状态：key 名称 类别 颜色 图标 说明
autoteam_statuses() {
  cat <<'EOF'
approved	已批准	unstarted	#3b82f6	circle	人已批准，等 Planner 派发
code_review	待评审	started	#a855f7	three_quarters	PR 已提交，等 Reviewer 评审
rework	返工	started	#f97316	half	评审或验收不通过，等 Implementer 修改
shipping	待上线	started	#14b8a6	three_quarters	评审通过，等合并、部署和 Planner 线上验收
EOF
}

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
  MC_PROFILE=${1:-${AUTOTEAM_MULTICA_PROFILE:-}}
  MC_ARGS=()
  if [ -z "$MC_PROFILE" ] && [ -n "${MULTICA_SERVER_URL:-}" ] && [ -n "${MULTICA_TOKEN:-}" ]; then
    :
  elif [ -z "$MC_PROFILE" ] && ! "$MC_BIN" config show 2>/dev/null | grep -Eq '^server_url:[[:space:]]+https?://'; then
    local dirs n
    dirs=$(ls -1 "$HOME/.multica/profiles" 2>/dev/null || true)
    n=$(printf '%s\n' "$dirs" | grep -c . || true)
    if [ "$n" = 1 ]; then
      MC_PROFILE=$dirs
    else
      die "multica 默认 profile 没有配置服务器：用 --profile 指定，或先运行 multica setup。现有 profile：$(printf '%s' "$dirs" | tr '\n' ' ')"
    fi
  fi
  if [ -n "$MC_PROFILE" ]; then
    MC_ARGS=(--profile "$MC_PROFILE")
  fi
}

mc() {
  "$MC_BIN" ${MC_ARGS[@]+"${MC_ARGS[@]}"} "$@"
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

# 调 Multica HTTP API；token 通过 stdin 交给 curl，不出现在进程参数里
mc_api() {
  local method=$1 path=$2 body=${3:-} tmp code data_args=()
  tmp=$(autoteam_tmpdir)
  if [ -n "$body" ]; then
    printf '%s' "$body" > "$tmp/mc-body.json"
    data_args=(--data-binary "@$tmp/mc-body.json")
  fi
  code=$(printf 'header = "Authorization: Bearer %s"\nheader = "X-Workspace-ID: %s"\n' "$MC_TOKEN" "$MC_WS_ID" \
    | curl -sS -K - -X "$method" -H 'Content-Type: application/json' -o "$tmp/mc-resp.json" -w '%{http_code}' \
        ${data_args[@]+"${data_args[@]}"} "$MC_SERVER$path" 2>"$tmp/mc-err") || code=000
  MC_API_OUT=$(cat "$tmp/mc-resp.json" 2>/dev/null || cat "$tmp/mc-err" 2>/dev/null || true)
  case $code in 2??) return 0 ;; *) MC_API_OUT="HTTP $code $MC_API_OUT"; return 1 ;; esac
}

multica_setup() {
  mc_resolve_bin
  mc_resolve_profile "$1"
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

  multica_want() { [ -z "$only" ] || case $only in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

  if multica_want statuses; then
    section "自定义状态"
    multica_statuses
  fi
  local runtimes
  runtimes=$(mc runtime list --output json) || die "读取 runtime 列表失败"
  if multica_want agents; then
    section "agent"
    multica_agents "$rows" "$runtimes"
  fi
  MC_PROJECT_ID=""
  if multica_want project || multica_want autopilots; then
    section "项目"
    multica_project
  fi
  if multica_want autopilots; then
    section "autopilot"
    multica_autopilots "$rows" "$paused" "$rotate"
  fi

  section "需要你在 Multica 界面里做的事"
  info "GitHub 集成（可选）：Settings → GitHub 连接仓库后，任务卡片上能看到关联 PR 和 CI 状态"
  info "看板上确认 4 个自定义状态：已批准、待评审、返工、待上线"
  preview_footer
}

# ---------- 自定义状态 ----------

mc_category_ok() {
  case "$1:$2" in
    unstarted:unstarted|unstarted:backlog|unstarted:todo) return 0 ;;
    started:started|started:in_progress|started:in_review|started:blocked) return 0 ;;
    *) return 1 ;;
  esac
}

multica_statuses() {
  mc_resolve_api
  if [ -z "$MC_TOKEN" ] || [ -z "$MC_SERVER" ]; then
    warn "读不到 multica 的登录 token，不能自动建状态"
    multica_status_manual
    return 0
  fi
  if ! mc_api GET /api/issue-statuses; then
    warn "读取状态列表失败：$MC_API_OUT"
    multica_status_manual
    return 0
  fi
  local catalog=$MC_API_OUT key name category color icon desc have body
  while IFS=$'\t' read -r key name category color icon desc; do
    [ -n "$key" ] || continue
    have=$(jq -r --arg k "$key" '.statuses[] | select(.key == $k) | .category' <<<"$catalog")
    if [ -n "$have" ]; then
      if mc_category_ok "$category" "$have"; then
        ok "状态 $key（$name）已存在"
      else
        fail "状态 $key 已存在但类别是 $have，应为 $category。类别建好后不能改：在界面里归档它，再重新运行"
      fi
      continue
    fi
    planned "新建状态 $key（$name，类别 $category）"
    [ "$AUTOTEAM_APPLY" = 1 ] || continue
    body=$(jq -nc --arg key "$key" --arg name "$name" --arg category "$category" \
      --arg color "$color" --arg icon "$icon" --arg desc "$desc（autoteam）" \
      '{key: $key, name: $name, category: $category, color: $color, icon: $icon, description: $desc}')
    if mc_api POST /api/issue-statuses "$body"; then
      ok "已新建状态 $key"
    else
      fail "新建状态 $key 失败：$MC_API_OUT"
      hint "需要工作区 owner 或 admin；也可以在 Settings → Issue Statuses 手动建（key 必须一致）"
    fi
  done <<EOF
$(autoteam_statuses)
EOF
}

multica_status_manual() {
  hint "在 Settings → Issue Statuses 手动添加（key 必须一致，类别建好后不能改）："
  local key name category color icon desc
  while IFS=$'\t' read -r key name category color icon desc; do
    hint "  key $key，名称 $name，类别 $category"
  done <<EOF
$(autoteam_statuses)
EOF
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
  local role=$1 rid=$2 model=$3 max=$4 mcp=$5
  MC_AGENT_ARGS=(--runtime-id "$rid" --instructions "$(read_file "ops/agents/$role.md")"
    --description "autoteam 的 $role（由 autoteam 管理，指令源文件 ops/agents/$role.md）")
  [ "$max" = "-" ] || MC_AGENT_ARGS+=(--max-concurrent-tasks "$max")
  if [ "$model" != "-" ] && [ "$model" != default ]; then MC_AGENT_ARGS+=(--model "$model"); fi
  if [ "$mcp" != "-" ]; then
    [ -f "ops/agents/$mcp" ] || die "找不到 MCP 配置 ops/agents/$mcp"
    MC_AGENT_ARGS+=(--mcp-config-file "ops/agents/$mcp")
  fi
}

multica_agent_create() {
  local name=$1 role=$2 rid=$3 model=$4 max=$5 mcp=$6 envf=$7 out
  [ -f "ops/agents/$role.md" ] || die "找不到角色指令 ops/agents/$role.md"
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

multica_agent_update() {
  local id=$1 name=$2 role=$3 rid=$4 model=$5 max=$6 mcp=$7 envf=$8 cur changes="" want_instr want_model out
  cur=$(mc agent get "$id" --output json) || { fail "读取 agent $name 失败"; return 0; }
  want_instr=$(read_file "ops/agents/$role.md")
  [ "$(jq -r '.instructions' <<<"$cur")" = "${want_instr%$'\n'}" ] || [ "$(jq -r '.instructions' <<<"$cur")" = "$want_instr" ] || changes="$changes 指令"
  [ "$(jq -r '.runtime_id' <<<"$cur")" = "$rid" ] || changes="$changes runtime"
  want_model=$model; { [ "$want_model" = "-" ] || [ "$want_model" = default ]; } && want_model=""
  [ "$(jq -r '.model // ""' <<<"$cur")" = "$want_model" ] || changes="$changes 模型"
  if [ "$max" != "-" ] && [ "$(jq -r '.max_concurrent_tasks' <<<"$cur")" != "$max" ]; then changes="$changes 并发"; fi
  if [ "$(jq -r '.archived_at // empty' <<<"$cur")" != "" ]; then
    warn "agent $name 已归档：在界面里恢复（multica agent restore $id）后再运行"
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
    [ "$AUTOTEAM_APPLY" = 1 ] || return 0
    if out=$(mc project create --title "$title" --repo "$url" --description "autoteam 管理的项目，仓库 $AUTOTEAM_REPO" --output json 2>&1); then
      MC_PROJECT_ID=$(jq -r '.id' <<<"$out")
      ok "已新建项目 $title（${MC_PROJECT_ID:0:8}）"
    else
      fail "新建项目失败：$out"
    fi
    return 0
  fi
  res=$(mc project resource list "$MC_PROJECT_ID" --output json 2>/dev/null || echo '[]')
  if jq -e --arg u "$url" '.[] | select(.resource_type == "github_repo" and ((.resource_ref.url // "") | sub("\\.git$"; "") | ascii_downcase) == ($u | ascii_downcase))' <<<"$res" >/dev/null; then
    ok "项目 $title 已存在，已挂仓库"
  else
    planned "给项目 $title 挂上仓库 $url"
    [ "$AUTOTEAM_APPLY" = 1 ] || return 0
    if out=$(mc project resource add "$MC_PROJECT_ID" --type github_repo --url "$url" --output json 2>&1); then
      ok "已挂上仓库"
    else
      fail "挂仓库失败：$out"
    fi
  fi
}

# ---------- autopilot ----------

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
  for f in ops/agents/autopilots/*.md; do
    [ -f "$f" ] || continue
    multica_autopilot "$f" "$rows" "$list" "$paused" "$rotate"
  done
}

# agent 名字 -> ID。精确匹配，避免 Multica 的模糊解析把 planner 匹配到 ex-planner
mc_agent_id() {
  mc agent list --output json 2>/dev/null | jq -r --arg n "$1" '[.[] | select(.name == $n)][0].id // empty'
}

multica_autopilot() {
  local f=$1 rows=$2 list=$3 paused=$4 rotate=$5
  local title role mode cron trigger issue_title subscriber agent body id out args
  title=$(fm_get "$f" title) role=$(fm_get "$f" role) mode=$(fm_get "$f" mode)
  cron=$(fm_get "$f" cron) trigger=$(fm_get "$f" trigger) issue_title=$(fm_get "$f" issue_title)
  subscriber=$(fm_get "$f" subscriber)
  if [ -z "$title" ] || [ -z "$role" ] || [ -z "$mode" ]; then
    fail "$f 缺少 title / role / mode"
    return 0
  fi
  [ -n "$trigger" ] || trigger=schedule
  agent=$(registry_agent_by_role "$rows" "$role")
  [ -n "$agent" ] || { fail "$f 要求角色 $role，但 registry.yaml 里没有"; return 0; }
  body=$(fm_body "$f")

  # 传 ID 不传名字：Multica 按名字解析是模糊匹配，工作区里只要有另一个 agent 的名字
  # 包含这个名字（比如 ex-planner 之于 planner），就会报 ambiguous agent
  local agent_ref
  agent_ref=$(mc_agent_id "$agent")
  [ -n "$agent_ref" ] || agent_ref=$agent

  args=(--agent "$agent_ref" --mode "$mode" --description "$body")
  [ -n "$MC_PROJECT_ID" ] && args+=(--project "$MC_PROJECT_ID")
  if [ "$mode" = create_issue ]; then
    [ -n "$issue_title" ] && args+=(--issue-title-template "$issue_title")
    if [ "$subscriber" = human ]; then
      subscriber=${AUTOTEAM_HUMAN:-$(mc user profile get --output json 2>/dev/null | jq -r '.name // empty')}
    fi
    [ -n "$subscriber" ] && args+=(--subscriber "$subscriber")
  fi

  id=$(jq -r --arg t "$title" '[.autopilots[]? | select(.title == $t)][0].id // empty' <<<"$list")
  if [ -z "$id" ]; then
    planned "新建 autopilot「$title」（$agent，$mode，${cron:-$trigger}）"
    if [ "$AUTOTEAM_APPLY" = 1 ]; then
      if out=$(mc autopilot create --title "$title" "${args[@]}" --output json 2>&1); then
        id=$(jq -r '.id // .autopilot.id // empty' <<<"$out")
        ok "已新建 autopilot「$title」"
      else
        fail "新建 autopilot「$title」失败：$out"; return 0
      fi
    fi
  else
    if multica_autopilot_same "$id" "$agent" "$mode" "$body"; then
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
  if [ "$paused" = 1 ] && [ "$AUTOTEAM_APPLY" = 1 ]; then
    if mc autopilot update "$id" --status paused --output json >/dev/null 2>&1; then
      info "已暂停「$title」"
    else
      warn "暂停「$title」失败"
    fi
  fi
}

# 已有 autopilot 的指派、模式、runbook 是否和文件一致
multica_autopilot_same() {
  local id=$1 agent=$2 mode=$3 body=$4 json agent_id
  json=$(mc autopilot get "$id" --output json 2>/dev/null) || return 1
  agent_id=$(mc_agent_id "$agent")
  # 项目也要比：项目改名或重建后会有新的 project_id，autopilot 还绑在旧项目上的话，
  # Planner 会在旧项目里找任务，查不到就报"无待验收任务"，整条链路悄悄断掉。
  jq -e --arg a "$agent_id" --arg m "$mode" --arg b "$body" --arg p "$MC_PROJECT_ID" '
    (.autopilot // .) as $ap
    | ($ap.assignee_id == $a)
      and ($ap.execution_mode == $m)
      and (($ap.project_id // "") == $p)
      and ((($ap.description // "") | rtrimstr("\n")) == ($b | rtrimstr("\n")))
  ' <<<"$json" >/dev/null 2>&1
}

mc_autopilot_triggers() {
  mc autopilot get "$1" --output json 2>/dev/null | jq -c '.triggers // (.autopilot.triggers // [])'
}

multica_schedule_trigger() {
  local id=$1 title=$2 cron=$3 triggers tid have_cron have_tz out
  [ -n "$cron" ] || { fail "「$title」是定时触发，但没写 cron"; return 0; }
  triggers=$(mc_autopilot_triggers "$id")
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
  local id=$1 title=$2 rotate=$3 triggers tid out url
  triggers=$(mc_autopilot_triggers "$id")
  tid=$(jq -r '[.[] | select(.kind == "webhook")][0].id // empty' <<<"$triggers")
  if [ -n "$tid" ] && [ "$rotate" != 1 ]; then
    if gh secret list --repo "$AUTOTEAM_REPO" --json name --jq '.[].name' 2>/dev/null | grep -qx MULTICA_DEPLOY_HOOK; then
      ok "部署 webhook 已存在，GitHub secret MULTICA_DEPLOY_HOOK 已设置"
    else
      warn "部署 webhook 已存在，但 GitHub 上没有 secret MULTICA_DEPLOY_HOOK：加 --rotate-webhook 重新生成并写入"
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
