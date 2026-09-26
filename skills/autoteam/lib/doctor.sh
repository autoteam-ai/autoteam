# shellcheck shell=bash
# autoteam doctor：只读检查，逐项给出 ✅ / ⚠️ / ❌。
# Multica 部分故意在子 shell 里跑（出错时 die 只结束那一段），计数通过文件带回：
# shellcheck disable=SC2030,SC2031

doctor_usage() {
  cat <<'EOF'
用法：autoteam doctor [选项]

只读检查本地文件、GitHub、Multica 是否按 autoteam 配好。有 ❌ 时退出码为 1。

  --skip-github            不检查 GitHub
  --skip-multica           不检查 Multica
  --profile <名字>         multica profile
  --workspace <slug|ID>    Multica 工作区（默认 autoteam.conf 的 AUTOTEAM_MULTICA_WORKSPACE）
EOF
}

cmd_doctor() {
  local skip_gh=0 skip_mc=0 profile="" ws=""
  while [ $# -gt 0 ]; do
    case $1 in
      --skip-github) skip_gh=1; shift ;;
      --skip-multica) skip_mc=1; shift ;;
      --profile) profile=$2; shift 2 ;;
      --workspace) ws=$2; shift 2 ;;
      -h|--help) doctor_usage; return 0 ;;
      *) doctor_usage >&2; die "未知选项：$1" ;;
    esac
  done
  need_cmd jq
  local root rows=""
  root=$(repo_root)
  cd "$root" || die "进不去 $root"

  section "本地文件"
  if [ -d "$AUTOTEAM_LEGACY_DIR" ]; then
    fail "检测到旧版布局 $AUTOTEAM_LEGACY_DIR/：运行 autoteam migrate 迁到 $AUTOTEAM_DIR/（先加 --dry-run 看计划）"
    print_summary
    return 1
  fi
  if ! conf_exists "$root"; then
    fail "没有 $AUTOTEAM_CONF_REL：先运行 autoteam init"
    print_summary
    return 1
  fi
  conf_load "$root"
  doctor_files
  if rows=$(registry_agents 2>/dev/null) && registry_validate "$rows"; then
    ok "registry.yaml：$(printf '%s\n' "$rows" | grep -c .) 个 agent，角色齐全"
  else
    rows=""
  fi

  if [ "$skip_gh" = 1 ]; then
    info "跳过 GitHub 检查"
  else
    section "GitHub $AUTOTEAM_REPO"
    doctor_github
  fi

  if [ "$skip_mc" = 1 ]; then
    info "跳过 Multica 检查"
  elif [ -z "${ws:-$AUTOTEAM_MULTICA_WORKSPACE}" ] && [ -z "${MULTICA_WORKSPACE_ID:-}" ]; then
    section "Multica"
    warn "autoteam.conf 没有 AUTOTEAM_MULTICA_WORKSPACE，跳过 Multica 检查"
  else
    section "Multica"
    # 在子 shell 里跑：multica 出错时 die 只结束这一段；计数通过文件带回来
    local counts e w
    counts=$(autoteam_tmpdir)/doctor-multica
    (
      AUTOTEAM_ERRORS=0 AUTOTEAM_WARNINGS=0
      doctor_multica "$profile" "${ws:-$AUTOTEAM_MULTICA_WORKSPACE}" "$rows"
      printf '%s %s\n' "$AUTOTEAM_ERRORS" "$AUTOTEAM_WARNINGS" > "$counts"
    ) || true
    if [ -f "$counts" ]; then
      read -r e w < "$counts"
      AUTOTEAM_ERRORS=$((AUTOTEAM_ERRORS + e)) AUTOTEAM_WARNINGS=$((AUTOTEAM_WARNINGS + w))
    else
      AUTOTEAM_ERRORS=$((AUTOTEAM_ERRORS + 1))
    fi
  fi

  print_summary
  [ "$AUTOTEAM_ERRORS" -eq 0 ]
}

# 老项目没有 lock 只提醒：升级时 autoteam upgrade 会生成
doctor_lock() {
  local v current
  current=$(autoteam_version)
  if [ ! -f "$AUTOTEAM_LOCK_REL" ]; then
    warn "没有 $AUTOTEAM_LOCK_REL（旧版 autoteam 装的项目）：运行 autoteam upgrade 生成，升级靠它判断哪些文件改过"
  elif ! v=$(jq -er '.version' "$AUTOTEAM_LOCK_REL" 2>/dev/null); then
    fail "$AUTOTEAM_LOCK_REL 读不出 version：不是合法的 lock，运行 autoteam upgrade 重新生成"
  elif [ "$v" != "$current" ]; then
    warn "$AUTOTEAM_LOCK_REL 记录的版本是 $v，当前 autoteam 是 $current：运行 autoteam upgrade"
  else
    ok "$AUTOTEAM_LOCK_REL 版本 $v，与当前 autoteam 一致"
  fi
}

