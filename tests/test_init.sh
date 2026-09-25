# shellcheck shell=bash
# autoteam init / diff / 模板渲染

t_render_keeps_actions_expressions_and_special_chars() {
  new_repo
  out=$(
    # shellcheck source=/dev/null
    . "$ROOT/skills/autoteam/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/skills/autoteam/lib/render.sh"
    AUTOTEAM_REPO='a&b/c\d' AUTOTEAM_OWNER=alice
    render_string 'x {{AUTOTEAM_REPO}} ${{ github.sha }} {{date}} {{AUTOTEAM_NOPE}} @{{AUTOTEAM_OWNER}} {{AUTOTEAM_OWNER}}'
  )
  assert_eq "$out" 'x a&b/c\d ${{ github.sha }} {{date}} {{AUTOTEAM_NOPE}} @alice alice'
}

t_init_fresh_repo_creates_everything() {
  new_repo acme/shop
  out=$(autoteam_offline init --owner alice --issue-prefix SHOP)
  assert_contains "$out" "新建 .github/workflows/gate.yml"
  for f in AGENTS.md Makefile .jscpd.json .gitignore .github/CODEOWNERS .github/workflows/deploy.yml \
           .github/workflows/rollback.yml .autoteam/autoteam.conf .autoteam/registry.yaml .autoteam/playbook.md; do
    assert_file "$f"
  done
  # 角色指令、autopilot、planner-mcp.json 默认不落盘
  for f in .autoteam/planner.md .autoteam/autopilots .autoteam/planner-mcp.json .autoteam/instructions; do
    assert_no_file "$f"
  done
  [ -x .autoteam/scripts/loop-guard.sh ] || tfail "loop-guard.sh 应可执行"
  assert_file_contains .github/CODEOWNERS "/.autoteam/     @alice"
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_REPO=acme/shop"
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_ISSUE_PREFIX=SHOP"
  assert_file_contains AGENTS.md "SHOP-123"
  assert_file_contains .github/workflows/deploy.yml "branches: [main]"
  assert_file_contains .github/workflows/deploy.yml "    environment: production"
  assert_file_contains .github/workflows/deploy.yml '${{ secrets.MULTICA_DEPLOY_HOOK }}'
  if grep -rq '{{AUTOTEAM_' --include='*' . 2>/dev/null; then tfail "还有没替换的占位符：$(grep -rl '{{AUTOTEAM_' .)"; fi
  [ -z "$(tail -c 1 .github/CODEOWNERS)" ] || tfail "CODEOWNERS 应以换行结尾"
}

t_init_is_idempotent() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  before=$(find . -path ./.git -prune -o -type f -print0 | xargs -0 shasum | sort)
  sleep 1 # 跨过一秒：.lock.json 不能只因为 generated_at 变了就重写
  out=$(autoteam_offline init --owner alice)
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
  out=$(autoteam_offline init --owner alice)
  assert_eq "$(cat Makefile)" "$(printf 'check:\n\tnpm test')" "已有 Makefile 不应被改"
  assert_contains "$out" "缺少目标： dev deploy"
  assert_eq "$(head -n 1 .github/CODEOWNERS)" "* @bob"
  assert_eq "$(grep -c '>>> autoteam >>>' .github/CODEOWNERS)" 1
  assert_file_contains AGENTS.md "已有规则"
  assert_eq "$(grep -c '<!-- >>> autoteam >>> -->' AGENTS.md)" 1
  autoteam_offline init --owner alice >/dev/null
  assert_eq "$(grep -c '<!-- >>> autoteam >>> -->' AGENTS.md)" 1 "受管块只能追加一次"
}

