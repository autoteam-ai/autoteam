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
  doctor_retired_keys "$root"
  doctor_launcher "$root"
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
    warn "没有 $AUTOTEAM_LOCK_REL：运行 autoteam upgrade 生成，升级靠它判断哪些文件改过"
  elif ! v=$(jq -er '.version' "$AUTOTEAM_LOCK_REL" 2>/dev/null); then
    fail "$AUTOTEAM_LOCK_REL 读不出 version：不是合法的 lock，运行 autoteam upgrade 重新生成"
  elif [ "$v" != "$current" ]; then
    warn "$AUTOTEAM_LOCK_REL 记录的版本是 $v，当前 autoteam 是 $current：运行 autoteam upgrade"
  else
    ok "$AUTOTEAM_LOCK_REL 版本 $v，与当前 autoteam 一致"
  fi
}

# autoteam.conf 里已合并的旧配置项不再生效，提示并入了哪个新键
doctor_retired_keys() {
  local old new
  while read -r old new; do
    [ -n "$old" ] || continue
    if grep -qE "^[[:space:]]*${old}[[:space:]]*=" "$1/$AUTOTEAM_CONF_REL"; then
      warn "$AUTOTEAM_CONF_REL 里的 $old 已合并到 $new，旧键被忽略：改用 $new"
    fi
  done <<EOF
$(autoteam_conf_retired)
EOF
}

# runbook 不同步到 Multica，不做漂移对比；只提示 eject 了但包内已经没有的那份
doctor_runbooks() {
  local f name
  for f in "$AUTOTEAM_INSTRUCTIONS_REL"/runbooks/*.md; do
    [ -f "$f" ] || continue
    name=${f##*/}
    [ -f "$AUTOTEAM_HOME/instructions/runbooks/$name" ] || warn "$f 在 autoteam 包内已不存在，确认还要不要保留"
  done
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
  doctor_runbooks
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

# 在没有本机 skill 的独立 worktree 里执行 agent 开工的原命令。
doctor_launcher() {
  local root=$1 checkout output rc home cache
  if [ ! -f "$root/autoteam" ]; then
    fail "缺少 ./autoteam：运行 autoteam init autoteam，提交后让新 checkout 使用"
    return 0
  fi
  if [ ! -x "$root/autoteam" ]; then
    fail "./autoteam 不可执行：运行 chmod +x autoteam 并提交"
    return 0
  fi
  if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    warn "还没有提交，无法预跑 ./autoteam：干净 checkout 只检查已提交的 HEAD，不包含未提交的改动；提交后重跑 autoteam doctor"
    return 0
  fi
  info "干净 checkout 预跑只检查已提交的 HEAD，不包含未提交的改动"
  checkout=$(autoteam_tmpdir)/doctor-checkout
  home=$(autoteam_tmpdir)/doctor-home
  cache=$home/.cache
  mkdir -p "$home" "$cache"
  if [ -d "$HOME/.multica" ]; then
    ln -s "$HOME/.multica" "$home/.multica"
  fi
  if ! git worktree add --detach "$checkout" HEAD >/dev/null 2>&1; then
    fail "创建干净 checkout 失败：检查 git worktree 状态后重跑 autoteam doctor"
    return 0
  fi
  if [ ! -f "$checkout/autoteam" ]; then
    fail "干净 checkout 缺少 ./autoteam：运行 autoteam init autoteam，提交并合并入口文件"
  else
    output=$(cd "$checkout" && HOME="$home" XDG_CACHE_HOME="$cache" bash ./autoteam status --check 2>&1) && rc=0 || rc=$?
    if [ "$rc" = 0 ]; then
      ok "干净 checkout 的 bash ./autoteam status --check 可运行"
    elif [[ $output == *"已暂停"* ]]; then
      ok "干净 checkout 的 bash ./autoteam status --check 可运行（项目已暂停）"
    else
      fail "干净 checkout 的 bash ./autoteam status --check 失败：$output；检查入口 ref、网络和缓存，修复后重跑 autoteam doctor"
    fi
  fi
  git worktree remove --force "$checkout" >/dev/null 2>&1 ||
    warn "清理 doctor 的临时 worktree 失败：运行 git worktree prune"
}

