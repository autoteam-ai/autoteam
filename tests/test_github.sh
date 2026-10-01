# shellcheck shell=bash
# autoteam github：预览不写、三种套餐、试用模式、已有规则集、GitHub App

# 套餐只影响 github 命令本身，init 用同一份仓库模板；只有 free-private 要在 init 时就带上套餐
github_ready_repo() {
  STUB_SCENARIO=${1:-user-public} setup_ready_repo acme/shop
  : > "$STUB_LOG"
}

# 预览不写；同一个仓库上接着 --apply，再跑一次确认幂等
t_github_preview_then_user_public_apply() {
  github_ready_repo
  out=$(autoteam_stub github)
  assert_contains "$out" "[预览] PATCH repos/acme/shop"
  assert_contains "$out" "[预览] POST repos/acme/shop/rulesets"
  assert_contains "$out" "以上是预览"
  assert_contains "$out" "还没有配置 GitHub App"
  assert_no_log "-X PATCH"
  assert_no_log "-X POST"
  assert_no_log "-X PUT"
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
  github_ready_repo
  out=$(STUB_SCENARIO=org-public autoteam_stub github --apply)
  assert_contains "$out" "合并队列都可用"
  assert_eq "$(jq -r '.rules[-1].type' "$STUB_STATE/ruleset.json")" merge_queue
  assert_eq "$(jq -r '.rules[-1].parameters.merge_method' "$STUB_STATE/ruleset.json")" SQUASH
}

