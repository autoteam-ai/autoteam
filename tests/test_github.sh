# shellcheck shell=bash
# aiwf github：预览不写、三种套餐、试用模式、已有规则集、机器账号

github_ready_repo() {
  new_repo acme/shop
  STUB_SCENARIO=${1:-user-public} aiwf_stub init --owner alice >/dev/null
  : > "$STUB_LOG"
}

t_github_preview_makes_no_writes() {
  github_ready_repo
  out=$(aiwf_stub github)
  assert_contains "$out" "[预览] PATCH repos/acme/shop"
  assert_contains "$out" "[预览] POST repos/acme/shop/rulesets"
  assert_contains "$out" "以上是预览"
  assert_no_log "-X PATCH"
  assert_no_log "-X POST"
  assert_no_log "-X PUT"
}

t_github_user_public_apply() {
  github_ready_repo
  out=$(aiwf_stub github --apply)
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
  out=$(aiwf_stub github --apply)
  assert_contains "$out" "规则集已符合"
  assert_contains "$out" "已符合：允许自动合并"
  assert_no_log "-X PUT repos/acme/shop/rulesets"
}

t_github_org_public_adds_merge_queue() {
  github_ready_repo org-public
  out=$(STUB_SCENARIO=org-public aiwf_stub github --apply)
  assert_contains "$out" "合并队列都可用"
  assert_eq "$(jq -r '.rules[-1].type' "$STUB_STATE/ruleset.json")" merge_queue
  assert_eq "$(jq -r '.rules[-1].parameters.merge_method' "$STUB_STATE/ruleset.json")" SQUASH
}

t_github_org_retries_without_merge_queue() {
  github_ready_repo org-no-mq
  out=$(STUB_SCENARIO=org-no-mq aiwf_stub github --apply)
  assert_contains "$out" "不支持合并队列，去掉后重试"
  assert_contains "$out" "规则集已写入（无合并队列"
  assert_eq "$(jq '[.rules[] | select(.type == "merge_queue")] | length' "$STUB_STATE/ruleset.json")" 0
}

t_github_free_private_degrades() {
  github_ready_repo free-private
  out=$(STUB_SCENARIO=free-private aiwf_stub github --apply)
  assert_contains "$out" "规则集、分支保护、自动合并都不可用"
  assert_contains "$out" "用不了规则集"
  assert_contains "$out" "这些设置没有生效（通常是套餐限制）：allow_auto_merge"
  assert_contains "$out" "合并闸门没有生效"
  assert_contains "$out" "没配置 AIWF_DEPLOY_ENVIRONMENT"
  assert_no_log "rulesets --input"
  [ ! -f "$STUB_STATE/ruleset.json" ] || tfail "不应写规则集"
}

t_github_trial_mode_drops_approvals() {
  github_ready_repo
  out=$(aiwf_stub github --apply --trial)
  assert_contains "$out" "试用模式"
  assert_eq "$(jq -c '.rules[2].parameters | [.required_approving_review_count, .require_code_owner_review, .require_last_push_approval]' "$STUB_STATE/ruleset.json")" '[0,false,false]'
}

t_github_updates_outdated_ruleset() {
  github_ready_repo has-ruleset
  out=$(STUB_SCENARIO=has-ruleset aiwf_stub github --apply)
  assert_contains "$out" "PUT repos/acme/shop/rulesets/7"
  assert_log "BODY PUT repos/acme/shop/rulesets/7"
}

t_github_invites_bots() {
  github_ready_repo
  out=$(aiwf_stub github --apply --bots impl=acme-impl-bot,review=acme-review-bot)
  assert_contains "$out" "已邀请 acme-impl-bot"
  assert_contains "$out" "已邀请 acme-review-bot"
  assert_contains "$out" "只能用 classic token"
  assert_log "BODY PUT repos/acme/shop/collaborators/acme-impl-bot"
}