doctor_files() {
  local tpl target mode missing="" t start
  while read -r tpl target mode; do
    [ -n "$tpl" ] || continue
    if [ ! -e "$target" ]; then
      missing="$missing $target"
      continue
    fi
    case $mode in
      exec) [ -x "$target" ] || warn "$target 没有可执行位：chmod +x $target" ;;
      block)
        start=$(block_markers "$target" | sed -n 1p)
        grep -qxF "$start" "$target" || fail "$target 里没有 autoteam 受管块：运行 autoteam init"
        ;;
    esac
  done <<EOF
$(autoteam_manifest)
EOF
  if [ -n "$missing" ]; then
    fail "缺少文件：$missing（运行 autoteam init）"
  else
    ok "工作流文件齐全"
  fi

  doctor_lock
  if [ -f Makefile ]; then
    for t in check dev deploy; do
      grep -Eq "^${t}[[:space:]]*:" Makefile || fail "Makefile 缺少 $t 目标"
    done
    if grep -q 'AUTOTEAM-TODO' Makefile; then
      fail "Makefile 里还有 AUTOTEAM-TODO 桩：把 check / dev / deploy 改成真实命令"
    else
      ok "Makefile 有 check / dev / deploy"
    fi
  fi
  if [ -f .github/CODEOWNERS ] && grep -Eq "^/$AUTOTEAM_DIR/[[:space:]]+@[A-Za-z0-9]" .github/CODEOWNERS; then
    ok "CODEOWNERS 保护 .github/、$AUTOTEAM_DIR/、Makefile、.jscpd.json"
  else
    fail "CODEOWNERS 里没有规则文件的负责人"
  fi
  if [ -f .github/workflows/gate.yml ] && grep -q 'make check' .github/workflows/gate.yml; then
    ok "gate.yml 调用 make check"
  fi
  if [ -f .github/workflows/deploy.yml ] && ! grep -q 'MULTICA_DEPLOY_HOOK' .github/workflows/deploy.yml; then
    warn "deploy.yml 没有通知 Planner 的步骤（MULTICA_DEPLOY_HOOK）"
  fi
}

