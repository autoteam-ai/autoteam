# shellcheck shell=bash
# autoteam github：仓库设置、规则集、environment、机器账号。默认只预览。

github_usage() {
  cat <<'EOF'
用法：autoteam github [选项]

按 ops/agents/autoteam.conf 配置 GitHub 仓库。默认只预览，加 --apply 才执行。

  --apply                  执行改动
  --trial                  单账号试用模式：规则集不要求审批（写代码和评审用同一个 GitHub 账号时用）
  --bots impl=<用户>,review=<用户>,planner=<用户>
                           邀请机器账号为协作者（也可以写在 autoteam.conf 的 AUTOTEAM_*_BOT）
  --repo <owner/name>      覆盖 autoteam.conf 里的仓库

会做的事：
  1. 仓库设置：允许自动合并、合并后删分支、只保留 squash 合并
  2. 规则集 autoteam（默认分支）：禁止删除和强推、必须走 PR、1 个审批、
     新提交作废旧审批、规则文件要 Code Owner 审批、最后一次推送要别人批准、
     必需检查 check（只认 GitHub Actions 上报）、组织仓库再加合并队列
  3. 部署 environment（autoteam.conf 的 AUTOTEAM_DEPLOY_ENVIRONMENT）
  4. 邀请机器账号，打印每个账号的 token 权限
EOF
}

GH_ACTIONS_APP_ID=15368
AUTOTEAM_RULESET_NAME=autoteam

# gh api 包装：结果（含错误信息）放在 GH_OUT，返回 gh 的退出码
gh_call() {
  local method=$1 path=$2 body=${3:-} rc=0
  if [ -n "$body" ]; then
    GH_OUT=$(printf '%s' "$body" | gh api -X "$method" "$path" --input - 2>&1) || rc=$?
  else
    GH_OUT=$(gh api -X "$method" "$path" 2>&1) || rc=$?
  fi
  return $rc
}

cmd_github() {
  local trial=0 bots=""
  while [ $# -gt 0 ]; do
    case $1 in
      --apply) AUTOTEAM_APPLY=1; shift ;;
      --trial) trial=1; shift ;;
      --bots) bots=$2; shift 2 ;;
      --repo) AUTOTEAM_REPO=$2; shift 2 ;;
      -h|--help) github_usage; return 0 ;;
      *) github_usage >&2; die "未知选项：$1" ;;
    esac
  done
  need_cmd gh "安装：https://cli.github.com"
  need_cmd jq
  local root
  root=$(repo_root)
  cd "$root" || die "进不去 $root"
  conf_load "$root"
  [ -n "$AUTOTEAM_REPO" ] || die "autoteam.conf 里没有 AUTOTEAM_REPO，先运行 autoteam init"
  gh auth status >/dev/null 2>&1 || die "gh 还没登录：gh auth login"

  section "仓库 $AUTOTEAM_REPO"
  local repo_json owner_type visibility level rulesets_ok=1
  gh_call GET "repos/$AUTOTEAM_REPO" || die "读不到仓库 $AUTOTEAM_REPO：$GH_OUT"
  repo_json=$GH_OUT
  owner_type=$(jq -r '.owner.type' <<<"$repo_json")
  visibility=$(jq -r '.visibility' <<<"$repo_json")
  [ "$(jq -r '.permissions.admin' <<<"$repo_json")" = true ] || die "需要 $AUTOTEAM_REPO 的管理员权限"

  if ! gh_call GET "repos/$AUTOTEAM_REPO/rulesets"; then
    case $GH_OUT in
      *"Upgrade to GitHub Pro"*) rulesets_ok=0 ;;
      *) die "读取规则集失败：$GH_OUT" ;;
    esac
  fi
  if [ "$rulesets_ok" = 0 ]; then
    level=none
  elif [ "$owner_type" = Organization ]; then
    level=full
  else
    level=standard
  fi
  info "所有者类型 $owner_type，可见性 $visibility"
  github_print_capability "$level"

  section "仓库设置"
  github_settings "$repo_json"

  section "规则集 $AUTOTEAM_RULESET_NAME"
  if [ "$level" = none ]; then
    warn "这个仓库用不了规则集（GitHub Free 的私有仓库），跳过"
  else
    github_ruleset "$trial" "$level"
  fi

  section "部署 environment"
  github_environment "$level"

  section "机器账号"
  github_bots "$bots" "$owner_type"

  section "其他检查"
  github_extra_checks

  section "结论"
  github_conclusion "$level" "$trial"
  preview_footer
}