t_init_force_overwrites_templates_but_not_config() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  echo "# 本地改动" >> .github/workflows/gate.yml
  echo "AUTOTEAM_PR_MAX_LINES=999" >> .autoteam/autoteam.conf
  sed -i.bak 's#/Makefile        @alice#/Makefile        @carol#' .github/CODEOWNERS && rm -f .github/CODEOWNERS.bak
  out=$(autoteam_offline init)
  assert_contains "$out" "跳过 .github/workflows/gate.yml"
  assert_contains "$out" "受管块与模板不同"
  autoteam_offline init --force >/dev/null
  assert_eq "$(grep -c '本地改动' .github/workflows/gate.yml)" 0 "--force 应覆盖 gate.yml"
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_PR_MAX_LINES=999"
  assert_eq "$(grep -c carol .github/CODEOWNERS)" 0 "--force 应替换受管块"
}

t_init_force_only_named_files() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  echo "# 本地改动" >> .github/workflows/gate.yml
  echo "# 本地改动" >> .autoteam/playbook.md
  out=$(autoteam_offline init --force .autoteam/playbook.md)
  assert_eq "$(grep -c '本地改动' .autoteam/playbook.md)" 0 "指定的文件应被覆盖"
  assert_eq "$(grep -c '本地改动' .github/workflows/gate.yml)" 1 "没指定的文件不应被覆盖"
  assert_not_contains "$out" "gate.yml"
  assert_contains "$out" "覆盖 .autoteam/playbook.md"
}

t_init_dry_run_writes_nothing() {
  new_repo
  out=$(autoteam_offline init --dry-run --owner alice)
  assert_contains "$out" "没有写任何文件"
  assert_no_file .autoteam/autoteam.conf
  assert_no_file AGENTS.md
}

t_init_free_private_repo_drops_environment() {
  new_repo
  out=$(STUB_SCENARIO=free-private autoteam_stub init)
  assert_file_contains .autoteam/autoteam.conf "AUTOTEAM_DEPLOY_ENVIRONMENT="
  assert_eq "$(grep -c '^AUTOTEAM_DEPLOY_ENVIRONMENT=$' .autoteam/autoteam.conf)" 1
  assert_eq "$(grep -c 'environment: production' .github/workflows/deploy.yml)" 0
  assert_file_contains .github/CODEOWNERS "@alice"
  assert_contains "$out" "deploy.yml 不声明 environment"
}

t_diff_shows_block_changes() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  out=$(autoteam_offline diff)
  assert_contains "$out" "与模板一致"
  sed -i.bak 's#/Makefile        @alice#/Makefile        @carol#' .github/CODEOWNERS && rm -f .github/CODEOWNERS.bak
  out=$(autoteam_offline diff .github/CODEOWNERS)
  assert_contains "$out" "-/Makefile        @carol"
}

t_registry_parsing_and_validation() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  rows=$(
    # shellcheck source=/dev/null
    for l in common registry; do . "$ROOT/skills/autoteam/lib/$l.sh"; done
    registry_agents .autoteam/registry.yaml
  )
  assert_eq "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" 6
  assert_eq "$(printf '%s\n' "$rows" | sed -n 2p)" "$(printf 'impl-claude\timplementer\tclaude-max\tclaude@machine-a\tdefault\t2\t-\t-')"
  printf 'agents:\n  a: { role: planner, runtime: x }\n  b: { role: boss, runtime: y }\n  c:\n    role: reviewer\n' > bad.yaml
  out=$(
    # shellcheck source=/dev/null
    for l in common registry; do . "$ROOT/skills/autoteam/lib/$l.sh"; done
    registry_validate "$(registry_agents bad.yaml)"; echo "rc=$?"
  )
  assert_contains "$out" "role 不对：boss"
  assert_contains "$out" "不是单行 flow 映射"
  assert_contains "$out" "至少要 1 个 implementer"
  assert_contains "$out" "rc=1"
}

# 模拟"装机时的模板和现在不一样"：改文件，再把 lock 里的 sha 改成改后的样子
fake_old_install() {
  echo "# 旧模板" >> "$1"
  sha=$(shasum -a 256 < "$1" | cut -d' ' -f1)
  sed -i.bak "s|\(\"$1\": { \"kind\": \"file\", \"sha256\": \"\)[0-9a-f]*|\1$sha|" .autoteam/.lock.json
  rm -f .autoteam/.lock.json.bak
}