# 指令漂移是拿本机 CLI 的指令文本和 Multica 上的对比；入口固定的版本不是本机 CLI 时，
# 对比的就不是 agent 实际会读到的版本，结论不可信。
doctor_pinned_version() {
  local pinned local_ref
  pinned=$(sed -n 's/^AUTOTEAM_REF=\([0-9a-f]\{40\}\)$/\1/p' autoteam 2>/dev/null | head -n 1)
  [ -n "$pinned" ] || return 0   # 入口缺失或格式不对，doctor_launcher 已报
  local_ref=$(autoteam_local_ref)
  if [ -z "$local_ref" ]; then
    warn "本机 autoteam 没有 source-ref，无法核对它与 ./autoteam 固定的版本 ${pinned:0:12} 是否一致"
  elif [ "$local_ref" != "$pinned" ]; then
    fail "本机 autoteam（${local_ref:0:12}）与 ./autoteam 固定的版本（${pinned:0:12}）不一致：指令漂移的比对结果不代表 agent 读到的版本"
    hint "用固定版本的 CLI 重跑：bash ./autoteam doctor；要升级固定版本先 autoteam upgrade autoteam 并合并"
  else
    ok "本机 autoteam 与 ./autoteam 固定的版本一致（${pinned:0:12}）"
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
  local repo=$GH_OUT level=standard id approvals n secrets
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

  if secrets=$(gh secret list --repo "$AUTOTEAM_REPO" --json name --jq '.[].name' 2>/dev/null) && grep -qx MULTICA_DEPLOY_HOOK <<<"$secrets"; then
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

# registry 里每个 agent 的 runtime 上要有它所用身份的 App 私钥（auditor 用 planner 身份）。
# 只有 runtime 就是本机（本机 daemon 管着它）时缺私钥才算错误：远端的 runtime 从这里
# 看不到它的磁盘，只能提示。私钥的查找规则只有 gh-app-token.sh 一份，这里调它的 --find-key。
doctor_app_keys() {
  local rows=$1 runtimes=$2 local_ids name role key_role runtime rid err upper id_var machine i found
  local remote_machines=() remote_roles=()
  local_ids=$(mc daemon status --output json 2>/dev/null | jq -r '[.workspaces[]?.runtimes[]?] | .[]' 2>/dev/null) || local_ids=""
  while IFS=$'\t' read -r name role _ runtime _; do
    case $role in
      implementer|reviewer|planner) key_role=$role ;;
      auditor) key_role=planner ;;
      *) continue ;;
    esac
    upper=$(printf '%s' "$key_role" | tr '[:lower:]' '[:upper:]')
    id_var=AUTOTEAM_${upper}_APP_ID
    [ -n "${!id_var}" ] || continue   # 没配这个角色的 App，就用不着私钥（缺 App ID 别处已经报了）
    rid=$(mc_runtime_id "$runtimes" "$runtime" || true)
    [ -n "$rid" ] || continue   # 找不到 runtime 是 autoteam multica 的事
    if ! grep -qxF "$rid" <<<"$local_ids"; then
      machine=${runtime##*@}
      found=-1
      for ((i=0; i<${#remote_machines[@]}; i++)); do
        [ "${remote_machines[$i]}" = "$machine" ] && { found=$i; break; }
      done
      if [ "$found" -lt 0 ]; then
        found=${#remote_machines[@]}
        remote_machines+=("$machine")
        remote_roles+=("")
      fi
      case " ${remote_roles[$found]} " in
        *" $key_role "*) ;;
        *) remote_roles[found]="${remote_roles[found]:+${remote_roles[found]} }$key_role" ;;
      esac
      continue
    fi
    if err=$("$AUTOTEAM_DIR/scripts/gh-app-token.sh" --find-key "$key_role" 2>&1 >/dev/null); then
      ok "本机有 $key_role 的私钥（agent $name 的 runtime 在本机；$role 使用 $key_role 身份）"
    else
      case $err in
        *"找不到 $key_role 的私钥"*)
          fail "本机没有 $key_role 的私钥，但 agent $name 的 runtime $runtime 在这台机器上（$role 使用 $key_role 身份）：派给它的任务会在开工时铸不出 token"
          hint "把 App 的 .pem 放进 AUTOTEAM_KEYS_DIR（当前 $AUTOTEAM_KEYS_DIR；agent 每次 checkout 都是新目录，别只放仓库里），文件名要带角色名，例如 $key_role.pem；也可以用 AUTOTEAM_${upper}_APP_KEY 指路径" ;;
        *) fail "$role 使用的 $key_role 私钥有问题：${err:-跑 $AUTOTEAM_DIR/scripts/gh-app-token.sh --find-key $key_role 看报错}" ;;
      esac
    fi
  done <<EOF
$rows
EOF
  for ((i=0; i<${#remote_machines[@]}; i++)); do
    info "远端机器 ${remote_machines[$i]} 的私钥待检查（角色：${remote_roles[$i]}；放 AUTOTEAM_KEYS_DIR，当前 $AUTOTEAM_KEYS_DIR；在该机器运行 autoteam doctor）"
  done
}

# agent 实际绑定的 runtime / 模型 / 并发要和 registry 一致。有人在界面上直接改绑时指令不变，
# 只比指令会报"一致"，运行却因为换了 runtime 或模型失败。比对用 autoteam multica 那一份。
doctor_agent_config() {
  local name=$1 cur=$2 runtimes=$3 runtime=$4 model=$5 max=$6 rid field have want diff line
  rid=$(mc_runtime_id "$runtimes" "$runtime" || true)
  if [ -z "$rid" ]; then
    fail "agent $name：registry 里的 runtime $runtime 在工作区找不到（autoteam runtimes 列出可选值）"
    return 0
  fi
  diff=$(mc_agent_config_diff "$cur" "$rid" "$model" "$max")
  [ -n "$diff" ] || return 0
  # 不能用 IFS=$'\t' read 拆：tab 是空白分隔符，相邻的 tab 会被合并，实际值为空（未绑定）时
  # 要求值会被读进实际值里。按 tab 逐段切，空字段才保得住。
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    field=${line%%$'\t'*} line=${line#*$'\t'}
    have=${line%%$'\t'*} want=${line#*$'\t'}
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
  [ -n "$id" ] || { printf '未绑定'; return 0; }
  rt_name=$(jq -r --arg id "$id" '[.[] | select(.id == $id)][0].name // empty' <<<"$runtimes")
  printf '%s' "${rt_name:+$rt_name }${id:0:8}"
}

doctor_multica() {
  local profile=$1 ws=$2 rows=$3 runtimes agents cur name role runtime model max rid want list f title id project last notes note_count
  mc_resolve_bin
  mc_resolve_profile "$profile"
  mc_require_login
  mc_resolve_workspace "$ws"
  info "工作区 $MC_WS_NAME（profile ${MC_PROFILE:-默认}）"
  doctor_pinned_version

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
      want=$(instructions_role_text "$role") || { fail "找不到角色 $role 的指令文件"; continue; }
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

  local pause_marker="" pause_reported=0
  project=""
  if doctor_mc_read "项目列表" project list; then
    project=$(jq -r --arg t "${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}}" '[.[] | select(.title == $t)][0].id // empty' <<<"$MC_READ_OUT")
    if [ -n "$project" ]; then
      ok "项目 ${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}} 存在"
      if notes=$(mc_project_note_ids "$project"); then
        note_count=$(grep -c . <<<"$notes" || true)
        case $note_count in
          0) fail "项目缺少运营笔记（autoteam multica --apply --only project）" ;;
          1)
            ok "项目有且只有一条运营笔记"
            if doctor_mc_read "运营笔记暂停标记" issue get "$notes"; then
              pause_marker=$(stop_parse_marker "$MC_READ_OUT") || {
                fail "暂停标记格式错误"
                pause_marker=""
              }
            fi
            ;;
          *) fail "项目有 $note_count 条运营笔记，应只有一条；请人工处理重复任务" ;;
        esac
      else
        fail "读取项目运营笔记失败"
      fi
    else
      fail "项目 ${AUTOTEAM_MULTICA_PROJECT:-${AUTOTEAM_REPO##*/}} 不存在（autoteam multica --apply）"
    fi
  fi

  doctor_mc_read "autopilot 列表" autopilot list || return 0
  list=$MC_READ_OUT
  mc_obsolete_autopilots_hint "$(mc_obsolete_autopilots "$list" "$project")"
  while IFS= read -r f; do
    title=$(fm_get "$f" title)
    local name
    name=${f##*/} name=${name%.md}
    # 同一工作区的别的项目也会有同名 autopilot，只认绑在本项目上的
    id=$(mc_autopilot_id "$list" "$title" "$project")
    if ! autopilot_selected "$name" "$id"; then
      if [ -z "$id" ]; then continue; fi
      autopilot_unlisted_hint "$title"
    fi
    if [ -z "$id" ]; then fail "本项目没有 autopilot「$title」（autoteam multica --apply）"; continue; fi
    local ntrig status triggers
    doctor_mc_read "autopilot「$title」的触发器" autopilot get "$id" || continue
    local body actual
    body=$(instructions_with_preamble "$(fm_body "$f")")
    actual=$(jq -r '(.autopilot // .).description // empty' <<<"$MC_READ_OUT")
    if [ "$actual" != "$body" ]; then
      fail "autopilot「$title」的指令和生效文本不一致（指令漂移）：autoteam multica --apply"
    fi
    triggers=$(jq -c '.triggers // (.autopilot.triggers // [])' <<<"$MC_READ_OUT")
    ntrig=$(jq 'length' <<<"$triggers")
    status=$(jq -r --arg id "$id" '.autopilots[] | select(.id == $id) | .status' <<<"$list")
    if [ "$ntrig" = 0 ]; then
      fail "autopilot「$title」没有触发器"
    elif [ "$status" = paused ] && [ -n "$pause_marker" ]; then
      if [ "$pause_reported" = 0 ]; then
        warn "项目已暂停（时间：$(jq -r '.at' <<<"$pause_marker")，操作人：$(jq -r '.operator.name // .operator.id' <<<"$pause_marker")）：paused 的 autopilot 均为暂停状态；恢复用 autoteam resume --apply"
        pause_reported=1
      fi
    elif [ "$status" != active ]; then
      warn "autopilot「$title」是 $status 状态"
    else
      ok "autopilot「$title」已启用"
    fi
  done <<EOF
$(instructions_list autopilots)
EOF
  mc_print_links
}
