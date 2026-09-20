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
  if [ -f .github/CODEOWNERS ] && grep -Eq '^/ops/agents/[[:space:]]+@[A-Za-z0-9]' .github/CODEOWNERS; then
    ok "CODEOWNERS 保护 .github/、ops/agents/、Makefile、.jscpd.json"
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
  local role user
  for role in IMPL REVIEW PLANNER; do
    eval "user=\${AUTOTEAM_${role}_BOT:-}"
    [ -n "$user" ] || continue
    if gh_call GET "repos/$AUTOTEAM_REPO/collaborators/$user"; then ok "机器账号 $user 已是协作者"; else fail "机器账号 $user 还不是协作者"; fi
  done
  if [ -z "$AUTOTEAM_IMPL_BOT$AUTOTEAM_REVIEW_BOT" ]; then
    warn "没有配置机器账号：Implementer 和 Reviewer 用同一个 GitHub 账号时，GitHub 不允许批准自己的 PR"
  fi
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

doctor_multica() {
  local profile=$1 ws=$2 rows=$3 runtimes agents cur name role rid want catalog list f title id project last
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
    if [ -z "$missing" ]; then ok "自定义状态齐全：approved、code_review、rework、shipping"; else fail "缺少自定义状态：$missing（autoteam multica --apply）"; fi
  else
    warn "读不到状态列表，没法检查自定义状态"
  fi

  runtimes=$(mc runtime list --output json)
  agents=$(mc agent list --output json)
  if [ -n "$rows" ]; then
    while IFS=$'\t' read -r name role _; do
      [ -n "$name" ] || continue
      id=$(jq -r --arg n "$name" '[.[] | select(.name == $n)][0].id // empty' <<<"$agents")
      if [ -z "$id" ]; then fail "agent $name 不存在（autoteam multica --apply）"; continue; fi
      cur=$(mc agent get "$id" --output json)
      rid=$(jq -r '.runtime_id' <<<"$cur")
      want=$(read_file "ops/agents/$role.md")
      if [ "$(jq -r '.instructions' <<<"$cur")" != "${want%$'\n'}" ] && [ "$(jq -r '.instructions' <<<"$cur")" != "$want" ]; then
        fail "agent $name 的指令和 ops/agents/$role.md 不一致（指令漂移）：autoteam multica --apply"
      elif [ "$(jq -r --arg id "$rid" '.[] | select(.id == $id) | .status' <<<"$runtimes")" != online ]; then
        warn "agent $name 的 runtime 不在线"
      else
        ok "agent $name（$role）指令一致，runtime 在线"
      fi
      # runtime 在线不代表 agent CLI 能用（比如订阅登录过期），看最近一次运行
      last=$(mc agent tasks "$id" --output json 2>/dev/null | jq -c '[.[] | select(.status == "completed" or .status == "failed")][0] // empty')
      if [ -n "$last" ] && [ "$(jq -r '.status' <<<"$last")" = failed ]; then
        warn "agent $name 最近一次运行失败：$(jq -r '.error // .failure_reason // "未知原因"' <<<"$last" | head -n 1)"
        hint "登录、额度类错误要到 runtime 所在的机器上处理，比如重新登录对应的 agent CLI"
      fi
    done <<EOF
$rows
EOF
  fi

  project=$(mc project list --output json | jq -r --arg t "${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}}" '[.[] | select(.title == $t)][0].id // empty')
  if [ -n "$project" ]; then ok "项目 ${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}} 存在"; else fail "项目 ${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}} 不存在（autoteam multica --apply）"; fi

  list=$(mc autopilot list --output json)
  for f in ops/agents/autopilots/*.md; do
    [ -f "$f" ] || continue
    title=$(fm_get "$f" title)
    cur=$(jq -c --arg t "$title" '[.autopilots[]? | select(.title == $t)][0] // empty' <<<"$list")
    if [ -z "$cur" ]; then fail "autopilot「$title」不存在（autoteam multica --apply）"; continue; fi
    id=$(jq -r '.id' <<<"$cur")
    local ntrig status
    ntrig=$(mc_autopilot_triggers "$id" | jq 'length')
    status=$(jq -r '.status' <<<"$cur")
    if [ "$ntrig" = 0 ]; then
      fail "autopilot「$title」没有触发器"
    elif [ "$status" != active ]; then
      warn "autopilot「$title」是 $status 状态"
    else
      ok "autopilot「$title」已启用"
    fi
  done
}
