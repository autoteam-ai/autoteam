# shellcheck shell=bash

t_instruction_budget_checks_package_and_rejects_growth() {
  cd "$ROOT" || return 1
  bash .autoteam/scripts/check-instruction-budget.sh || tfail "当前包内指令应在预算内"
  new_repo
  mkdir -p skills/autoteam/instructions/roles
  printf 'one\ntwo\n' > skills/autoteam/instructions/roles/planner.md
  printf '1 skills/autoteam/instructions/roles/planner.md\n' > budget
  if out=$(bash "$ROOT/.autoteam/scripts/check-instruction-budget.sh" budget 2>&1); then
    tfail "超预算应失败"
  fi
  assert_contains "$out" "先删 / 合并旧规则，或由人批准提高预算"
}

t_instruction_budget_template_checks_ejected_instructions() {
  setup_init_repo
  assert_file .autoteam/instruction-budget
  assert_file .autoteam/scripts/check-instruction-budget.sh
  assert_file_contains Makefile 'bash .autoteam/scripts/check-instruction-budget.sh'
  bash .autoteam/scripts/check-instruction-budget.sh || tfail "未 eject 时应通过"
  mkdir -p .autoteam/instructions/roles
  awk 'BEGIN { for (i=0; i<401; i++) print "line" }' > .autoteam/instructions/roles/planner.md
  # 同一次检查同时验证超预算与缺预算，保留两条独立诊断断言。
  printf 'new\n' > .autoteam/instructions/roles/new-role.md
  if out=$(bash .autoteam/scripts/check-instruction-budget.sh 2>&1); then
    tfail "eject 后超预算应失败"
  fi
  assert_contains "$out" 'planner.md (401 > 400 行)'
  assert_contains "$out" '指令缺少预算：.autoteam/instructions/roles/new-role.md'
}

t_instruction_budget_covers_runbooks() {
  new_repo
  mkdir -p skills/autoteam/instructions/runbooks
  printf 'one\n' > skills/autoteam/instructions/runbooks/foo.md
  : > budget
  if out=$(bash "$ROOT/.autoteam/scripts/check-instruction-budget.sh" budget 2>&1); then
    tfail "包内 runbook 缺预算行应失败"
  fi
  assert_contains "$out" '指令缺少预算：skills/autoteam/instructions/runbooks/foo.md'
  printf '5 skills/autoteam/instructions/runbooks/foo.md\n' > budget
  bash "$ROOT/.autoteam/scripts/check-instruction-budget.sh" budget || tfail "补上预算行后应通过"
}
