# shellcheck shell=bash
# 模板共享构建，但测试副本的 git、配置、桩状态和日志必须完全隔离。

t_repo_templates_parallel_build_and_isolation() {
  local result_dir=$TEST_BASE/template-results i pid first second
  local pids=()
  mkdir -p "$result_dir"
  # 统计真实 init / apply 调用；四个进程竞争同一套模板。
  eval "$(declare -f autoteam_stub | sed '1s/autoteam_stub/template_original_stub/')"
  # shellcheck disable=SC2329  # setup_* 间接调用这个桩包装器。
  autoteam_stub() {
    printf '%s\n' "$1" >> "$result_dir/builds"
    printf '%s\n' "$WORK/" >> "$STUB_LOG"
    template_original_stub "$@"
  }
  for i in 1 2 3 4; do
    (
      setup_applied_repo
      printf '%s\n' "$WORK" > "$result_dir/work-$i"
    ) &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || tfail "并发复制模板失败"
  done
  assert_eq "$(grep -c '^init$' "$result_dir/builds")" 1 "并发只初始化一次"
  assert_eq "$(grep -c '^multica$' "$result_dir/builds")" 1 "并发只同步一次"
  first=$(cat "$result_dir/work-1")
  second=$(cat "$result_dir/work-2")
  [ "$first" != "$second" ] || tfail "测试副本应有不同路径"
  assert_eq "$(git -C "$first" rev-parse --show-toplevel)" "$first"
  assert_eq "$(git -C "$second" config user.name)" tester
  assert_file "$first/.home/.multica/profiles/test/config.json"
  assert_eq "$(jq length "$first/.stub/mc-agents.json")" 4
  assert_eq "$(jq length "$first/.stub/mc-autopilots.json")" 5
  # 构建时记录的绝对路径应已指向副本。
  assert_file_contains "$first/.stub/log" "$first/"
  assert_not_contains "$(cat "$second/.stub/log")" "$first/"
  echo '[]' > "$first/.stub/mc-agents.json"
  echo changed >> "$first/.stub/log"
  git -C "$first" config user.name changed
  echo changed >> "$first/.autoteam/autoteam.conf"
  assert_eq "$(jq length "$second/.stub/mc-agents.json")" 4
  assert_eq "$(git -C "$second" config user.name)" tester
  assert_not_contains "$(cat "$second/.stub/log")" changed
  assert_not_contains "$(cat "$second/.autoteam/autoteam.conf")" changed
  setup_applied_repo
  assert_eq "$(jq length "$STUB_STATE/mc-agents.json")" 4 "后续副本也不受污染"
}

t_repo_templates_stages_and_custom_remote() {
  local result_dir=$TEST_BASE/template-results
  setup_init_repo acme/other
  assert_eq "$(git remote get-url origin)" https://github.com/acme/other.git
  assert_file_contains .autoteam/autoteam.conf AUTOTEAM_REPO=acme/other
  assert_file_contains Makefile AUTOTEAM-TODO
  assert_no_file "$STUB_STATE/mc-agents.json"
  setup_ready_repo acme/other
  assert_file_contains Makefile '@true'
  assert_file_contains .autoteam/registry.yaml claude@machine-a
  assert_eq "$(jq length "$STUB_STATE/mc-agents.json")" 0
  setup_applied_repo acme/other
  assert_eq "$(git remote get-url origin)" https://github.com/acme/other.git
  assert_file_contains .autoteam/autoteam.conf AUTOTEAM_REPO=acme/other
  assert_eq "$(jq -r '.[0].title' "$STUB_STATE/mc-projects.json")" other
}

t_repo_templates_build_failure_is_not_published_or_retried() {
  local result_dir=$TEST_BASE/template-results
  mkdir -p "$result_dir"
  # shellcheck disable=SC2329  # setup_* 间接调用这个桩包装器。
  autoteam_stub() { echo called >> "$result_dir/calls"; return 1; }
  out=$(setup_ready_repo 2>&1) && tfail "模板构建失败应传递到用例"
  out=$(setup_ready_repo 2>&1) && tfail "后续用例不能复制失败的模板"
  assert_contains "$out" "仓库模板构建失败"
  assert_eq "$(wc -l < "$result_dir/calls" | tr -d ' ')" 1 "失败模板不重复构建"
  assert_eq "$(find "$result_dir/repo-templates" -mindepth 1 -type d | wc -l | tr -d ' ')" 0 "不发布残缺模板、不残留锁"
}