t_init_writes_lock() {
  new_repo
  autoteam_offline init --owner alice >/dev/null
  assert_eq "$(jq -r .version .autoteam/.lock.json)" "$(autoteam_offline version | cut -d' ' -f2)"
  assert_eq "$(jq -r '.files[".github/workflows/gate.yml"].sha256' .autoteam/.lock.json)" \
    "$(shasum -a 256 < .github/workflows/gate.yml | cut -d' ' -f1)"
  assert_eq "$(jq -r '.files["AGENTS.md"].kind' .autoteam/.lock.json)" block
  # 用户的文件不进 lock；lock 本身要入库，不能被受管块忽略
  assert_eq "$(jq -r '.files | has(".autoteam/autoteam.conf") or has(".autoteam/registry.yaml") or has("Makefile")' .autoteam/.lock.json)" false
  git check-ignore -q .autoteam/.lock.json && tfail ".lock.json 不该被 .gitignore 忽略"
  assert_contains "$(autoteam_offline doctor --skip-github --skip-multica)" "与当前 autoteam 一致"
  # 已有 lock 时 init 保留版本号，由 upgrade 推进
  sed -i.bak 's/"version": ".*"/"version": "0.0.1"/' .autoteam/.lock.json
  autoteam_offline init >/dev/null
  assert_eq "$(jq -r .version .autoteam/.lock.json)" 0.0.1
  assert_contains "$(autoteam_offline doctor --skip-github --skip-multica)" "记录的版本是 0.0.1"
}

t_upgrade_overwrites_unmodified_keeps_modified() {
  setup_ready_repo
  fake_old_install .autoteam/playbook.md
  echo "# 本地加的" >> .autoteam/scripts/loop-guard.sh
  kept=$(jq -r '.files[".autoteam/scripts/loop-guard.sh"].sha256' .autoteam/.lock.json)

  out=$(autoteam_offline upgrade --dry-run)
  assert_contains "$out" "没有写任何文件"
  assert_file_contains .autoteam/playbook.md "# 旧模板"

  out=$(autoteam_offline upgrade)
  assert_contains "$out" "覆盖 .autoteam/playbook.md"
  assert_eq "$(grep -c '旧模板' .autoteam/playbook.md)" 0 "没改过的文件应被覆盖"
  assert_contains "$out" "本地已修改，未覆盖 .autoteam/scripts/loop-guard.sh"
  assert_contains "$out" "-# 本地加的"
  assert_contains "$out" "autoteam init --force <文件>"
  assert_file_contains .autoteam/scripts/loop-guard.sh "# 本地加的"
  assert_eq "$(jq -r '.files[".autoteam/scripts/loop-guard.sh"].sha256' .autoteam/.lock.json)" "$kept" "改过的文件保留原记录"
  assert_contains "$out" "已是最新 .github/workflows/gate.yml"
}

t_upgrade_without_lock_keeps_differing_files() {
  setup_ready_repo
  rm .autoteam/.lock.json
  echo "# 本地加的运行时" >> .github/workflows/gate.yml
  out=$(autoteam_offline doctor --skip-github --skip-multica)
  assert_contains "$out" "没有 .autoteam/.lock.json"
  out=$(autoteam_offline upgrade)
  assert_contains "$out" "无法判断是否改过，未覆盖 .github/workflows/gate.yml"
  assert_file_contains .github/workflows/gate.yml "本地加的运行时"
  out=$(autoteam_offline upgrade)
  assert_contains "$out" "本地已修改，未覆盖 .github/workflows/gate.yml"
}