github_print_capability() {
  case $1 in
    full)
      ok "规则集、自动合并、合并队列都可用（组织仓库）" ;;
    standard)
      ok "规则集、自动合并可用"
      info "合并队列只有组织仓库支持，这里不配置" ;;
    none)
      warn "规则集、分支保护、自动合并都不可用：GitHub Free 的私有仓库没有这些功能"
      hint "要拿到平台闸门：仓库改为公开、升级 GitHub Pro，或迁到 Team 套餐的组织" ;;
  esac
}

github_settings() {
  local repo_json=$1 want diff
  want='{"allow_auto_merge":true,"delete_branch_on_merge":true,"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false,"squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}'
  diff=$(jq -c --argjson want "$want" '. as $cur | $want | with_entries(select($cur[.key] != .value))' <<<"$repo_json")
  if [ "$diff" = "{}" ]; then
    ok "已符合：允许自动合并、合并后删分支、只保留 squash"
    return 0
  fi
  planned "PATCH repos/$AUTOTEAM_REPO $diff"
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  if ! gh_call PATCH "repos/$AUTOTEAM_REPO" "$diff"; then
    # 有的套餐不允许打开自动合并，去掉这一项再试
    diff=$(jq -c 'del(.allow_auto_merge)' <<<"$diff")
    gh_call PATCH "repos/$AUTOTEAM_REPO" "$diff" || { fail "修改仓库设置失败：$GH_OUT"; return 0; }
  fi
  gh_call GET "repos/$AUTOTEAM_REPO" || { fail "回读仓库设置失败：$GH_OUT"; return 0; }
  local missed
  missed=$(jq -r --argjson want "$want" '. as $cur | $want | to_entries[] | select($cur[.key] != .value) | .key' <<<"$GH_OUT")
  if [ -z "$missed" ]; then
    ok "仓库设置已更新"
  else
    warn "这些设置没有生效（通常是套餐限制）：$(printf '%s' "$missed" | tr '\n' ' ')"
  fi
}

github_ruleset_json() {
  local approvals=$1 code_owner=$2 last_push=$3 mq=$4
  jq -n --argjson approvals "$approvals" --argjson code_owner "$code_owner" \
    --argjson last_push "$last_push" --argjson mq "$mq" \
    --arg check "$AUTOTEAM_CHECK_NAME" --arg name "$AUTOTEAM_RULESET_NAME" --argjson app "$GH_ACTIONS_APP_ID" '
    {
      name: $name,
      target: "branch",
      enforcement: "active",
      bypass_actors: [],
      conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
      rules: ([
        { type: "deletion" },
        { type: "non_fast_forward" },
        { type: "pull_request", parameters: {
            required_approving_review_count: $approvals,
            dismiss_stale_reviews_on_push: true,
            require_code_owner_review: $code_owner,
            require_last_push_approval: $last_push,
            required_review_thread_resolution: false,
            allowed_merge_methods: ["squash"] } },
        { type: "required_status_checks", parameters: {
            strict_required_status_checks_policy: false,
            do_not_enforce_on_create: false,
            required_status_checks: [ { context: $check, integration_id: $app } ] } }
      ] + (if $mq then [ { type: "merge_queue", parameters: {
            check_response_timeout_minutes: 60,
            grouping_strategy: "ALLGREEN",
            max_entries_to_build: 5,
            max_entries_to_merge: 5,
            merge_method: "SQUASH",
            min_entries_to_merge: 1,
            min_entries_to_merge_wait_minutes: 5 } } ] else [] end))
    }'
}

