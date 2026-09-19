# shellcheck shell=bash
# aiwf init / diff / 模板渲染

t_render_keeps_actions_expressions_and_special_chars() {
  new_repo
  out=$(
    # shellcheck source=/dev/null
    . "$ROOT/skills/ai-workflow/scripts/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/skills/ai-workflow/scripts/lib/render.sh"
    AIWF_REPO='a&b/c\d' AIWF_OWNER=alice
    render_string 'x {{AIWF_REPO}} ${{ github.sha }} {{date}} {{AIWF_NOPE}} @{{AIWF_OWNER}} {{AIWF_OWNER}}'
  )
  assert_eq "$out" 'x a&b/c\d ${{ github.sha }} {{date}} {{AIWF_NOPE}} @alice alice'
}

t_init_fresh_repo_creates_everything() {
  new_repo acme/shop
  out=$(aiwf_offline init --owner alice --issue-prefix SHOP)
  assert_contains "$out" "新建 .github/workflows/gate.yml"
  for f in AGENTS.md Makefile .jscpd.json .gitignore .github/CODEOWNERS .github/workflows/deploy.yml \
           .github/workflows/rollback.yml ops/agents/aiwf.conf ops/agents/registry.yaml ops/agents/planner.md \
           ops/agents/autopilots/patrol.md ops/agents/autopilots/deploy-result.md; do
    assert_file "$f"
  done
  [ -x ops/agents/scripts/loop-guard.sh ] || tfail "loop-guard.sh 应可执行"
  assert_file_contains .github/CODEOWNERS "/ops/agents/     @alice"
  assert_file_contains ops/agents/aiwf.conf "AIWF_REPO=acme/shop"
  assert_file_contains ops/agents/aiwf.conf "AIWF_ISSUE_PREFIX=SHOP"
  assert_file_contains AGENTS.md "SHOP-123"
  assert_file_contains .github/workflows/deploy.yml "branches: [main]"
  assert_file_contains .github/workflows/deploy.yml "    environment: production"
  assert_file_contains .github/workflows/deploy.yml '${{ secrets.MULTICA_DEPLOY_HOOK }}'
  if grep -rq '{{AIWF_' --include='*' . 2>/dev/null; then tfail "还有没替换的占位符：$(grep -rl '{{AIWF_' .)"; fi
  [ -z "$(tail -c 1 .github/CODEOWNERS)" ] || tfail "CODEOWNERS 应以换行结尾"
}

t_init_is_idempotent() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
  before=$(find . -path ./.git -prune -o -type f -print0 | xargs -0 shasum | sort)
  out=$(aiwf_offline init --owner alice)
  after=$(find . -path ./.git -prune -o -type f -print0 | xargs -0 shasum | sort)
  assert_eq "$after" "$before" "第二次运行不应改动文件"
  assert_not_contains "$out" "新建"
  assert_not_contains "$out" "追加"
}

t_init_respects_existing_files() {
  new_repo
  printf 'check:\n\tnpm test\n' > Makefile
  printf '# Shop\n\n已有规则' > AGENTS.md
  mkdir -p .github && printf '* @bob\n' > .github/CODEOWNERS
  out=$(aiwf_offline init --owner alice)
  assert_eq "$(cat Makefile)" "$(printf 'check:\n\tnpm test')" "已有 Makefile 不应被改"
  assert_contains "$out" "缺少目标： dev deploy"
  assert_eq "$(head -n 1 .github/CODEOWNERS)" "* @bob"
  assert_eq "$(grep -c '>>> ai-workflow >>>' .github/CODEOWNERS)" 1
  assert_file_contains AGENTS.md "已有规则"
  assert_eq "$(grep -c '<!-- >>> ai-workflow >>> -->' AGENTS.md)" 1
  aiwf_offline init --owner alice >/dev/null
  assert_eq "$(grep -c '<!-- >>> ai-workflow >>> -->' AGENTS.md)" 1 "受管块只能追加一次"
}

