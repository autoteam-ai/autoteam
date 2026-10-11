# shellcheck shell=bash
# 团队仓库与成员项目（design/0003）：配置分层、-P、运行时脚本

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
  mkdir -p .autoteam/projects/acme/app
  printf 'AUTOTEAM_DEFAULT_BRANCH=trunk\nAUTOTEAM_PR_MAX_LINES=500\n' > .autoteam/projects/acme/app/project.conf
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

t_team_member_eject_goes_to_team() {
  setup_team
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