doctor_github() {
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    fail "gh 没安装或没登录，跳过 GitHub 检查"
    return 0
  fi
  if ! gh_call GET "repos/$AUTOTEAM_REPO"; then
    fail "读不到仓库：$GH_OUT"
    return 0
  fi
  local repo=$GH_OUT level=standard id approvals n
  if [ "$(jq -r '.allow_auto_merge' <<<"$repo")" = true ]; then ok "允许自动合并"; else warn "没有打开自动合并"; fi
  if [ "$(jq -r '.allow_squash_merge and (.allow_merge_commit | not) and (.allow_rebase_merge | not)' <<<"$repo")" = true ]; then
    ok "只保留 squash 合并"
  else
    warn "合并方式不止 squash：autoteam github --apply"
  fi
  if [ "$(jq -r '.delete_branch_on_merge' <<<"$repo")" = true ]; then ok "合并后自动删分支"; else warn "合并后不会自动删分支"; fi

  if ! gh_call GET "repos/$AUTOTEAM_REPO/rulesets"; then
    case $GH_OUT in
      *"Upgrade to GitHub Pro"*)
        level=none
        warn "降级模式：GitHub Free 的私有仓库没有规则集，合并闸门只靠 agent 指令"
        hint "仓库改为公开、升级 GitHub Pro 或迁到 Team 组织后，运行 autoteam github --apply" ;;
      *) fail "读取规则集失败：$GH_OUT" ;;
    esac
  else
    id=$(jq -r --arg n "$AUTOTEAM_RULESET_NAME" '.[] | select(.name == $n) | .id' <<<"$GH_OUT" | head -n1)
    if [ -z "$id" ]; then
      fail "没有规则集 $AUTOTEAM_RULESET_NAME：autoteam github --apply"
    elif gh_call GET "repos/$AUTOTEAM_REPO/rulesets/$id"; then
      if [ "$(jq -r '.enforcement' <<<"$GH_OUT")" != active ]; then
        fail "规则集 $AUTOTEAM_RULESET_NAME 没有启用（enforcement=$(jq -r '.enforcement' <<<"$GH_OUT")）"
      else
        approvals=$(jq -r '[.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count][0] // 0' <<<"$GH_OUT")
        if [ "$approvals" = 0 ]; then
          warn "规则集生效，但不要求审批（单账号试用模式）：评审独立性不由平台保证"
        else
          ok "规则集生效：必须走 PR、$approvals 个审批、必需检查 $(jq -r '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | join(",")' <<<"$GH_OUT")"
        fi
        if [ "$AUTOTEAM_CODEOWNERS_GATE" = off ]; then
          warn "AUTOTEAM_CODEOWNERS_GATE=off：规则集不要求 Code Owner 审批（初期开发阶段临时配置）"
        fi
        if [ "$(jq -r '[.rules[] | select(.type == "merge_queue")] | length' <<<"$GH_OUT")" = 1 ]; then ok "合并队列已启用"; fi
        if [ "$(jq -r '(.bypass_actors // []) | length' <<<"$GH_OUT")" != 0 ]; then warn "规则集有豁免名单：所有 agent 都不应该能绕过规则"; fi
      fi
    fi
  fi

  if gh secret list --repo "$AUTOTEAM_REPO" --json name --jq '.[].name' 2>/dev/null | grep -qx MULTICA_DEPLOY_HOOK; then
    ok "secret MULTICA_DEPLOY_HOOK 已设置"
  else
    fail "没有 secret MULTICA_DEPLOY_HOOK：部署结果通知不到 Planner（autoteam multica --apply）"
  fi
  if gh_call GET "repos/$AUTOTEAM_REPO/codeowners/errors"; then
    n=$(jq '.errors | length' <<<"$GH_OUT")
    if [ "$n" = 0 ]; then ok "CODEOWNERS 没有错误"; else fail "CODEOWNERS 有 $n 个错误（autoteam github 查看详情）"; fi
  else
    warn "默认分支上还没有 CODEOWNERS"
  fi
  doctor_apps
  local run
  run=$(gh run list --repo "$AUTOTEAM_REPO" --workflow gate.yml --limit 1 --json conclusion,status,headBranch,url 2>/dev/null | jq -c '.[0] // empty')
  if [ -z "$run" ]; then
    info "gate 还没有跑过（开一个 PR 就会跑）"
  elif [ "$(jq -r '.conclusion' <<<"$run")" = success ]; then
    ok "最近一次 gate 通过（$(jq -r '.headBranch' <<<"$run")）"
  else
    warn "最近一次 gate：$(jq -r '.status + " " + (.conclusion // "")' <<<"$run")  $(jq -r '.url' <<<"$run")"
  fi
  : "$level"
}

