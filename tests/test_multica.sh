# shellcheck shell=bash
# autoteam multica / runtimes：预览、新建、再跑变成无改动、runtime 找不到、webhook 写 secret

t_multica_preview_makes_no_writes() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub multica)
  assert_contains "$out" "profile：test"
  assert_contains "$out" "[预览] 新建状态 shipping（待上线，类别 started）"
  assert_contains "$out" "[预览] 新建 agent planner（planner，runtime rt-c-cla，模型 default，并发 1）"
  assert_contains "$out" "[预览] 新建 agent rev-codex（reviewer，runtime rt-b-cod，模型 gpt-5.5，并发 2）"
  assert_contains "$out" "runtime codex@machine-b 现在不在线"
  assert_contains "$out" "[预览] 新建项目 shop"
  assert_contains "$out" "[预览] 新建 autopilot「推进巡检」（planner，run_only，0 */2 * * *）"
  assert_no_log "agent create"
  assert_no_log "curl POST"
}

# shellcheck disable=SC2153  # ROOT 来自 tests/lib.sh
t_multica_apply_creates_everything() {
  setup_ready_repo
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply)
  assert_contains "$out" "已新建状态 shipping"
  assert_log 'BODY POST /api/issue-statuses {"key":"shipping","name":"待上线","category":"started","color":"#14b8a6"'
  assert_log "curl POST https://api.multica.test/api/issue-statuses auth=ok"
  assert_eq "$(jq length "$STUB_STATE/mc-agents.json")" 4
  assert_eq "$(jq -r '.[] | select(.name == "impl-claude") | .runtime_id' "$STUB_STATE/mc-agents.json")" rt-a-claude-0000
  assert_eq "$(jq -r '.[] | select(.name == "auditor") | .runtime_id' "$STUB_STATE/mc-agents.json")" rt-c-claude-0000
  assert_eq "$(jq -r '.[] | select(.name == "rev-codex") | .instructions' "$STUB_STATE/mc-agents.json" | head -n 1)" "$(head -n 1 "$ROOT/skills/autoteam/instructions/roles/reviewer.md")" "没 eject 时取包内指令"
  assert_log "agent create --name rev-codex --runtime-id rt-b-codex-00000"
  assert_log "--model gpt-5.5"
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 10
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "每日摘要") | .triggers[0].cron_expression' "$STUB_STATE/mc-autopilots.json")" "0 9 * * *"
  assert_eq "$(jq -r '.[] | select(.autopilot.title == "每日摘要") | .triggers[0].timezone' "$STUB_STATE/mc-autopilots.json")" "Asia/Shanghai"
  assert_log "autopilot create --title 每日摘要 --agent agent-planner --mode create_issue"
  assert_log "--issue-title-template 每日摘要 {{date}}"
  assert_log "--subscriber Alice"
  assert_log "autopilot create --title agent 成绩单 --agent agent-auditor"
  assert_eq "$(cat "$STUB_STATE/secret-MULTICA_DEPLOY_HOOK")" "https://api.multica.test/api/webhooks/SECRET-TOKEN-123"
  assert_not_contains "$out" "SECRET-TOKEN-123" "webhook 地址含凭据，不应打印"
  assert_not_contains "$out" "mul_test_token" "token 不应打印"
  assert_no_log "mul_test_token"
}

