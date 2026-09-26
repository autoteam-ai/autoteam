# shellcheck shell=bash
# The test runner must clear host credentials before it loads fixtures.

t_runner_isolates_inherited_autoteam_vars() {
  for test in \
    t_ghapp_rejects_bad_role_and_missing_config \
    t_github_warns_when_no_apps; do
    out=$(env AUTOTEAM_IMPLEMENTER_APP_ID=1 AUTOTEAM_REVIEWER_APP_ID=2 \
      bash "$TESTS_DIR/run.sh" "$test" 2>&1)
    rc=$?
    assert_eq "$rc" 0 "$out"
    assert_contains "$out" "1 个测试，0 个失败"
  done
}
