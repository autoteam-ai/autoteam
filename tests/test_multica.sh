# shellcheck shell=bash
# autoteam multica / runtimes：预览、新建、再跑变成无改动、runtime 找不到、webhook 写 secret

t_multica_preview_makes_no_writes() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub multica)
  assert_contains "$out" "profile：test"
  assert_contains "$out" "旧状态 shipping 不存在或已归档"
  assert_contains "$out" "[预览] 新建 agent planner（planner，runtime rt-c-cla，模型 default，并发 1）"
  assert_contains "$out" "[预览] 新建 agent rev-codex（reviewer，runtime rt-b-cod，模型 gpt-5.5，并发 2）"
  assert_contains "$out" "runtime codex@machine-b 现在不在线"
  assert_contains "$out" "[预览] 新建项目 shop"
  assert_contains "$out" "[预览] 新建运营笔记"
  assert_no_log "issue create"
  assert_contains "$out" "[预览] 新建 autopilot「推进巡检」（planner，run_only，0 */2 * * *）"
  assert_no_log "agent create"
  assert_no_log "curl POST"
}

# shellcheck disable=SC2153  # ROOT 来自 tests/lib.sh
t_multica_apply_creates_everything() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply)
  assert_contains "$out" "旧状态 shipping 不存在或已归档"
  assert_no_log "curl POST https://api.multica.test/api/issue-statuses"
  assert_eq "$(jq length "$STUB_STATE/mc-agents.json")" 4
  assert_eq "$(jq length "$STUB_STATE/mc-issues-project.json")" 1
  assert_eq "$(jq -r '.[0] | [.title,.project_id,.assignee_id,.status] | join("|")' "$STUB_STATE/mc-issues-project.json")" '运营笔记|proj-1|agent-planner|in_progress'
  assert_log 'issue create --title 运营笔记 --project proj-1 --status backlog'
  assert_log 'issue assign note-1 --to-id agent-planner --no-start'
  assert_log 'issue status note-1 in_progress --no-start'
  assert_eq "$(jq -r '.[] | select(.name == "impl-claude") | .runtime_id' "$STUB_STATE/mc-agents.json")" rt-a-claude-0000
  assert_eq "$(jq -r '.[] | select(.name == "auditor") | .runtime_id' "$STUB_STATE/mc-agents.json")" rt-c-claude-0000
  assert_eq "$(jq -r '.[] | select(.name == "rev-codex") | .instructions' "$STUB_STATE/mc-agents.json" | sed -n 3p)" "$(head -n 1 "$ROOT/skills/autoteam/instructions/roles/reviewer.md")" "没 eject 时取包内指令（前言之后）"
  assert_log "agent create --name rev-codex --runtime-id rt-b-codex-00000"
  assert_log "--model gpt-5.5"
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 5
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "每日摘要") | .triggers[0].cron_expression' "$STUB_STATE/mc-autopilots.json")" "0 9 * * *"
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "每日摘要") | .triggers[0].timezone' "$STUB_STATE/mc-autopilots.json")" "Asia/Shanghai"
  assert_log "autopilot create --title 每日摘要 --agent agent-planner --mode create_issue"
  assert_log "--issue-title-template 每日摘要 {{date}}"
  assert_log "--subscriber Alice"
  assert_log "autopilot create --title 周度健康报告 --agent agent-auditor"
  assert_eq "$(cat "$STUB_STATE/secret-MULTICA_DEPLOY_HOOK")" "https://api.multica.test/api/webhooks/SECRET-TOKEN-123"
  assert_not_contains "$out" "SECRET-TOKEN-123" "webhook 地址含凭据，不应打印"
  assert_not_contains "$out" "mul_test_token" "token 不应打印"
  assert_no_log "mul_test_token"
}

t_multica_second_apply_is_noop() {
  setup_applied_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply)
  assert_contains "$out" "旧状态 shipping 不存在或已归档"
  assert_contains "$out" "agent planner 已是最新"
  assert_contains "$out" "运营笔记已存在（1 条）"
  assert_eq "$(jq length "$STUB_STATE/mc-issues-project.json")" 1
  assert_no_log 'issue create'
  assert_contains "$out" "autopilot「推进巡检」已是最新"
  assert_contains "$out" "定时触发已是 0 */2 * * *（Asia/Shanghai）"
  assert_contains "$out" "部署 webhook 已存在，GitHub secret MULTICA_DEPLOY_HOOK 已设置"
  assert_no_log "agent create"
  assert_no_log "autopilot create"
  assert_no_log "trigger-add"
  assert_no_log "curl POST"
}

