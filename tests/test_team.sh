# shellcheck shell=bash
# 团队仓库与成员项目（design/0003）：登记、配置分层、-P、运行时脚本、启动器

# 团队仓库 acme/team（已 init）登记成员 acme/app，再建成员仓库 acme/app 的 clone（不装 autoteam 文件）。
# 结束时在成员 clone 里；TEAM 是团队仓库目录，成员命令都带 AUTOTEAM_TEAM_DIR=$TEAM
setup_team() {
  new_repo acme/team
  TEAM=$WORK
  autoteam_offline init --owner alice --workspace ws >/dev/null
  set_conf AUTOTEAM_IMPLEMENTER_APP_ID 111
  set_conf AUTOTEAM_PR_MAX_LINES 300
  set_conf AUTOTEAM_DEPLOY_ENVIRONMENT prod-team
  printf '# 团队经验\n' > .autoteam/playbook.md
  autoteam_offline project add acme/app --default-branch trunk >/dev/null
  printf 'AUTOTEAM_PR_MAX_LINES=500\n' >> .autoteam/projects/acme/app/project.conf
  printf '# app 经验\n' > .autoteam/projects/acme/app/playbook.md
  new_repo acme/app
  MEMBER=$WORK
}

# 改团队仓库 autoteam.conf 里的一个键（同名键第一条生效，所以替换而不是追加）
set_conf() {
  local f=$TEAM/.autoteam/autoteam.conf
  if grep -q "^$1=" "$f"; then
    sed "s|^$1=.*|$1=$2|" "$f" > "$f.new" && mv "$f.new" "$f"
  else
    printf '%s=%s\n' "$1" "$2" >> "$f"
  fi
}

team_cli() { env AUTOTEAM_TEAM_DIR="$TEAM" PATH="$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" HOME="$WORK/.home" NO_COLOR=1 bash "$AUTOTEAM" "$@"; }

t_team_project_add_registers_member_once() {
  setup_team
  cd "$TEAM" || return
  assert_file .autoteam/projects/acme/app/project.conf
  assert_file .autoteam/projects/acme/app/playbook.md
  assert_file_contains .autoteam/projects/acme/app/project.conf "AUTOTEAM_DEFAULT_BRANCH=trunk"
  out=$(autoteam_offline project add acme/app)
  assert_contains "$out" "acme/app 已登记"
  out=$(autoteam_offline project add acme/team 2>&1) && tfail "登记团队仓库自己应失败"
  assert_contains "$out" "就是团队仓库"
  out=$(autoteam_offline project add not-a-repo 2>&1) && tfail "仓库名格式错误应失败"
  assert_contains "$out" "owner/name"
}

t_team_member_conf_layers_team_and_project() {
  setup_team
  out=$(team_cli conf AUTOTEAM_REPO AUTOTEAM_MULTICA_WORKSPACE AUTOTEAM_PR_MAX_LINES AUTOTEAM_CHECK_NAME \
    AUTOTEAM_DEPLOY_ENVIRONMENT AUTOTEAM_TEAM_HOME AUTOTEAM_MULTICA_PROJECT AUTOTEAM_DEFAULT_BRANCH AUTOTEAM_AUTOPILOTS)
  assert_eq "$out" "acme/app
ws
500
autoteam / check
production
acme/team
app
trunk"
  # 在团队仓库里用 -P 指定成员项目，结果一样
  cd "$TEAM" || return
  assert_eq "$(team_cli -P acme/app conf AUTOTEAM_REPO AUTOTEAM_PR_MAX_LINES)" "acme/app
500"
  # -P 指团队仓库自己时就是团队配置
  assert_eq "$(team_cli -P acme/team conf AUTOTEAM_REPO AUTOTEAM_PR_MAX_LINES)" "acme/team
300"
  out=$(team_cli -P acme/nope conf 2>&1) && tfail "没登记的项目应失败"
  assert_contains "$out" "没有在团队仓库登记"
  # 全部打印时标明成员项目和团队仓库
  cd "$MEMBER" || return
  out=$(team_cli conf)
  assert_contains "$out" "# 成员项目 acme/app，团队仓库 acme/team"
  assert_contains "$out" "AUTOTEAM_IMPLEMENTER_APP_ID=111"
}

t_team_unregistered_repo_is_not_autoteam_project() {
  setup_team
  new_repo acme/other
  out=$(team_cli conf 2>&1) && tfail "没登记也没 conf 的仓库应失败"
  assert_contains "$out" "不是 autoteam 项目"
}

