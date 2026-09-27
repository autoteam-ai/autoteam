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
  new_repo
  autoteam_offline init --owner alice >/dev/null
  assert_file .autoteam/instruction-budget
  assert_file .autoteam/scripts/check-instruction-budget.sh
  assert_file_contains Makefile 'bash .autoteam/scripts/check-instruction-budget.sh'
  bash .autoteam/scripts/check-instruction-budget.sh || tfail "未 eject 时应通过"
  mkdir -p .autoteam/instructions/roles
  awk 'BEGIN { for (i=0; i<401; i++) print "line" }' > .autoteam/instructions/roles/planner.md
  if out=$(bash .autoteam/scripts/check-instruction-budget.sh 2>&1); then
    tfail "eject 后超预算应失败"
  fi
  assert_contains "$out" 'planner.md (401 > 400 行)'
  printf 'new\n' > .autoteam/instructions/roles/new-role.md
  out=$(bash .autoteam/scripts/check-instruction-budget.sh 2>&1)
  assert_contains "$out" '指令缺少预算：.autoteam/instructions/roles/new-role.md'
}