t_multica_note_lookup_pages_and_keeps_existing_note() {
  setup_ready_repo
  autoteam_stub multica --apply --only agents >/dev/null
  autoteam_stub multica --apply --only project >/dev/null
  jq -n '[range(0; 100) | {id:("other-" + tostring),title:"other",project_id:"proj-1"}] + [{id:"existing-note",title:"运营笔记",project_id:"proj-1",status:"in_progress",metadata:{"autoteam.paused":"keep"}}]' > "$STUB_STATE/mc-issues-project.json"
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply --only project)
  assert_contains "$out" '运营笔记已存在（1 条）'
  assert_log 'issue list --project proj-1 --fields id,title --limit 100 --offset 100'
  assert_no_log 'issue create'
  assert_eq "$(jq -r '.[-1].metadata["autoteam.paused"]' "$STUB_STATE/mc-issues-project.json")" keep
}

t_multica_issue_pages_reads_all_pages_and_fails_on_empty_page() {
  setup_ready_repo
  source "$ROOT/skills/autoteam/lib/multica.sh"
  MC_BIN="$TESTS_DIR/stubs/multica"
  export STUB_LOG STUB_STATE
  jq -n '[range(0; 205) | {id:("i-" + tostring),title:"t"}]' > "$STUB_STATE/mc-issues-project.json"
  : > "$STUB_LOG"
  out=$(mc_issue_pages '.issues[].id' --project proj-1)
  assert_eq "$(grep -c . <<<"$out")" 205
  assert_log 'issue list --project proj-1 --limit 100 --offset 200'
  # has_more 为真却是空页：必须报错，不能死循环
  STUB_ISSUES_EMPTY_MORE=1 mc_issue_pages '.issues[].id' --project proj-1 >/dev/null && tfail '空页应返回非零'
  return 0
}

t_multica_rewrites_env_file_every_apply() {
  setup_ready_repo
  mkdir -p .autoteam/local
  echo '{"GITHUB_TOKEN":"bot-token"}' > .autoteam/local/reviewer-env.json
  # 给一个 reviewer 配上 env_file（机器账号的 token 就是这么给的）
  python3 - <<'PY'
import pathlib
p = pathlib.Path('.autoteam/registry.yaml')
lines = p.read_text().split('\n')
for i, l in enumerate(lines):
    if l.strip().startswith('rev-codex:'):
        lines[i] = l.replace(' }', ', env_file: .autoteam/local/reviewer-env.json }')
p.write_text('\n'.join(lines))
PY
  grep -q 'env_file' .autoteam/registry.yaml || tfail "registry 没改成功"

  # 首次是 create，env 跟着 agent create 一起传
  autoteam_stub multica --apply --only agents >/dev/null
  assert_log "--custom-env-file"

  # 第二次：agent 其他字段都没变，但 env 读不回来没法比对，必须照样重写一遍，
  # 否则换了 token 之后 apply 会报"已是最新"，token 永远同步不过去
  : > "$STUB_STATE/mc-agent-env.log"
  out=$(autoteam_stub multica --apply --only agents)
  assert_contains "$out" "agent rev-codex 已是最新（环境变量会重新写入）"
  assert_contains "$(cat "$STUB_STATE/mc-agent-env.log" 2>/dev/null)" "agent-rev-codex" "第二次 apply 也要重写环境变量"
  assert_contains "$out" "agent planner 已是最新"
  assert_not_contains "$(cat "$STUB_STATE/mc-agent-env.log" 2>/dev/null)" "agent-planner" "没配 env_file 的 agent 不该被写"
}

t_multica_updates_changed_instructions() {
  setup_ready_repo
  autoteam_stub multica --apply --only agents >/dev/null
  autoteam_stub eject planner >/dev/null
  echo "新增一条规则" >> .autoteam/instructions/roles/planner.md
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply --only agents)
  assert_contains "$out" "更新 agent planner： 指令"
  assert_log "agent update agent-planner"
  assert_contains "$out" "agent impl-claude 已是最新"
  assert_contains "$(jq -r '.[] | select(.name == "planner") | .instructions' "$STUB_STATE/mc-agents.json")" "新增一条规则"

  # 删掉 eject 的文件，指令回到包内版本
  rm .autoteam/instructions/roles/planner.md
  out=$(autoteam_stub multica --apply --only agents)
  assert_contains "$out" "更新 agent planner： 指令"
  assert_not_contains "$(jq -r '.[] | select(.name == "planner") | .instructions' "$STUB_STATE/mc-agents.json")" "新增一条规则"
}