t_team_projects_lists_team_first() {
  setup_team
  cd "$TEAM" || return
  assert_eq "$(autoteam_offline projects)" "acme/team	team
acme/app	app"
  out=$(team_cli projects --json)
  assert_eq "$(jq -c '.' <<<"$out")" '[{"repo":"acme/team","project":"team","team":true},{"repo":"acme/app","project":"app"}]'
  # 成员 clone 里、不在任何仓库里，列出的都是同一个团队
  cd "$MEMBER" || return
  assert_eq "$(team_cli projects | cut -f1 | tr '\n' ' ')" "acme/team acme/app "
  cd "$(mktemp -d "$TEST_BASE/nogit.XXXXXX")" || return
  assert_eq "$(team_cli projects | cut -f1 | tr '\n' ' ')" "acme/team acme/app "
}

t_team_member_playbook_and_eject() {
  setup_team
  out=$(team_cli playbook)
  assert_eq "$out" "# 团队经验

# app 经验"
  out=$(team_cli eject planner 2>&1) && tfail "成员项目不能 eject"
  assert_contains "$out" "到团队仓库里 eject"
}

t_team_member_scripts_use_effective_conf() {
  setup_team
  mkdir -p "$WORK/keys"
  touch "$WORK/keys/implementer.pem"
  set_conf AUTOTEAM_KEYS_DIR "$WORK/keys"
  assert_eq "$(team_cli token --find-key implementer)" "$WORK/keys/implementer.pem"
  # 脚本参数原样传下去，不被当成 autoteam 的 -C / -P
  out=$(team_cli protected-paths --files README.md -P x 2>&1)
  assert_contains "$out" "unknown option: -P"
  # 成员仓库没有 CODEOWNERS：没有受保护路径，锁文件仍算
  out=$(team_cli protected-paths --files README.md) && tfail "没有 CODEOWNERS 时应退出 1"
  assert_eq "$out" ""
  assert_eq "$(team_cli protected-paths --files yarn.lock)" "yarn.lock"
}

t_team_launcher_picks_repo_cli_then_team_snapshot() {
  new_repo acme/standalone
  printf '#!/usr/bin/env bash\nAUTOTEAM_REF=abc\necho "pinned $*"\n' > autoteam
  launcher=$ROOT/skills/autoteam/bin/autoteam-launcher
  assert_eq "$(HOME="$WORK/.home" bash "$launcher" status --check)" "pinned status --check"
  # 不在仓库里：用缓存的团队快照，并把快照目录交给 CLI
  cd "$(mktemp -d "$TEST_BASE/nogit.XXXXXX")" || return
  ref=0123456789abcdef0123456789abcdef01234567
  mkdir -p "$WORK/.home/.cache/autoteam/cli/$ref/skills/autoteam/bin"
  printf '#!/usr/bin/env bash\necho "snapshot $AUTOTEAM_TEAM_DIR $*"\n' > "$WORK/.home/.cache/autoteam/cli/$ref/skills/autoteam/bin/autoteam"
  printf '%s %s\n' "$(date +%s)" "$ref" > "$WORK/.home/.cache/autoteam/team-ref-autoteam-ai_autoteam"
  out=$(env -u AUTOTEAM_TEAM_DIR HOME="$WORK/.home" XDG_CACHE_HOME= bash "$launcher" version)
  assert_eq "$out" "snapshot $WORK/.home/.cache/autoteam/cli/$ref version"
  # AUTOTEAM_TEAM_DIR 指向本机 checkout 时直接用它
  out=$(AUTOTEAM_TEAM_DIR=$ROOT HOME="$WORK/.home" bash "$launcher" version)
  assert_contains "$out" "autoteam "
}

t_team_init_and_doctor_member_files() {
  setup_team
  printf 'check:\n\t@true\n' > Makefile
  out=$(team_cli init)
  assert_contains "$out" "成员项目 acme/app"
  assert_contains "$out" "新建 .github/workflows/autoteam.yml"
  assert_contains "$out" "Makefile 已存在但缺少目标： dev deploy"
  assert_file_contains .github/workflows/autoteam.yml "uses: acme/team/.github/workflows/member.yml@main"
  assert_file_contains .github/workflows/autoteam.yml "branches: [trunk]"
  assert_no_file .autoteam
  assert_no_file autoteam
  out=$(team_cli init --team-home "$TEAM" 2>&1) && tfail "已登记的仓库不用 --team-home"
  out=$(team_cli upgrade 2>&1) && tfail "成员项目没有可升级的文件"
  assert_contains "$out" "成员项目没有安装 autoteam 的文件"
  printf 'check:\n\t@true\ndev:\n\t@true\ndeploy:\n\t@true\n' > Makefile
  mkdir -p .autoteam && touch .autoteam/autoteam.conf.old
  out=$(team_cli doctor --skip-github --skip-multica)
  assert_contains "$out" "成员项目，团队仓库 acme/team"
  assert_contains "$out" ".github/workflows/autoteam.yml 调用团队仓库的可复用工作流"
  assert_contains "$out" "Makefile 有 check / dev / deploy"
  assert_contains "$out" ".autoteam 是旧版装进来的"
  assert_contains "$out" "registry.yaml："
  assert_not_contains "$out" "缺少 ./autoteam"
}