# 已有规则集是否已经包含想要的规则（只比较我们关心的字段）
github_ruleset_matches() {
  local have=$1 want=$2
  jq -e --argjson want "$want" '
    . as $have
    | ($have.enforcement == "active")
      and (($have.bypass_actors // []) | length == 0)
      and ([$want.rules[] as $w
            | [$have.rules[] | select(.type == $w.type) | (.parameters // {}) | contains($w.parameters // {})]
            | any] | all)
      and ([$have.rules[].type] | sort) == ([$want.rules[].type] | sort)
  ' <<<"$have" >/dev/null
}

github_ruleset() {
  # require_last_push_approval 刻意不开。它要的是"批准人不能是最后推送的人"，
  # 而 dismiss_stale_reviews_on_push 已经把它防的风险覆盖了：Implementer 推了新提交，
  # 之前的批准全部作废，Reviewer 必须重新看。对 agent 流程它一点保护都不增加
  # （Implementer 和 Reviewer 本来就是不同账号），却会卡住人改规则文件：
  # ops/agents/ 受 CODEOWNERS 保护只有人能批，而人又是推的那个，于是谁都合不了。
  local trial=$1 level=$2 approvals=1 code_owner=true last_push=false mq=false want id
  if [ "$trial" = 1 ]; then
    approvals=0 code_owner=false
    warn "试用模式：不要求审批，也不要求 Code Owner 审批（写代码和评审是同一个 GitHub 账号）"
  fi
  [ "$level" = full ] && mq=true
  want=$(github_ruleset_json "$approvals" "$code_owner" "$last_push" "$mq")

  gh_call GET "repos/$AUTOTEAM_REPO/rulesets" || { fail "读取规则集失败：$GH_OUT"; return 0; }
  id=$(jq -r --arg n "$AUTOTEAM_RULESET_NAME" '.[] | select(.name == $n) | .id' <<<"$GH_OUT" | head -n1)

  if [ -n "$id" ]; then
    gh_call GET "repos/$AUTOTEAM_REPO/rulesets/$id" || { fail "读取规则集 $id 失败：$GH_OUT"; return 0; }
    if github_ruleset_matches "$GH_OUT" "$want"; then
      ok "规则集已符合（id $id）"
      return 0
    fi
    planned "PUT repos/$AUTOTEAM_REPO/rulesets/$id（更新为 $(github_ruleset_summary "$want")）"
    [ "$AUTOTEAM_APPLY" = 1 ] || return 0
    github_ruleset_write PUT "repos/$AUTOTEAM_REPO/rulesets/$id" "$want"
  else
    planned "POST repos/$AUTOTEAM_REPO/rulesets（$(github_ruleset_summary "$want")）"
    [ "$AUTOTEAM_APPLY" = 1 ] || return 0
    github_ruleset_write POST "repos/$AUTOTEAM_REPO/rulesets" "$want"
  fi
}

github_ruleset_summary() {
  jq -r '[.rules[].type] | join("、")' <<<"$1"
}

github_ruleset_write() {
  local method=$1 path=$2 want=$3
  if gh_call "$method" "$path" "$want"; then
    ok "规则集已写入（id $(jq -r .id <<<"$GH_OUT")）"
    return 0
  fi
  case $GH_OUT in
    *merge_queue*|*"merge queue"*|*"Merge queue"*)
      warn "这个仓库不支持合并队列，去掉后重试"
      want=$(jq -c '.rules |= map(select(.type != "merge_queue"))' <<<"$want")
      if gh_call "$method" "$path" "$want"; then
        ok "规则集已写入（无合并队列，id $(jq -r .id <<<"$GH_OUT")）"
        return 0
      fi
      ;;
  esac
  fail "写规则集失败：$GH_OUT"
}

github_environment() {
  local level=$1 env=$AUTOTEAM_DEPLOY_ENVIRONMENT
  if [ -z "$env" ]; then
    info "autoteam.conf 没配置 AUTOTEAM_DEPLOY_ENVIRONMENT，deploy.yml 不使用 environment"
    return 0
  fi
  if gh_call GET "repos/$AUTOTEAM_REPO/environments/$env"; then
    ok "environment $env 已存在"
    return 0
  fi
  planned "PUT repos/$AUTOTEAM_REPO/environments/$env"
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  if gh_call PUT "repos/$AUTOTEAM_REPO/environments/$env" '{}'; then
    ok "已创建 environment $env"
  else
    warn "创建 environment 失败：$GH_OUT"
    hint "GitHub Free 的私有仓库不支持 environment：把 autoteam.conf 的 AUTOTEAM_DEPLOY_ENVIRONMENT 置空，并删掉 deploy.yml、rollback.yml 里的 environment 行"
  fi
}

github_bots() {
  local bots=$1 owner_type=$2 pair role user any=0
  local impl=$AUTOTEAM_IMPL_BOT review=$AUTOTEAM_REVIEW_BOT planner=$AUTOTEAM_PLANNER_BOT
  if [ -n "$bots" ]; then
    for pair in $(printf '%s' "$bots" | tr ',' ' '); do
      role=${pair%%=*} user=${pair#*=}
      case $role in
        impl|implementer) impl=$user ;;
        review|reviewer) review=$user ;;
        planner) planner=$user ;;
        *) die "--bots 只认 impl / review / planner：$pair" ;;
      esac
    done
  fi
  for pair in "impl:$impl" "review:$review" "planner:$planner"; do
    role=${pair%%:*} user=${pair#*:}
    [ -n "$user" ] || continue
    any=1
    github_invite "$role" "$user"
  done
  if [ "$any" = 0 ]; then
    warn "没有配置机器账号：写代码和评审用的是同一个 GitHub 账号，GitHub 不允许作者批准自己的 PR"
    hint "准备好账号后写进 autoteam.conf 的 AUTOTEAM_IMPL_BOT / AUTOTEAM_REVIEW_BOT / AUTOTEAM_PLANNER_BOT，或用 --bots 传入"
    return 0
  fi
  github_token_table "$owner_type"
}

github_invite() {
  local role=$1 user=$2
  if gh_call GET "repos/$AUTOTEAM_REPO/collaborators/$user"; then
    ok "$role 账号 $user 已是协作者"
    return 0
  fi
  if gh_call GET "repos/$AUTOTEAM_REPO/invitations" \
    && jq -e --arg u "$user" '.[] | select(.invitee.login == $u)' <<<"$GH_OUT" >/dev/null; then
    warn "$role 账号 $user 的邀请还没接受：用该账号登录 GitHub 接受邀请"
    return 0
  fi
  planned "PUT repos/$AUTOTEAM_REPO/collaborators/$user（permission=push）"
  [ "$AUTOTEAM_APPLY" = 1 ] || return 0
  if gh_call PUT "repos/$AUTOTEAM_REPO/collaborators/$user" '{"permission":"push"}'; then
    ok "已邀请 $user，需要用该账号接受邀请"
  else
    fail "邀请 $user 失败：$GH_OUT"
  fi
}

github_token_table() {
  info ""
  info "每个机器账号只在自己的机器上登录 gh，token 只给最小权限、设过期时间："
  if [ "$1" = Organization ]; then
    info "  impl    fine-grained，只选本仓库：Contents 读写、Pull requests 读写（推分支、开 PR、开自动合并）"
    info "  review  fine-grained，只选本仓库：Pull requests 读写、Contents 只读（提交评审）"
    info "  planner fine-grained，只选本仓库：Actions 读写、Contents 只读、Pull requests 只读（查 PR、触发回滚）"
    hint "机器账号要是组织成员才能用 fine-grained token；组织需要允许 fine-grained token"
  else
    info "  个人账号的仓库：协作者不能用 fine-grained token，只能用 classic token（repo 范围，设过期时间）"
    info "  impl 的 token 不要勾 workflow 范围，这样它推不了 .github/workflows 的改动"
    hint "想按最小权限给 token，把仓库迁到组织下，机器账号作为组织成员"
  fi
}

github_extra_checks() {
  if gh_call GET "repos/$AUTOTEAM_REPO/codeowners/errors"; then
    local n
    n=$(jq '.errors | length' <<<"$GH_OUT")
    if [ "$n" = 0 ]; then
      ok "CODEOWNERS 没有错误"
    else
      fail "CODEOWNERS 有 $n 个错误："
      jq -r '.errors[] | "     第 \(.line) 行：\(.message)"' <<<"$GH_OUT"
    fi
  else
    info "默认分支上还没有 CODEOWNERS（合并 autoteam init 生成的文件后再检查）"
  fi
  if gh secret list --repo "$AUTOTEAM_REPO" --json name --jq '.[].name' 2>/dev/null | grep -qx MULTICA_DEPLOY_HOOK; then
    ok "secret MULTICA_DEPLOY_HOOK 已设置"
  else
    info "secret MULTICA_DEPLOY_HOOK 还没设置，autoteam multica --apply 会创建部署 webhook 并写入"
  fi
}

github_conclusion() {
  local level=$1 trial=$2
  case $level in
    full) ok "平台闸门完整：规则集 + 自动合并 + 合并队列，所有 agent 都绕不过" ;;
    standard) ok "规则集 + 自动合并生效；没有合并队列，几个 PR 同时合并时靠合并后的部署和验收兜底" ;;
    none)
      warn "合并闸门没有生效：谁能合并只靠 agent 指令约束"
      hint "这种仓库里 Reviewer 在检查通过后自己执行合并（降级模式），文档 docs/concepts/guardrails.md 有说明" ;;
  esac
  if [ "$trial" = 1 ] && [ "$level" != none ]; then
    warn "单账号试用模式：评审独立性不由平台保证。补齐机器账号后去掉 --trial 重新运行"
  fi
}