t_init_force_overwrites_templates_but_not_config() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
  echo "# 本地改动" >> .github/workflows/gate.yml
  echo "AIWF_PR_MAX_LINES=999" >> ops/agents/aiwf.conf
  sed -i.bak 's#/Makefile        @alice#/Makefile        @carol#' .github/CODEOWNERS && rm -f .github/CODEOWNERS.bak
  out=$(aiwf_offline init)
  assert_contains "$out" "跳过 .github/workflows/gate.yml"
  assert_contains "$out" "受管块与模板不同"
  aiwf_offline init --force >/dev/null
  assert_eq "$(grep -c '本地改动' .github/workflows/gate.yml)" 0 "--force 应覆盖 gate.yml"
  assert_file_contains ops/agents/aiwf.conf "AIWF_PR_MAX_LINES=999"
  assert_eq "$(grep -c carol .github/CODEOWNERS)" 0 "--force 应替换受管块"
}

t_init_force_only_named_files() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
  echo "# 本地改动" >> .github/workflows/gate.yml
  echo "# 本地改动" >> ops/agents/reviewer.md
  out=$(aiwf_offline init --force ops/agents/reviewer.md)
  assert_eq "$(grep -c '本地改动' ops/agents/reviewer.md)" 0 "指定的文件应被覆盖"
  assert_eq "$(grep -c '本地改动' .github/workflows/gate.yml)" 1 "没指定的文件不应被覆盖"
  assert_not_contains "$out" "gate.yml"
  assert_contains "$out" "覆盖 ops/agents/reviewer.md"
}

t_init_dry_run_writes_nothing() {
  new_repo
  out=$(aiwf_offline init --dry-run --owner alice)
  assert_contains "$out" "没有写任何文件"
  assert_no_file ops/agents/aiwf.conf
  assert_no_file AGENTS.md
}

t_init_free_private_repo_drops_environment() {
  new_repo
  out=$(STUB_SCENARIO=free-private aiwf_stub init)
  assert_file_contains ops/agents/aiwf.conf "AIWF_DEPLOY_ENVIRONMENT="
  assert_eq "$(grep -c '^AIWF_DEPLOY_ENVIRONMENT=$' ops/agents/aiwf.conf)" 1
  assert_eq "$(grep -c 'environment: production' .github/workflows/deploy.yml)" 0
  assert_file_contains .github/CODEOWNERS "@alice"
  assert_contains "$out" "deploy.yml 不声明 environment"
}

t_diff_shows_block_changes() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
  out=$(aiwf_offline diff)
  assert_contains "$out" "与模板一致"
  sed -i.bak 's#/Makefile        @alice#/Makefile        @carol#' .github/CODEOWNERS && rm -f .github/CODEOWNERS.bak
  out=$(aiwf_offline diff .github/CODEOWNERS)
  assert_contains "$out" "-/Makefile        @carol"
}

t_registry_parsing_and_validation() {
  new_repo
  aiwf_offline init --owner alice >/dev/null
  rows=$(
    # shellcheck source=/dev/null
    for l in common registry; do . "$ROOT/skills/ai-workflow/scripts/lib/$l.sh"; done
    registry_agents ops/agents/registry.yaml
  )
  assert_eq "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" 6
  assert_eq "$(printf '%s\n' "$rows" | sed -n 2p)" "$(printf 'impl-claude\timplementer\tclaude-max\tclaude@machine-a\tdefault\t2\t-\t-')"
  printf 'agents:\n  a: { role: planner, runtime: x }\n  b: { role: boss, runtime: y }\n  c:\n    role: reviewer\n' > bad.yaml
  out=$(
    # shellcheck source=/dev/null
    for l in common registry; do . "$ROOT/skills/ai-workflow/scripts/lib/$l.sh"; done
    registry_validate "$(registry_agents bad.yaml)"; echo "rc=$?"
  )
  assert_contains "$out" "role 不对：boss"
  assert_contains "$out" "不是单行 flow 映射"
  assert_contains "$out" "至少要 1 个 implementer"
  assert_contains "$out" "rc=1"
}