# autoteam diff --check：CI 用来挡住"改了模板但没同步到本仓库"的漂移
t_diff_check_uses_lock() {
  setup_ready_repo
  out=$(autoteam_offline diff --check) ; rc=$?
  assert_eq "$rc" 0 "刚装完不该有漂移"
  assert_contains "$out" "与模板一致"
  assert_not_contains "$out" "registry.yaml"

  # 用户改过的不算漂移
  echo "# 本项目加的运行时" >> .github/workflows/gate.yml
  out=$(autoteam_offline diff --check) ; rc=$?
  assert_eq "$rc" 0
  assert_contains "$out" "本地已修改 .github/workflows/gate.yml"

  # 模板变了、文件还是装机时的样子：漂移
  fake_old_install .autoteam/playbook.md
  out=$(autoteam_offline diff --check) ; rc=$?
  assert_eq "$rc" 1 "有漂移要退出码 1"
  assert_contains "$out" ".autoteam/playbook.md"
  assert_contains "$out" "autoteam upgrade"
}

# autoteam eject：把包内指令复制到 .autoteam/instructions/，此后由用户维护
t_eject_role_copies_package_file() {
  setup_ready_repo
  out=$(autoteam_offline eject reviewer)
  assert_contains "$out" "已 eject .autoteam/instructions/roles/reviewer.md"
  assert_contains "$out" "此后由你维护，升级不会覆盖"
  assert_eq "$(cat .autoteam/instructions/roles/reviewer.md)" "$(cat "$ROOT/skills/autoteam/instructions/roles/reviewer.md")"
  assert_no_file .autoteam/instructions/roles/planner.md
}

t_eject_autopilot_and_mcp() {
  setup_ready_repo
  autoteam_offline eject patrol planner-mcp.json >/dev/null
  assert_file .autoteam/instructions/autopilots/patrol.md
  assert_file .autoteam/instructions/planner-mcp.json
  out=$(autoteam_offline eject patrol.md)
  assert_contains "$out" "已存在，保留 .autoteam/instructions/autopilots/patrol.md"
}

t_eject_all() {
  setup_ready_repo
  autoteam_offline eject --all >/dev/null
  for f in planner implementer reviewer auditor; do assert_file ".autoteam/instructions/roles/$f.md"; done
  assert_file .autoteam/instructions/planner-mcp.json
  assert_eq "$(find .autoteam/instructions/autopilots -name "*.md" | wc -l | tr -d " ")" 10
}

t_eject_does_not_overwrite_existing() {
  setup_ready_repo
  autoteam_offline eject reviewer >/dev/null
  echo "# 我的改动" >> .autoteam/instructions/roles/reviewer.md
  out=$(autoteam_offline eject reviewer)
  assert_contains "$out" "已存在，保留"
  assert_file_contains .autoteam/instructions/roles/reviewer.md "# 我的改动"
}

t_eject_diff_prints_without_writing() {
  setup_ready_repo
  out=$(autoteam_offline eject --diff reviewer)
  assert_contains "$out" "reviewer：未 eject"
  assert_no_file .autoteam/instructions

  autoteam_offline eject reviewer >/dev/null
  out=$(autoteam_offline eject --diff reviewer)
  assert_contains "$out" "已 eject，与包内一致"

  echo "# 我的改动" >> .autoteam/instructions/roles/reviewer.md
  out=$(autoteam_offline eject --diff reviewer)
  assert_contains "$out" "+# 我的改动"
  assert_file_contains .autoteam/instructions/roles/reviewer.md "# 我的改动"
}

t_eject_rejects_bad_usage() {
  setup_ready_repo
  out=$(autoteam_offline eject nosuch 2>&1) && tfail "不认识的目标应失败"
  assert_contains "$out" "不认识的目标：nosuch"
  out=$(autoteam_offline eject 2>&1) && tfail "没有目标应失败"
  assert_contains "$out" "需要指定目标或 --all"
  out=$(autoteam_offline eject -h)
  assert_contains "$out" "用法：autoteam eject"
}
