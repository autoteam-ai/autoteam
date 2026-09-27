# shellcheck shell=bash

t_protected_paths_directory_and_unmatched() {
  new_repo
  mkdir -p .github
  printf '/.github/ @owner\n/skills/autoteam/ @owner\n' > .github/CODEOWNERS
  script=$ROOT/skills/autoteam/templates/autoteam/scripts/protected-paths.sh
  out=$(bash "$script" --files .github/workflows/gate.yml skills/autoteam/SKILL.md docs/README.md)
  assert_eq "$out" "$(printf '.github/workflows/gate.yml\nskills/autoteam/SKILL.md')"
  bash "$script" --files docs/README.md >/dev/null
  assert_eq "$?" 1 "普通文档不应命中"
}

t_protected_paths_last_matching_rule() {
  new_repo
  mkdir -p .github
  printf '* @owner\n!/docs/ @owner\n/docs/ @other\n' > .github/CODEOWNERS
  script=$ROOT/skills/autoteam/templates/autoteam/scripts/protected-paths.sh
  out=$(bash "$script" --files docs/README.md)
  assert_eq "$out" 'docs/README.md' '最后一条有效规则应生效'
}

t_protected_paths_lock_and_error() {
  new_repo
  mkdir -p .github
  printf '/src/ @owner\n' > .github/CODEOWNERS
  script=$ROOT/skills/autoteam/templates/autoteam/scripts/protected-paths.sh
  out=$(bash "$script" --files package-lock.json .autoteam/.lock.json)
  assert_eq "$out" "$(printf 'package-lock.json\n.autoteam/.lock.json')"
  bash "$script" --codeowners missing --files src/app.ts >/dev/null 2>&1
  assert_eq "$?" 2 '缺少 CODEOWNERS 应报错'
}

t_protected_paths_pr_uses_base_codeowners() {
  new_repo
  mkdir -p .github "$WORK/stub"
  printf '/docs/ @local\n' > .github/CODEOWNERS
  cat > "$WORK/stub/gh" <<'EOF'
#!/usr/bin/env bash
case $* in
  'pr view 42 --json baseRefName --jq .baseRefName') printf 'main\n' ;;
  'pr view 42 --json files --jq .files[].path') printf '.github/workflows/gate.yml\ndocs/README.md\n' ;;
  'api repos/{owner}/{repo}/contents/.github/CODEOWNERS?ref=main -H Accept: application/vnd.github.raw') printf '/.github/ @base\n' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$WORK/stub/gh"
  out=$(PATH="$WORK/stub:$PATH" bash "$ROOT/skills/autoteam/templates/autoteam/scripts/protected-paths.sh" --pr 42)
  assert_eq "$out" '.github/workflows/gate.yml' 'PR 模式应读取目标分支 CODEOWNERS'
}