# 暂停检查前言只在包内 _preamble.md 维护一份，同步时加到每份角色指令和 autopilot 正文最前面
t_multica_prepends_preamble() {
  local pre name
  pre=$(sed 's/{{AUTOTEAM_LANGUAGE}}/zh-CN/' "$ROOT/skills/autoteam/instructions/_preamble.md")
  assert_contains "$pre" "开工先检查暂停"
  assert_contains "$pre" '使用 `zh-CN` 对应的语言'
  assert_eq "$(grep -rl "开工先检查暂停" "$ROOT/skills/autoteam/instructions")" "$ROOT/skills/autoteam/instructions/_preamble.md" "前言只能有一份来源"
  setup_applied_repo
  for name in planner impl-claude rev-codex auditor; do
    assert_eq "$(jq -r --arg n "$name" '.[] | select(.name == $n) | .instructions' "$STUB_STATE/mc-agents.json" | head -n 1)" "$pre" "agent $name 的指令开头是前言"
  done
  assert_eq "$(jq -r '.[] | select(.name == "planner") | .instructions' "$STUB_STATE/mc-agents.json")" \
    "$(printf '%s\n\n' "$pre"; cat "$ROOT/skills/autoteam/instructions/roles/planner.md")" "前言、空行、角色文件原文"
  assert_eq "$(jq '[.[] | select((.autopilot.description | split("\n")[0]) != $p)] | length' --arg p "$pre" "$STUB_STATE/mc-autopilots.json")" 0 "每个 autopilot 正文开头是前言"
  assert_contains "$(jq -r '.[] | select(.autopilot.title == "推进巡检") | .autopilot.description' "$STUB_STATE/mc-autopilots.json")" "$pre

按 \`bash ./autoteam runbook progress\` 处理，事件=\`patrol\`"

  # eject 出的文件不含前言，同步时仍自动加上，不会重复
  autoteam_stub eject reviewer >/dev/null
  assert_not_contains "$(cat .autoteam/instructions/roles/reviewer.md)" "开工先检查暂停"
  echo "新增一条规则" >> .autoteam/instructions/roles/reviewer.md
  autoteam_stub multica --apply --only agents >/dev/null
  out=$(jq -r '.[] | select(.name == "rev-codex") | .instructions' "$STUB_STATE/mc-agents.json")
  assert_eq "$(printf '%s' "$out" | head -n 1)" "$pre" "eject 后同步仍以前言开头"
  assert_eq "$(printf '%s' "$out" | grep -c "开工先检查暂停")" 1 "前言不重复"
  assert_contains "$out" "新增一条规则"
}

t_multica_reports_missing_runtime() {
  setup_ready_repo
  sed -i.bak 's/claude@machine-a/claude@nowhere/' .autoteam/registry.yaml && rm -f .autoteam/registry.yaml.bak
  out=$(autoteam_stub multica --only agents) && tfail "缺失 runtime 应返回非零"
  assert_contains "$out" "agent impl-claude：找不到 runtime claude@nowhere"
  assert_contains "$out" "claude@machine-a（online）"
}

t_multica_paused_flag() {
  setup_ready_repo
  autoteam_stub multica --apply --paused >/dev/null
  assert_eq "$(jq '[.[] | select(.autopilot.status == "paused")] | length' "$STUB_STATE/mc-autopilots.json")" 5
}

t_runtimes_lists_selectors() {
  setup_ready_repo
  out=$(autoteam_stub runtimes)
  assert_contains "$out" "claude@machine-a"
  assert_contains "$out" "codex@machine-b"
  assert_contains "$out" "offline"
}


t_multica_partial_failure_summary() {
  setup_ready_repo
  echo 'project list' > "$STUB_STATE/mc-fail-command"
  echo -1 > "$STUB_STATE/mc-fail-count"
  out=$(autoteam_stub multica --apply 2>&1) && tfail "读取失败应返回非零"
  assert_contains "$out" "同步不完整"
  assert_contains "$out" "已完成： statuses agents"
  assert_contains "$out" "失败或部分完成： project"
  assert_contains "$out" "未执行： autopilots"
  assert_eq "$(grep -c 'project list' "$STUB_LOG")" 3
  assert_no_log "autopilot create"
}

t_multica_transient_read_recovers() {
  setup_ready_repo
  echo 'project list' > "$STUB_STATE/mc-fail-command"
  echo 1 > "$STUB_STATE/mc-fail-count"
  out=$(autoteam_stub multica --apply 2>&1)
  assert_eq "$?" 0
  assert_not_contains "$out" "同步不完整"
  assert_eq "$(grep -c 'project list' "$STUB_LOG")" 2
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 5
}

t_multica_resource_read_failure_does_not_attach() {
  setup_ready_repo
  autoteam_stub multica --apply --only project >/dev/null
  : > "$STUB_LOG"
  echo 'project resource list proj-1' > "$STUB_STATE/mc-fail-command"
  echo -1 > "$STUB_STATE/mc-fail-count"
  out=$(autoteam_stub multica --apply --only project 2>&1) && tfail "资源读取失败应返回非零"
  assert_contains "$out" "同步不完整"
  assert_no_log 'resource add'
}

t_multica_resource_conflict_is_current() {
  setup_ready_repo
  autoteam_stub multica --apply --only agents >/dev/null
  autoteam_stub multica --apply --only project >/dev/null
  touch "$STUB_STATE/mc-resource-empty" "$STUB_STATE/mc-resource-conflict"
  out=$(autoteam_stub multica --apply --only project)
  assert_eq "$?" 0
  assert_contains "$out" "仓库已是最新"
  assert_not_contains "$out" "同步不完整"
}

t_multica_write_failure_is_not_retried() {
  setup_ready_repo
  autoteam_stub multica --apply --only project >/dev/null
  touch "$STUB_STATE/mc-resource-empty"
  : > "$STUB_LOG"
  echo 'project resource add proj-1 --type github_repo --url https://github.com/acme/shop' > "$STUB_STATE/mc-fail-command"
  echo -1 > "$STUB_STATE/mc-fail-count"
  out=$(autoteam_stub multica --apply --only project 2>&1) && tfail "写入失败应返回非零"
  assert_contains "$out" "同步不完整"
  assert_eq "$(grep -c 'resource add' "$STUB_LOG")" 1
}

t_multica_api_timeout_and_only_statuses() {
  setup_ready_repo
  touch "$STUB_STATE/curl-timeout"
  : > "$STUB_LOG"
  out=$(MULTICA_HTTP_TIMEOUT=1m30s autoteam_stub multica --apply --only statuses 2>&1) && tfail "API 超时应返回非零"
  assert_contains "$out" "同步不完整"
  assert_contains "$out" "Operation timed out"
  assert_log 'curl max-time=90.000000000'
  assert_log 'http-timeout=1m30s'
  assert_eq "$(grep -c 'curl GET' "$STUB_LOG")" 3
  assert_no_log 'runtime list'
}

t_multica_timeout_formats() {
  setup_ready_repo
  local value expected
  for value in 45 45s 2m 500ms 1.5h .5s; do
    case $value in
      45|45s) expected=45.000000000 ;;
      2m) expected=120.000000000 ;;
      500ms|.5s) expected=0.500000000 ;;
      1.5h) expected=5400.000000000 ;;
    esac
    : > "$STUB_LOG"
    MULTICA_HTTP_TIMEOUT=$value autoteam_stub multica --only statuses >/dev/null
    assert_log "curl max-time=$expected"
  done
  for value in 0 -1 bad; do
    out=$(MULTICA_HTTP_TIMEOUT=$value autoteam_stub multica --apply 2>&1) && tfail "无效超时应失败"
    assert_contains "$out" "同步不完整"
    assert_contains "$out" "MULTICA_HTTP_TIMEOUT 必须"
  done
}

t_multica_fatal_local_error_summary() {
  setup_ready_repo
  sed -i.bak 's/model: default, max_tasks: 1 }$/model: default, max_tasks: 1, mcp: nofile.json }/' .autoteam/registry.yaml && rm -f .autoteam/registry.yaml.bak
  out=$(autoteam_stub multica --apply 2>&1) && tfail "缺失 MCP 配置应失败"
  assert_contains "$out" "已完成： statuses"
  assert_contains "$out" "失败或部分完成： agents"
  assert_contains "$out" "未执行： project autopilots"
}


t_multica_autopilot_read_failure_does_not_update() {
  setup_applied_repo
  : > "$STUB_LOG"
  echo 'autopilot get ap-1' > "$STUB_STATE/mc-fail-command"
  echo -1 > "$STUB_STATE/mc-fail-count"
  out=$(autoteam_stub multica --apply --only autopilots 2>&1) && tfail "autopilot 读取失败应返回非零"
  assert_contains "$out" "同步不完整"
  assert_contains "$out" "未执行更新"
  assert_no_log 'autopilot update ap-1 '
  assert_no_log 'autopilot trigger-add ap-1 '
  assert_no_log 'autopilot trigger-update ap-1 '
  assert_eq "$(grep -c 'autopilot get ap-1 ' "$STUB_LOG")" 3
}

# 同一工作区接第二个项目：别的项目的同名 autopilot 预览和 --apply 都不动，本项目另建一套
t_multica_leaves_other_project_autopilots() {
  setup_applied_repo
  jq 'map(.autopilot.project_id = "proj-other" | .autopilot.description = "别的项目的 runbook")' \
    "$STUB_STATE/mc-autopilots.json" > "$STUB_STATE/mc-autopilots.tmp"
  mv "$STUB_STATE/mc-autopilots.tmp" "$STUB_STATE/mc-autopilots.json"
  cp "$STUB_STATE/mc-autopilots.json" "$WORK/other.json"
  : > "$STUB_LOG"

  out=$(autoteam_stub multica --only autopilots)
  assert_contains "$out" "工作区里另有同名 autopilot「推进巡检」不属于本项目，不改动它"
  assert_contains "$out" "[预览] 新建 autopilot「推进巡检」"
  assert_not_contains "$out" "更新 autopilot"
  assert_no_log "autopilot update"

  out=$(autoteam_stub multica --apply --only autopilots)
  assert_not_contains "$out" "更新 autopilot"
  assert_no_log "autopilot update"
  assert_no_log "trigger-update"
  assert_eq "$(jq -c '[.[] | select(.autopilot.project_id == "proj-other")]' "$STUB_STATE/mc-autopilots.json")" \
    "$(jq -c . "$WORK/other.json")" "别的项目的 autopilot 和触发器原样保留"
  assert_eq "$(jq '[.[] | select(.autopilot.project_id == "proj-1")] | length' "$STUB_STATE/mc-autopilots.json")" 5

  out=$(autoteam_stub multica --apply --only autopilots)
  assert_contains "$out" "autopilot「推进巡检」已是最新"
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 10 "再跑不重复建"
}

# 列表里还是本项目的，读详情时已被改绑到别的项目：不更新、不同步触发器、不暂停
t_multica_skips_autopilot_rebound_after_list() {
  setup_applied_repo
  echo proj-other > "$STUB_STATE/mc-autopilot-get-project"
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply --paused --only autopilots 2>&1) && tfail "改绑的 autopilot 应算失败"
  assert_contains "$out" "autopilot「推进巡检」（ap-4）已不属于本项目，未执行该项"
  assert_no_log "autopilot update"
  assert_no_log "autopilot create"
  assert_no_log "trigger-add"
  assert_no_log "trigger-update"
  assert_no_log "trigger-rotate-url"
}

t_multica_api_failure_keeps_independent_steps() {
  setup_ready_repo
  touch "$STUB_STATE/curl-timeout"
  out=$(autoteam_stub multica --apply 2>&1) && tfail "状态读取失败应返回非零"
  assert_contains "$out" "已完成： agents project autopilots"
  assert_contains "$out" "失败或部分完成： statuses"
  assert_contains "$out" "未执行：无"
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 5
}

# 无 profile 目录、多个 profile、仅环境变量：agent runtime 只有环境变量
t_multica_profile_missing_dir_dies() {
  setup_ready_repo
  rm -rf "$WORK/.home/.multica"
  out=$(autoteam_stub multica 2>&1) && tfail "没有 profile 也没有环境变量应报错"
  assert_contains "$out" "multica 还没登录：先运行 multica login"
}

t_multica_profile_multiple_dies() {
  setup_ready_repo
  mkdir -p "$WORK/.home/.multica/profiles/other"
  out=$(autoteam_stub multica 2>&1) && tfail "多个 profile 应报错"
  assert_contains "$out" "multica 默认 profile 没有配置服务器"
  assert_contains "$out" "other"
}

t_multica_profile_server_missing_differs_from_login() {
  setup_ready_repo
  rm -rf "$WORK/.home/.multica/profiles"
  printf '{"token":"mul_test_token"}\n' > "$WORK/.home/.multica/config.json"
  out=$(autoteam_stub multica 2>&1) && tfail "默认 profile 无服务器应失败"
  assert_contains "$out" "默认 profile 没有配置服务器"
  assert_contains "$out" "multica setup"
  assert_not_contains "$out" "还没登录"

  rm "$WORK/.home/.multica/config.json"
  out=$(autoteam_stub multica 2>&1) && tfail "未登录应失败"
  assert_contains "$out" "multica 还没登录：先运行 multica login"
  assert_not_contains "$out" "默认 profile 没有配置服务器"
}

t_multica_env_only_needs_no_profile() {
  setup_ready_repo
  rm -rf "$WORK/.home/.multica"
  echo '[{"id":"status-shipping","key":"shipping","name":"待上线","category":"in_progress","archived_at":null}]' > "$STUB_STATE/mc-statuses.json"
  : > "$STUB_LOG"
  out=$(TEST_MULTICA_SERVER_URL=https://api.multica.test TEST_MULTICA_TOKEN=mul_test_token autoteam_stub multica --apply --only statuses)
  assert_contains "$out" "已归档旧状态 shipping"
  assert_no_log "--profile"
  assert_log "curl DELETE https://api.multica.test/api/issue-statuses/status-shipping auth=ok"
}

t_multica_shipping_preview_pages_then_migrates_and_archives() {
  setup_ready_repo
  echo '[{"id":"status-shipping","key":"shipping","name":"待上线","category":"in_progress","archived_at":null}]' > "$STUB_STATE/mc-statuses.json"
  jq -n '[range(0; 101) | {id:("issue-" + tostring),identifier:("TST-" + tostring),title:"旧任务",status:"shipping"}]' > "$STUB_STATE/mc-issues-shipping.json"
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --only statuses)
  assert_contains "$out" '[预览] 迁移 TST-100 旧任务：shipping → in_review'
  assert_contains "$out" '[预览] 归档旧状态 shipping'
  assert_log 'issue list --status shipping --fields id,identifier,title --limit 100 --offset 100'
  assert_no_log 'issue status'
  assert_no_log 'curl DELETE'
  out=$(autoteam_stub multica --apply --only statuses)
  assert_contains "$out" '已归档旧状态 shipping'
  assert_eq "$(jq length "$STUB_STATE/mc-issues-shipping.json")" 0
  assert_log 'issue status issue-100 in_review --no-start'
  assert_eq "$(jq -r '.[0].archived_at' "$STUB_STATE/mc-statuses.json")" '2026-09-30T00:00:00Z'
  out=$(autoteam_stub multica --apply --only statuses)
  assert_contains "$out" '旧状态 shipping 不存在或已归档'
}

t_multica_shipping_failure_keeps_status() {
  setup_ready_repo
  echo '[{"id":"status-shipping","key":"shipping","name":"待上线","category":"in_progress","archived_at":null}]' > "$STUB_STATE/mc-statuses.json"
  echo '[{"id":"issue-1","identifier":"TST-1","title":"旧任务","status":"shipping"}]' > "$STUB_STATE/mc-issues-shipping.json"
  echo issue-1 > "$STUB_STATE/mc-status-fail"
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply --only statuses 2>&1) && tfail '迁移失败应返回非零'
  assert_contains "$out" '迁移 TST-1 旧任务 失败；未归档 shipping'
  assert_no_log 'curl DELETE'
  assert_eq "$(jq -r '.[0].archived_at' "$STUB_STATE/mc-statuses.json")" null
}

t_multica_env_needs_both_vars() {
  setup_ready_repo
  rm -rf "$WORK/.home/.multica"
  out=$(TEST_MULTICA_TOKEN=mul_test_token autoteam_stub multica 2>&1) && tfail "只有 token 没有 server 应报错"
  assert_contains "$out" "multica 默认 profile 没有配置服务器"
}

# 指令解析：eject 的覆盖包内的，同名以 eject 的为准
t_instructions_path_prefers_ejected() {
  new_repo
  out=$(
    AUTOTEAM_HOME=$ROOT/skills/autoteam AUTOTEAM_DIR=.autoteam
    . "$ROOT/skills/autoteam/lib/instructions.sh"
    instructions_path roles reviewer.md
    instructions_path "" planner-mcp.json
    mkdir -p .autoteam/instructions/roles
    echo x > .autoteam/instructions/roles/reviewer.md
    instructions_path roles reviewer.md
    instructions_path roles nope.md || echo missing
  )
  assert_eq "$out" "$ROOT/skills/autoteam/instructions/roles/reviewer.md
$ROOT/skills/autoteam/instructions/planner-mcp.json
.autoteam/instructions/roles/reviewer.md
missing"
}

t_instructions_list_merges_and_dedupes() {
  new_repo
  out=$(
    AUTOTEAM_HOME=$ROOT/skills/autoteam AUTOTEAM_DIR=.autoteam
    . "$ROOT/skills/autoteam/lib/instructions.sh"
    mkdir -p .autoteam/instructions/autopilots
    echo x > .autoteam/instructions/autopilots/patrol.md
    echo x > .autoteam/instructions/autopilots/extra.md
    instructions_list autopilots
  )
  assert_eq "$(grep -c . <<<"$out")" 7 "6 个包内的 + 1 个新增的，同名不重复"
  assert_contains "$out" ".autoteam/instructions/autopilots/patrol.md"
  assert_not_contains "$out" "$ROOT/skills/autoteam/instructions/autopilots/patrol.md" "同名以 eject 的为准"
  assert_contains "$out" ".autoteam/instructions/autopilots/extra.md"
  assert_contains "$out" "$ROOT/skills/autoteam/instructions/autopilots/health.md"
}

t_instructions_have_no_placeholders() {
  # 只有 _preamble.md 的 {{AUTOTEAM_LANGUAGE}} 会在同步时渲染，其余文件不渲染
  local found
  found=$(grep -rl '{{AUTOTEAM_' "$ROOT/skills/autoteam/instructions" | grep -v '/_preamble\.md$' || true)
  [ -z "$found" ] || tfail "instructions/ 里不该再有占位符：$found"
  assert_eq "$(grep -o '{{AUTOTEAM_[A-Z_]*}}' "$ROOT/skills/autoteam/instructions/_preamble.md")" '{{AUTOTEAM_LANGUAGE}}' "前言只有语言一个占位符"
}

t_multica_autopilot_cron_comes_from_conf() {
  setup_ready_repo
  sed -i.bak 's|^AUTOTEAM_CRON_PATROL=.*|AUTOTEAM_CRON_PATROL=15 */3 * * *|' .autoteam/autoteam.conf && rm -f .autoteam/autoteam.conf.bak
  autoteam_stub multica --apply >/dev/null
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "推进巡检") | .triggers[0].cron_expression' "$STUB_STATE/mc-autopilots.json")" "15 */3 * * *"
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "每日摘要") | .triggers[0].cron_expression' "$STUB_STATE/mc-autopilots.json")" "0 9 * * *"
}

t_multica_uses_ejected_autopilot() {
  setup_ready_repo
  autoteam_stub eject patrol >/dev/null
  sed -i.bak 's|^按 `bash ./autoteam runbook progress`|自定义巡检 runbook|' .autoteam/instructions/autopilots/patrol.md && rm -f .autoteam/instructions/autopilots/patrol.md.bak
  : > "$STUB_LOG"
  autoteam_stub multica --apply >/dev/null
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 5 "同名以 eject 的为准，不重复建"
  assert_contains "$(jq -r '.[] | select(.autopilot.title == "推进巡检") | .autopilot.description' "$STUB_STATE/mc-autopilots.json")" "自定义巡检 runbook"
}

# 前言里的输出语言取自 AUTOTEAM_LANGUAGE：缺省 zh-CN，配置后同步到 agent 和 autopilot
t_multica_preamble_renders_language() {
  setup_ready_repo
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_LANGUAGE=zh-CN"
  sed -i '/^AUTOTEAM_LANGUAGE=/d' .autoteam/autoteam.conf
  autoteam_stub multica --apply >/dev/null
  assert_contains "$(jq -r '.[] | select(.name == "planner") | .instructions' "$STUB_STATE/mc-agents.json" | head -n 1)" '使用 `zh-CN` 对应的语言'
  echo "AUTOTEAM_LANGUAGE=en" >> .autoteam/autoteam.conf
  autoteam_stub multica --apply --only agents,autopilots >/dev/null
  out=$(jq -r '.[] | select(.name == "impl-claude") | .instructions' "$STUB_STATE/mc-agents.json" | head -n 1)
  assert_contains "$out" '使用 `en` 对应的语言'
  assert_not_contains "$out" "{{AUTOTEAM_LANGUAGE}}"
  assert_contains "$(jq -r '.[0].autopilot.description' "$STUB_STATE/mc-autopilots.json" | head -n 1)" '使用 `en` 对应的语言'
  out=$(autoteam_stub doctor --skip-github)
  assert_not_contains "$out" "指令漂移" "渲染后的前言和同步文本一致"
}

t_multica_preview_lists_merged_report_autopilots() {
  setup_ready_repo
  out=$(autoteam_stub multica --only autopilots)
  assert_contains "$out" "新建 autopilot「周度健康报告」（auditor，create_issue，0 9 * * 1）"
  assert_not_contains "$out" "新建 autopilot「月度方向报告」"
  assert_contains "$out" "新建 autopilot「规则复盘」"
  for old in 整合审计 agent\ 成绩单 老代码巡检 规格对账 前沿扫描 路线图对账; do
    assert_not_contains "$out" "$old" "旧的 $old 已并入两份新报告"
  done
}

t_multica_autopilot_selection_keeps_existing() {
  setup_ready_repo
  out=$(autoteam_stub multica --only autopilots)
  assert_eq "$(grep -c '新建 autopilot' <<<"$out")" 5
  assert_no_log 'autopilot create'
  autoteam_stub multica --apply --only agents,project >/dev/null
  sed -i 's/^AUTOTEAM_AUTOPILOTS=.*/AUTOTEAM_AUTOPILOTS=deploy-result,patrol,daily-digest,rule-review,health,direction/' .autoteam/autoteam.conf
  autoteam_stub multica --apply --only autopilots >/dev/null
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 6
  # 收窄清单后，旧实例继续更新，不删除、不暂停。
  sed -i '/^AUTOTEAM_AUTOPILOTS=/d' .autoteam/autoteam.conf
  echo 'AUTOTEAM_AUTOPILOTS=deploy-result,patrol,daily-digest,rule-review,health' >> .autoteam/autoteam.conf
  out=$(autoteam_stub multica --apply --only autopilots)
  assert_contains "$out" '月度方向报告」未在 AUTOTEAM_AUTOPILOTS 里'
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 6
  assert_no_log 'autopilot delete'
  autoteam_stub eject direction >/dev/null
  echo '新版方向报告规则' >> .autoteam/instructions/autopilots/direction.md
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply --only autopilots)
  assert_contains "$out" '已更新 autopilot「月度方向报告」'
  assert_contains "$(jq -r '.[] | select(.autopilot.title == "月度方向报告") | .autopilot.description' "$STUB_STATE/mc-autopilots.json")" '新版方向报告规则'
  : > "$STUB_LOG"
  autoteam_stub multica --apply --paused --only autopilots >/dev/null
  assert_no_log '--status paused'
  assert_eq "$(jq '[.[] | select(.autopilot.status == "active")] | length' "$STUB_STATE/mc-autopilots.json")" 6
  out=$(autoteam_stub doctor --skip-github)
  assert_contains "$out" '月度方向报告」未在 AUTOTEAM_AUTOPILOTS 里'
}

t_multica_legacy_autopilots_preserved() {
  setup_ready_repo
  autoteam_stub multica --apply --only agents,project >/dev/null
  sed -i 's/^AUTOTEAM_AUTOPILOTS=.*/AUTOTEAM_AUTOPILOTS=deploy-result,patrol,daily-digest,rule-review,health,direction/' .autoteam/autoteam.conf
  autoteam_stub multica --apply --only autopilots >/dev/null
  sed -i '/^AUTOTEAM_AUTOPILOTS=/d' .autoteam/autoteam.conf
  out=$(autoteam_stub multica --only autopilots)
  assert_contains "$out" 'autopilot「月度方向报告」已是最新'
  assert_not_contains "$out" '未在 AUTOTEAM_AUTOPILOTS 里'
  out=$(autoteam_stub upgrade --dry-run)
  assert_contains "$out" '没有 AUTOTEAM_AUTOPILOTS'
}

t_obsolete_autopilots_preview_apply_and_doctor() {
  setup_applied_repo
  autoteam_stub github --apply >/dev/null
  jq '. + [range(1;7) | {autopilot:{id:("old-" + tostring),title:("旧报告" + tostring),project_id:"proj-1",status:"active"},triggers:[]}]
    + [{autopilot:{id:"old-paused",title:"已暂停旧报告",project_id:"proj-1",status:"paused"},triggers:[]},
       {autopilot:{id:"other",title:"其他项目旧报告",project_id:"proj-other",status:"active"},triggers:[]}]' "$STUB_STATE/mc-autopilots.json" > "$WORK/aps.json"
  mv "$WORK/aps.json" "$STUB_STATE/mc-autopilots.json"
  cp "$STUB_STATE/mc-autopilots.json" "$WORK/before.json"
  for mode in preview apply doctor; do
    : > "$STUB_LOG"
    case $mode in
      preview) out=$(autoteam_stub multica --only autopilots) ;;
      apply) out=$(autoteam_stub multica --apply --only autopilots) ;;
      doctor) out=$(autoteam_stub doctor) ;;
    esac
    assert_eq "$(grep -c '⚠️.*旧报告[1-6].*已无生效定义' <<<"$out")" 6
    assert_contains "$out" '已暂停旧报告'
    assert_contains "$out" 'multica autopilot update old-1 --status paused'
    assert_not_contains "$out" '其他项目旧报告'
    assert_no_log 'autopilot update old-'
    assert_no_log 'autopilot delete'
  done
  assert_eq "$(cat "$STUB_STATE/mc-autopilots.json")" "$(cat "$WORK/before.json")"
  mkdir -p .autoteam/instructions/autopilots
  printf '%s\n' '---' 'title: 旧报告1' '---' > .autoteam/instructions/autopilots/retained.md
  out=$(autoteam_stub doctor)
  assert_not_contains "$out" '旧报告1」（old-1，active）已无生效定义'
}