t_multica_second_apply_is_noop() {
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
  : > "$STUB_LOG"
  out=$(autoteam_stub multica --apply)
  assert_contains "$out" "状态 shipping（待上线）已存在"
  assert_contains "$out" "agent planner 已是最新"
  assert_contains "$out" "autopilot「推进巡检」已是最新"
  assert_contains "$out" "定时触发已是 0 */2 * * *（Asia/Shanghai）"
  assert_contains "$out" "部署 webhook 已存在，GitHub secret MULTICA_DEPLOY_HOOK 已设置"
  assert_no_log "agent create"
  assert_no_log "autopilot create"
  assert_no_log "trigger-add"
  assert_no_log "curl POST"
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
  assert_eq "$(jq '[.[] | select(.autopilot.status == "paused")] | length' "$STUB_STATE/mc-autopilots.json")" 10
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
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 10
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
  setup_ready_repo
  autoteam_stub multica --apply >/dev/null
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

t_multica_api_failure_keeps_independent_steps() {
  setup_ready_repo
  touch "$STUB_STATE/curl-timeout"
  out=$(autoteam_stub multica --apply 2>&1) && tfail "状态读取失败应返回非零"
  assert_contains "$out" "已完成： agents project autopilots"
  assert_contains "$out" "失败或部分完成： statuses"
  assert_contains "$out" "未执行：无"
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 10
}

# 无 profile 目录、多个 profile、仅环境变量：agent runtime 只有环境变量
t_multica_profile_missing_dir_dies() {
  setup_ready_repo
  rm -rf "$WORK/.home/.multica"
  out=$(autoteam_stub multica 2>&1) && tfail "没有 profile 也没有环境变量应报错"
  assert_contains "$out" "multica 默认 profile 没有配置服务器"
}

t_multica_profile_multiple_dies() {
  setup_ready_repo
  mkdir -p "$WORK/.home/.multica/profiles/other"
  out=$(autoteam_stub multica 2>&1) && tfail "多个 profile 应报错"
  assert_contains "$out" "multica 默认 profile 没有配置服务器"
  assert_contains "$out" "other"
}

t_multica_env_only_needs_no_profile() {
  setup_ready_repo
  rm -rf "$WORK/.home/.multica"
  : > "$STUB_LOG"
  out=$(TEST_MULTICA_SERVER_URL=https://api.multica.test TEST_MULTICA_TOKEN=mul_test_token autoteam_stub multica --apply --only statuses)
  assert_contains "$out" "已新建状态 shipping"
  assert_no_log "--profile"
  assert_log "curl POST https://api.multica.test/api/issue-statuses auth=ok"
}

t_multica_archives_empty_legacy_statuses_and_skips_used_ones() {
  setup_ready_repo
  printf '%s\n' '[{"id":"status-approved","key":"approved","name":"已批准","category":"todo","archived_at":null},{"id":"status-code-review","key":"code_review","name":"待评审","category":"in_progress","archived_at":null},{"id":"status-rework","key":"rework","name":"返工","category":"in_progress","archived_at":null}]' > "$STUB_STATE/mc-statuses.json"
  printf '%s\n' '[{"id":"issue-1","identifier":"TST-1","title":"仍在返工"}]' > "$STUB_STATE/mc-issues-rework.json"
  out=$(autoteam_stub multica --only statuses)
  assert_contains "$out" "[预览] 归档旧状态 approved"
  assert_no_log "curl DELETE"
  out=$(autoteam_stub multica --apply --only statuses)
  assert_contains "$out" "已归档旧状态 approved"
  assert_contains "$out" "已归档旧状态 code_review"
  assert_contains "$out" "旧状态 rework 仍有任务：TST-1 仍在返工"
  assert_contains "$out" "未归档"
  assert_eq "$(jq -r '.[] | select(.key == "approved") | .archived_at' "$STUB_STATE/mc-statuses.json")" "2099-01-01T00:00:00Z"
  assert_eq "$(jq -r '.[] | select(.key == "rework") | .archived_at' "$STUB_STATE/mc-statuses.json")" "null"
  assert_log "curl DELETE https://api.multica.test/api/issue-statuses/status-approved auth=ok"
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
  assert_eq "$(grep -c . <<<"$out")" 11 "10 个包内的 + 1 个新增的，同名不重复"
  assert_contains "$out" ".autoteam/instructions/autopilots/patrol.md"
  assert_not_contains "$out" "$ROOT/skills/autoteam/instructions/autopilots/patrol.md" "同名以 eject 的为准"
  assert_contains "$out" ".autoteam/instructions/autopilots/extra.md"
  assert_contains "$out" "$ROOT/skills/autoteam/instructions/autopilots/roadmap.md"
}

t_instructions_have_no_placeholders() {
  if grep -rq '{{AUTOTEAM_' "$ROOT/skills/autoteam/instructions"; then
    tfail "instructions/ 里不该再有占位符：$(grep -rl '{{AUTOTEAM_' "$ROOT/skills/autoteam/instructions")"
  fi
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
  sed -i.bak 's|^按 .autoteam/planner.md 做一次推进巡检|自定义巡检 runbook|' .autoteam/instructions/autopilots/patrol.md && rm -f .autoteam/instructions/autopilots/patrol.md.bak
  : > "$STUB_LOG"
  autoteam_stub multica --apply >/dev/null
  assert_eq "$(jq length "$STUB_STATE/mc-autopilots.json")" 10 "同名以 eject 的为准，不重复建"
  assert_contains "$(jq -r '.[] | select(.autopilot.title == "推进巡检") | .autopilot.description' "$STUB_STATE/mc-autopilots.json")" "自定义巡检 runbook"
}