t_github_org_retries_without_merge_queue() {
  github_ready_repo
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
  github_ready_repo
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

t_github_all_repos_ack_silences_warning() {
  setup_ready_repo
  printf '{"installations":[{"app_id":111,"app_slug":"impl","repository_selection":"all","permissions":{"workflows":"write"}}]}\n' > "$STUB_STATE/installations.json"
  out=$(STUB_SCENARIO=org-public autoteam_stub github --apps impl=111)
  assert_contains "$out" "私钥泄露会影响整个组织"
  assert_contains "$out" "AUTOTEAM_APP_ALL_REPOS_ACK=on"
  sed -i 's/^AUTOTEAM_APP_ALL_REPOS_ACK=off$/AUTOTEAM_APP_ALL_REPOS_ACK=on/' .autoteam/autoteam.conf
  out=$(STUB_SCENARIO=org-public autoteam_stub github --apps impl=111)
  assert_contains "$out" "已确认多仓库共用"
  assert_not_contains "$out" "私钥泄露会影响整个组织"
}

# 同一个 App 既开 PR 又批准，GitHub 会拒，评审独立性就没了——这是整套方案的核心约束
t_github_rejects_same_app_for_impl_and_review() {
  setup_ready_repo
  out=$(autoteam_stub github --apply --apps impl=111,review=111)
  assert_contains "$out" "同一个 App"
  assert_contains "$out" "评审独立性"
}

# --- github --create-apps（App Manifest 流程）---

# 回调 URL：state 由 AUTOTEAM_APP_STATE_NONCE 固定，形如 <角色>-<nonce>
cb_url() { printf 'http://localhost:3000/autoteam-callback?code=code-%s&state=%s-n0nce\n' "$1" "${2:-$1}"; }
create_apps_run() { AUTOTEAM_APP_STATE_NONCE=n0nce autoteam_stub github --create-apps --apply; }
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

t_create_apps_preview_writes_nothing() {
  setup_ready_repo
  out=$(autoteam_stub github --create-apps)
  assert_contains "$out" "[预览] 创建 App shop-implementer"
  assert_contains "$out" '"workflows":"write"'
  assert_contains "$out" "以上是预览"
  assert_no_log "app-manifests"
  assert_no_file "$WORK/.home/.autoteam"
}

t_create_apps_stores_keys_and_ids() {
  setup_ready_repo
  out=$( { cb_url implementer; cb_url reviewer; cb_url planner; } | create_apps_run)
  for r in implementer reviewer planner; do
    key=$WORK/.home/.autoteam/$r.pem
    assert_file "$key"
    assert_eq "$(file_mode "$key")" 600
    assert_file_contains "$key" "STUB-PEM-$r"
  done
  assert_eq "$(file_mode "$WORK/.home/.autoteam")" 700
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_IMPLEMENTER_APP_ID=111"
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_REVIEWER_APP_ID=222"
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_PLANNER_APP_ID=333"
  assert_contains "$out" "https://github.com/apps/shop-implementer/installations/new"
  # 私钥、client secret、webhook secret（桩里都以 STUB- 开头）一个字都不能出现在输出里
  assert_not_contains "$out" "STUB-"
}

t_create_apps_manifest_form_has_permissions() {
  setup_ready_repo
  ( AUTOTEAM_HOME=$ROOT/skills/autoteam
    # shellcheck source=/dev/null
    . "$AUTOTEAM_HOME/lib/common.sh"
    # shellcheck source=/dev/null
    . "$AUTOTEAM_HOME/lib/conf.sh"
    # shellcheck source=/dev/null
    . "$AUTOTEAM_HOME/lib/create_apps.sh"
    AUTOTEAM_REPO=acme/shop
    m=$(github_app_manifest reviewer shop-reviewer)
    assert_eq "$(jq -c .default_permissions <<<"$m")" '{"contents":"write","pull_requests":"write"}'
    assert_eq "$(jq -c '[.public, .hook_attributes]' <<<"$m")" '[false,null]'
    assert_eq "$(jq -c .default_permissions <<<"$(github_app_manifest planner p)")" '{"actions":"write","contents":"read","pull_requests":"read"}'
    html=$(github_app_form_html "https://github.com/settings/apps/new?state=s" "$m" reviewer)
    assert_contains "$html" 'action="https://github.com/settings/apps/new?state=s"'
    assert_contains "$html" '&quot;pull_requests&quot;:&quot;write&quot;'
    exit "$T_FAILS" ) || T_FAILS=$((T_FAILS + 1))
}

t_create_apps_skips_existing_key() {
  setup_ready_repo
  mkdir -p "$WORK/.home/.autoteam"
  printf 'ORIGINAL' > "$WORK/.home/.autoteam/implementer.pem"
  printf 'ORIGINAL' > "$WORK/.home/.autoteam/shop-reviewer.2026-01-01.private-key.pem"
  out=$(cb_url planner | create_apps_run)
  assert_contains "$out" "implementer：$WORK/.home/.autoteam 里已有私钥，跳过"
  assert_contains "$out" "reviewer：$WORK/.home/.autoteam 里已有私钥，跳过"
  assert_eq "$(cat "$WORK/.home/.autoteam/implementer.pem")" ORIGINAL
  assert_no_log "CONVERT implementer"
  assert_log "CONVERT planner"
}

t_create_apps_configured_id_without_key_is_not_recreated() {
  setup_ready_repo
  sed -i 's/^AUTOTEAM_PLANNER_APP_ID=$/AUTOTEAM_PLANNER_APP_ID=999/' .autoteam/autoteam.conf
  out=$( { cb_url implementer; cb_url reviewer; } | create_apps_run)
  assert_contains "$out" "已有 AUTOTEAM_PLANNER_APP_ID"
  assert_no_log "CONVERT planner"
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_PLANNER_APP_ID=999"
}

# 缺 state、裸 code、别的角色的 state、非回调 URL、空输入、无效 code 都不能兑换或落盘
t_create_apps_rejects_bad_callbacks() {
  setup_ready_repo
  rc=0
  out=$(printf '%s\n' \
    'code-implementer' \
    'http://localhost:3000/autoteam-callback?code=code-reviewer' \
    'http://localhost:3000/autoteam-callback?code=code-planner&state=implementer-n0nce' | create_apps_run) || rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "裸 code 不接受"
  assert_contains "$out" "没有 state 参数"
  assert_contains "$out" "state 与这次创建的不一致"
  assert_no_log "app-manifests"
  assert_no_file "$WORK/.home/.autoteam/implementer.pem"
  out=$(printf '%s\n' 'https://evil.example/autoteam-callback?code=code-implementer&state=implementer-n0nce' | create_apps_run) || true
  assert_contains "$out" "不是完整的回调 URL"
  rc=0
  out=$(printf '%s\n' "$(cb_url implementer)" '' "$(cb_url planner | sed 's/code-planner/bad/')" | create_apps_run) || rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "没有收到 URL"
  assert_contains "$out" "用 code 换取 App 失败"
  assert_file "$WORK/.home/.autoteam/implementer.pem"
}

# 转换之后任何一步落盘失败都要明确报错、给恢复办法，并且整条命令退出非 0
t_create_apps_reports_store_failures() {
  setup_ready_repo
  ( AUTOTEAM_HOME=$ROOT/skills/autoteam
    # shellcheck source=/dev/null
    . "$AUTOTEAM_HOME/lib/common.sh"
    # shellcheck source=/dev/null
    . "$AUTOTEAM_HOME/lib/conf.sh"
    # shellcheck source=/dev/null
    . "$AUTOTEAM_HOME/lib/create_apps.sh"
    AUTOTEAM_REPO=acme/shop AUTOTEAM_CONF_REL=.autoteam/autoteam.conf
    # shellcheck disable=SC2034  # GH_OUT 由 gh_call 桩写、被 github_convert_and_store 读
    GH_OUT='{"id":111,"slug":"shop-implementer","pem":"STUB-PEM"}'
    # shellcheck disable=SC2329  # 覆盖 lib 里的同名函数，由 github_convert_and_store 调用
    gh_call() { return 0; }
    keys=$WORK/keys
    # 1) 写 App ID 失败：私钥已在，消息要说清楚并给出手工写入的那一行
    # shellcheck disable=SC2329  # 覆盖 lib 里的同名函数，由 github_convert_and_store 调用
    github_write_app_id() { return 1; }
    out=$(github_convert_and_store implementer code1 "$keys" "$WORK/.autoteam/autoteam.conf" acme User) && tfail "写 conf 失败时应返回非 0"
    assert_contains "$out" "App ID 没能写进"
    assert_contains "$out" "AUTOTEAM_IMPLEMENTER_APP_ID=111"
    assert_not_contains "$out" "已建好：私钥"
    rm -f "$keys/implementer.pem"
    # 2) 私钥文件已存在（竞态）：不覆盖，给出恢复办法
    # shellcheck disable=SC2329  # 覆盖 lib 里的同名函数，由 github_convert_and_store 调用
    github_write_app_id() { return 0; }
    printf 'ORIGINAL' > "$keys/implementer.pem"
    out=$(github_convert_and_store implementer code1 "$keys" "$WORK/.autoteam/autoteam.conf" acme User) && tfail "私钥已存在时应返回非 0"
    assert_eq "$(cat "$keys/implementer.pem")" ORIGINAL
    assert_contains "$out" "没有覆盖任何文件"
    assert_contains "$out" "Generate a private key"
    exit "$T_FAILS" ) || T_FAILS=$((T_FAILS + 1))
}
