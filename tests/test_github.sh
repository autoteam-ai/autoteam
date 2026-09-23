# shellcheck shell=bash
# autoteam github：预览不写、三种套餐、试用模式、已有规则集、GitHub App

github_ready_repo() {
  new_repo acme/shop
  STUB_SCENARIO=${1:-user-public} autoteam_stub init --owner alice >/dev/null
  : > "$STUB_LOG"
}

t_github_preview_makes_no_writes() {
  github_ready_repo
  out=$(autoteam_stub github)
  assert_contains "$out" "[预览] PATCH repos/acme/shop"
  assert_contains "$out" "[预览] POST repos/acme/shop/rulesets"
  assert_contains "$out" "以上是预览"
  assert_no_log "-X PATCH"
  assert_no_log "-X POST"
  assert_no_log "-X PUT"
}

t_github_user_public_apply() {
  github_ready_repo
  out=$(autoteam_stub github --apply)
  assert_contains "$out" "仓库设置已更新"
  assert_contains "$out" "规则集已写入"
  assert_log 'BODY PATCH repos/acme/shop {"allow_auto_merge":true,"delete_branch_on_merge":true'
  rs=$STUB_STATE/ruleset.json
  assert_eq "$(jq -r '.bypass_actors | length' "$rs")" 0
  assert_eq "$(jq -r '.conditions.ref_name.include[0]' "$rs")" "~DEFAULT_BRANCH"
  assert_eq "$(jq -c '[.rules[].type]' "$rs")" '["deletion","non_fast_forward","pull_request","required_status_checks"]'
  assert_eq "$(jq -c '.rules[2].parameters | [.required_approving_review_count, .require_code_owner_review, .require_last_push_approval, .dismiss_stale_reviews_on_push, .allowed_merge_methods]' "$rs")" '[1,true,true,true,["squash"]]'
  assert_eq "$(jq -c '.rules[3].parameters.required_status_checks' "$rs")" '[{"context":"check","integration_id":15368}]'
  # 再跑一次：规则集已符合，不再写
  : > "$STUB_LOG"
  out=$(autoteam_stub github --apply)
  assert_contains "$out" "规则集已符合"
  assert_contains "$out" "已符合：允许自动合并"
  assert_no_log "-X PUT repos/acme/shop/rulesets"
}

t_github_codeowners_gate_off_preserves_review_approval() {
  github_ready_repo
  echo 'AUTOTEAM_CODEOWNERS_GATE=off' >> .autoteam/autoteam.conf
  out=$(autoteam_stub github --apply)
  assert_contains "$out" "保留 1 个审批，关闭 Code Owner 审批"
  assert_eq "$(jq -c '.rules[2].parameters | [.required_approving_review_count, .require_code_owner_review, .require_last_push_approval]' "$STUB_STATE/ruleset.json")" '[1,false,true]'
  # 再跑一次必须与 off 的期望值匹配，不能把 Code Owner 审批写回去。
  : > "$STUB_LOG"
  out=$(autoteam_stub github --apply)
  assert_contains "$out" "规则集已符合"
  assert_no_log "-X PUT repos/acme/shop/rulesets"
}

t_github_org_public_adds_merge_queue() {
  github_ready_repo org-public
  out=$(STUB_SCENARIO=org-public autoteam_stub github --apply)
  assert_contains "$out" "合并队列都可用"
  assert_eq "$(jq -r '.rules[-1].type' "$STUB_STATE/ruleset.json")" merge_queue
  assert_eq "$(jq -r '.rules[-1].parameters.merge_method' "$STUB_STATE/ruleset.json")" SQUASH
}

t_github_org_retries_without_merge_queue() {
  github_ready_repo org-no-mq
  out=$(STUB_SCENARIO=org-no-mq autoteam_stub github --apply)
  assert_contains "$out" "不支持合并队列，去掉后重试"
  assert_contains "$out" "规则集已写入（无合并队列"
  assert_eq "$(jq '[.rules[] | select(.type == "merge_queue")] | length' "$STUB_STATE/ruleset.json")" 0
}

t_github_free_private_degrades() {
  github_ready_repo free-private
  out=$(STUB_SCENARIO=free-private autoteam_stub github --apply)
  assert_contains "$out" "规则集、分支保护、自动合并都不可用"
  assert_contains "$out" "用不了规则集"
  assert_contains "$out" "这些设置没有生效（通常是套餐限制）：allow_auto_merge"
  assert_contains "$out" "合并闸门没有生效"
  assert_contains "$out" "没配置 AUTOTEAM_DEPLOY_ENVIRONMENT"
  assert_no_log "rulesets --input"
  [ ! -f "$STUB_STATE/ruleset.json" ] || tfail "不应写规则集"
}

t_github_trial_mode_drops_approvals() {
  github_ready_repo
  out=$(autoteam_stub github --apply --trial)
  assert_contains "$out" "试用模式"
  assert_eq "$(jq -c '.rules[2].parameters | [.required_approving_review_count, .require_code_owner_review, .require_last_push_approval]' "$STUB_STATE/ruleset.json")" '[0,false,false]'
}

t_github_updates_outdated_ruleset() {
  github_ready_repo has-ruleset
  out=$(STUB_SCENARIO=has-ruleset autoteam_stub github --apply)
  assert_contains "$out" "PUT repos/acme/shop/rulesets/7"
  assert_log "BODY PUT repos/acme/shop/rulesets/7"
}

t_github_checks_apps() {
  setup_ready_repo
  STUB_SCENARIO=org-public out=$(autoteam_stub github --apply --apps impl=111,review=222,planner=333)
  assert_contains "$out" "GitHub App"
  assert_contains "$out" "三个 App 各自的权限"
  # App 不能用 API 创建，autoteam 只核对：不该出现任何写操作
  assert_no_log "BODY PUT repos/acme/shop/collaborators"
}

# 同一个 App 既开 PR 又批准，GitHub 会拒，评审独立性就没了——这是整套方案的核心约束
t_github_rejects_same_app_for_impl_and_review() {
  setup_ready_repo
  out=$(autoteam_stub github --apply --apps impl=111,review=111)
  assert_contains "$out" "同一个 App"
  assert_contains "$out" "评审独立性"
}

t_github_warns_when_no_apps() {
  setup_ready_repo
  out=$(autoteam_stub github)
  assert_contains "$out" "还没有配置 GitHub App"
}