# App 的安装和私钥。doctor 可能跑在人的机器上（没有私钥），也可能跑在 agent 机器上，
# 两种情况要给出不同的结论，不要把"本机没有私钥"报成错误。
doctor_apps() {
  local role key_role id org installed row err
  org=${AUTOTEAM_REPO%%/*}
  installed=""
  if gh_call GET "orgs/$org/installations"; then installed=$GH_OUT; fi

  if [ -z "$AUTOTEAM_IMPLEMENTER_APP_ID$AUTOTEAM_REVIEWER_APP_ID" ]; then
    warn "没有配置 GitHub App：写代码和评审是同一个身份，GitHub 不允许作者批准自己的 PR，评审独立性只剩指令约束"
    return 0
  fi
  if [ "$AUTOTEAM_IMPLEMENTER_APP_ID" = "$AUTOTEAM_REVIEWER_APP_ID" ]; then
    fail "Implementer 和 Reviewer 是同一个 App：评审独立性失效，必须用两个不同的 App"
    return 0
  fi

  for role in impl review planner; do
    case $role in
      impl) id=$AUTOTEAM_IMPLEMENTER_APP_ID; key_role=implementer ;;
      review) id=$AUTOTEAM_REVIEWER_APP_ID; key_role=reviewer ;;
      planner) id=$AUTOTEAM_PLANNER_APP_ID; key_role=planner ;;
    esac
    [ -n "$id" ] || { warn "$role 没有配置 App ID"; continue; }
    if [ -n "$installed" ]; then
      row=$(jq -c --argjson id "$id" '.installations[]? | select(.app_id == $id)' <<<"$installed" 2>/dev/null | head -n 1)
      if [ -n "$row" ]; then
        ok "$role App $(jq -r '.app_slug' <<<"$row")（$id）已装在 $org"
        if [ "$role" = impl ] && [ "$(jq -r '.permissions.workflows // "none"' <<<"$row")" != write ]; then
          warn "Implementer App 没有 Workflows 权限：提不了含 .github/workflows/ 改动的 PR"
        fi
        if [ "$role" = review ] && [ "$(jq -r '.permissions.contents // "none"' <<<"$row")" != write ]; then
          fail "Reviewer App 没有 Contents 写权限：它的批准不计入必需审批数，PR 会卡在等审批"
        fi
      else
        fail "$role App $id 没有装在 $org 上"
      fi
    else
      info "$role App $id：核对不了安装状态（需要组织 admin），到 App 的 Install 页面自己确认"
    fi
    # 私钥可能在 $AUTOTEAM_DIR/local/、AUTOTEAM_KEYS_DIR 或环境变量指的路径，别去猜它在哪，
    # 直接铸一次看结果：铸得出就是好的，没有私钥和有私钥但坏了要分开报
    if err=$("$AUTOTEAM_DIR/scripts/gh-app-token.sh" "$key_role" 2>&1 >/dev/null); then
      ok "$role 的私钥能铸出 token（本机可以用这个身份操作 GitHub）"
    else
      case $err in
        *"找不到 $key_role 的私钥"*) info "本机没有 $key_role 的私钥：只有跑 $role 的那台机器需要它" ;;
        *) fail "$role 铸不出 token：${err:-跑 $AUTOTEAM_DIR/scripts/gh-app-token.sh $key_role 看报错}" ;;
      esac
    fi
  done
}

# 读一次 Multica：退出码为 0 且输出是合法 JSON 才算读到，结果放在 MC_READ_OUT。
# 读不到就报错并返回 1，调用方跳过依赖它的检查——不能把"没读到"当成空或不一致。
# 用法：doctor_mc_read <描述> <mc 参数...>
doctor_mc_read() {
  local what=$1
  shift
  if MC_READ_OUT=$(mc "$@" --output json 2>/dev/null) && jq -e . >/dev/null 2>&1 <<<"$MC_READ_OUT"; then
    return 0
  fi
  MC_READ_OUT=""
  fail "读不到 $what（mc $* 失败或输出不是 JSON）"
  hint "多半是网络或服务端慢：调大 MULTICA_HTTP_TIMEOUT 后重跑 autoteam doctor；这不代表配置有问题，先别去同步指令"
  return 1
}

# registry 里每个 agent 的 runtime 上要有它角色的 App 私钥（auditor 没有 App，不查）。
# 只有 runtime 就是本机（本机 daemon 管着它）时缺私钥才算错误：远端的 runtime 从这里
# 看不到它的磁盘，只能提示。私钥的查找规则只有 gh-app-token.sh 一份，这里调它的 --find-key。
doctor_app_keys() {
  local rows=$1 runtimes=$2 local_ids name role runtime rid err seen=" " upper id_var
  local_ids=$(mc daemon status --output json 2>/dev/null | jq -r '[.workspaces[]?.runtimes[]?] | .[]' 2>/dev/null) || local_ids=""
  while IFS=$'\t' read -r name role _ runtime _; do
    case $role in implementer|reviewer|planner) ;; *) continue ;; esac
    upper=$(printf '%s' "$role" | tr '[:lower:]' '[:upper:]')
    id_var=AUTOTEAM_${upper}_APP_ID
    [ -n "${!id_var}" ] || continue   # 没配这个角色的 App，就用不着私钥（缺 App ID 别处已经报了）
    rid=$(mc_runtime_id "$runtimes" "$runtime" || true)
    [ -n "$rid" ] || continue   # 找不到 runtime 是 autoteam multica 的事
    if ! grep -qxF "$rid" <<<"$local_ids"; then
      info "agent $name 的 runtime $runtime 不在本机：$role 的私钥要到那台机器上检查（放 AUTOTEAM_KEYS_DIR，在那里跑 autoteam doctor）"
      continue
    fi
    case $seen in *" $role "*) continue ;; esac   # 同一台机器同一个角色只报一次
    seen="$seen$role "
    if err=$("$AUTOTEAM_DIR/scripts/gh-app-token.sh" --find-key "$role" 2>&1 >/dev/null); then
      ok "本机有 $role 的私钥（agent $name 的 runtime 在本机）"
    else
      case $err in
        *"找不到 $role 的私钥"*)
          fail "本机没有 $role 的私钥，但 agent $name 的 runtime $runtime 在这台机器上：派给它的任务会在开工时铸不出 token"
          hint "把 App 的 .pem 放进 AUTOTEAM_KEYS_DIR（当前 $AUTOTEAM_KEYS_DIR；agent 每次 checkout 都是新目录，别只放仓库里），文件名要带角色名，例如 $role.pem；也可以用 AUTOTEAM_${upper}_APP_KEY 指路径" ;;
        *) fail "$role 的私钥有问题：${err:-跑 $AUTOTEAM_DIR/scripts/gh-app-token.sh --find-key $role 看报错}" ;;
      esac
    fi
  done <<EOF
$rows
EOF
}

# agent 实际绑定的 runtime / 模型 / 并发要和 registry 一致。有人在界面上直接改绑时指令不变，
# 只比指令会报"一致"，运行却因为换了 runtime 或模型失败。比对用 autoteam multica 那一份。
doctor_agent_config() {
  local name=$1 cur=$2 runtimes=$3 runtime=$4 model=$5 max=$6 rid field have want diff
  rid=$(mc_runtime_id "$runtimes" "$runtime" || true)
  if [ -z "$rid" ]; then
    fail "agent $name：registry 里的 runtime $runtime 在工作区找不到（autoteam runtimes 列出可选值）"
    return 0
  fi
  diff=$(mc_agent_config_diff "$cur" "$rid" "$model" "$max")
  [ -n "$diff" ] || return 0
  while IFS=$'\t' read -r field have want; do
    if [ "$field" = runtime ]; then
      have="$(doctor_runtime_label "$runtimes" "$have")"
      want="$runtime（$(doctor_runtime_label "$runtimes" "$rid")）"
    fi
    fail "agent $name 的 $field 与 registry 不一致：实际 $have，registry 要求 $want"
  done <<EOF
$diff
EOF
  hint "恢复成 registry 的配置：autoteam multica --apply --only agents；如果是有意迁移，先改 registry.yaml 走 PR"
}

# runtime ID 显示成「名字 ID 前 8 位」，列表里没有就原样显示 ID
doctor_runtime_label() {
  local runtimes=$1 id=$2 rt_name
  [ -n "$id" ] || { printf '（未绑定）'; return 0; }
  rt_name=$(jq -r --arg id "$id" '[.[] | select(.id == $id)][0].name // empty' <<<"$runtimes")
  printf '%s' "${rt_name:+$rt_name }${id:0:8}"
}

doctor_multica() {
  local profile=$1 ws=$2 rows=$3 runtimes agents cur name role runtime model max rid want instr catalog list f title id project last
  mc_resolve_bin
  mc_resolve_profile "$profile"
  mc_resolve_workspace "$ws"
  info "工作区 $MC_WS_NAME（profile ${MC_PROFILE:-默认}）"

  mc_resolve_api
  if [ -n "$MC_TOKEN" ] && mc_api GET /api/issue-statuses; then
    catalog=$MC_API_OUT
    local key missing=""
    while IFS=$'\t' read -r key _; do
      [ -n "$key" ] || continue
      jq -e --arg k "$key" '.statuses[] | select(.key == $k)' <<<"$catalog" >/dev/null || missing="$missing $key"
    done <<EOF
$(autoteam_statuses)
EOF
    if [ -z "$missing" ]; then ok "自定义状态齐全：shipping"; else fail "缺少自定义状态：$missing（autoteam multica --apply）"; fi
    local legacy key
    for key in approved code_review rework; do
      legacy=$(jq -r --arg k "$key" '.statuses[] | select(.key == $k and (.archived_at // null) == null) | .key' <<<"$catalog")
      [ -z "$legacy" ] || warn "发现未归档的旧状态 $key：先把其中任务移到 todo / in_review / in_progress，再在 Multica 界面归档或运行 autoteam multica --apply"
    done
  else
    warn "读不到状态列表，没法检查自定义状态"
  fi

  runtimes="" agents=""
  doctor_mc_read "runtime 列表" runtime list && runtimes=$MC_READ_OUT
  doctor_mc_read "agent 列表" agent list && agents=$MC_READ_OUT
  if [ -n "$rows" ] && [ -n "$agents" ]; then
    while IFS=$'\t' read -r name role _ runtime model max _; do
      [ -n "$name" ] || continue
      id=$(jq -r --arg n "$name" '[.[] | select(.name == $n)][0].id // empty' <<<"$agents")
      if [ -z "$id" ]; then fail "agent $name 不存在（autoteam multica --apply）"; continue; fi
      doctor_mc_read "agent $name 的配置" agent get "$id" || continue
      cur=$MC_READ_OUT
      rid=$(jq -r '.runtime_id' <<<"$cur")
      instr=$(instructions_path roles "$role.md") || { fail "找不到角色 $role 的指令文件"; continue; }
      want=$(read_file "$instr")
      if [ "$(jq -r '.instructions' <<<"$cur")" != "${want%$'\n'}" ] && [ "$(jq -r '.instructions' <<<"$cur")" != "$want" ]; then
        fail "agent $name 的指令和生效文本（$(instructions_source roles "$role.md")）不一致（指令漂移）：autoteam multica --apply"
      elif [ -z "$runtimes" ]; then
        ok "agent $name（$role）指令一致（runtime 列表没读到，没核对是否在线）"
      elif [ "$(jq -r --arg id "$rid" '.[] | select(.id == $id) | .status' <<<"$runtimes")" != online ]; then
        warn "agent $name 的 runtime 不在线"
      else
        ok "agent $name（$role）指令一致，runtime 在线"
      fi
      [ -z "$runtimes" ] || doctor_agent_config "$name" "$cur" "$runtimes" "$runtime" "$model" "$max"
      # runtime 在线不代表 agent CLI 能用（比如订阅登录过期），看最近一次运行
      last=$(mc agent tasks "$id" --output json 2>/dev/null | jq -c '[.[] | select(.status == "completed" or .status == "failed")][0] // empty')
      if [ -n "$last" ] && [ "$(jq -r '.status' <<<"$last")" = failed ]; then
        # 带上时间：这是历史记录，处理完也要等下一次成功运行才会消失
        when=$(jq -r '.completed_at // .started_at // ""' <<<"$last" | cut -c1-16 | tr T ' ')
        warn "agent $name 最近一次运行失败${when:+（$when UTC）}：$(jq -r '.error // .failure_reason // "未知原因"' <<<"$last" | head -n 1)"
        hint "登录、额度类错误要到 runtime 所在的机器上处理，比如重新登录对应的 agent CLI；已经处理过的话，这条会留到下一次成功运行"
      fi
    done <<EOF
$rows
EOF
    [ -z "$runtimes" ] || doctor_app_keys "$rows" "$runtimes"
  fi

  project=""
  if doctor_mc_read "项目列表" project list; then
    project=$(jq -r --arg t "${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}}" '[.[] | select(.title == $t)][0].id // empty' <<<"$MC_READ_OUT")
    if [ -n "$project" ]; then ok "项目 ${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}} 存在"; else fail "项目 ${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}} 不存在（autoteam multica --apply）"; fi
  fi

  doctor_mc_read "autopilot 列表" autopilot list || return 0
  list=$MC_READ_OUT
  while IFS= read -r f; do
    title=$(fm_get "$f" title)
    cur=$(jq -c --arg t "$title" '[.autopilots[]? | select(.title == $t)][0] // empty' <<<"$list")
    if [ -z "$cur" ]; then fail "autopilot「$title」不存在（autoteam multica --apply）"; continue; fi
    id=$(jq -r '.id' <<<"$cur")
    local ntrig status bound triggers
    doctor_mc_read "autopilot「$title」的触发器" autopilot get "$id" || continue
    triggers=$(jq -c '.triggers // (.autopilot.triggers // [])' <<<"$MC_READ_OUT")
    ntrig=$(jq 'length' <<<"$triggers")
    status=$(jq -r '.status' <<<"$cur")
    bound=$(jq -r '.project_id // ""' <<<"$cur")
    if [ "$ntrig" = 0 ]; then
      fail "autopilot「$title」没有触发器"
    elif [ -n "$project" ] && [ "$bound" != "$project" ]; then
      # 绑错项目时 autopilot 照常运行，只是在别的项目里找任务，什么都找不到
      fail "autopilot「$title」绑的是别的项目（autoteam multica --apply --only autopilots）"
    elif [ "$status" != active ]; then
      warn "autopilot「$title」是 $status 状态"
    else
      ok "autopilot「$title」已启用"
    fi
  done <<EOF
$(instructions_list autopilots)
EOF
}
