# shellcheck shell=bash
# 团队仓库与成员项目（design/0003）。团队仓库的 .autoteam/ 是整个团队的默认配置：autoteam.conf、
# registry.yaml、playbook.md、eject 的指令，以及 projects/<owner>/<repo>/ 下各成员项目的
# project.conf 和 playbook.md。成员仓库里不装 autoteam 的文件，agent 用 PATH 上的启动器
# （bin/autoteam-launcher）跑团队仓库最新提交的 CLI，配置也从那份快照里读。

AUTOTEAM_PROJECTS_REL=$AUTOTEAM_DIR/projects

# 成员项目不从团队配置继承的键：团队的 autoteam.conf 里这些键写的是团队仓库自己
autoteam_project_keys() {
  printf '%s\n' AUTOTEAM_REPO AUTOTEAM_DEFAULT_BRANCH AUTOTEAM_MULTICA_PROJECT AUTOTEAM_CHECK_NAME \
    AUTOTEAM_PR_SIZE_EXCLUDE AUTOTEAM_DEPLOY_ENVIRONMENT AUTOTEAM_AUTOPILOTS AUTOTEAM_TEAM_HOME
}

# 团队仓库目录：AUTOTEAM_TEAM_DIR 优先；否则 CLI 所在的源码树本身（启动器下载的快照、
# autoteam 仓库的 checkout）。不是团队仓库（没有 .autoteam/autoteam.conf）返回 1
team_dir() {
  local d=${AUTOTEAM_TEAM_DIR:-$AUTOTEAM_HOME/../..}
  [ -f "$d/$AUTOTEAM_CONF_REL" ] || return 1
  (cd "$d" && pwd)
}

# 判定工作模式，结果放进全局变量（必须在主 shell 里调用，autoteam_main 解析完参数后调）：
#   local   仓库根有 .autoteam/autoteam.conf：独立项目或团队仓库自己，行为和以前一样
#   member  团队仓库 projects/ 下登记过的成员项目；用 -P / AUTOTEAM_PROJECT 指定时不需要在它的 clone 里
team_context() {
  local root slug td
  AUTOTEAM_MODE=local AUTOTEAM_TEAM_ROOT="" AUTOTEAM_PROJECT_DIR=""
  if [ -n "${AUTOTEAM_PROJECT:-}" ]; then
    slug=$AUTOTEAM_PROJECT
    td=$(team_dir) || die "找不到团队仓库：用团队仓库里的 autoteam，或设置 AUTOTEAM_TEAM_DIR"
    if [ "$slug" = "$(conf_file_get "$td/$AUTOTEAM_CONF_REL" AUTOTEAM_REPO)" ]; then
      cd "$td" || die "进不去团队仓库 $td"
      unset AUTOTEAM_PROJECT
      return 0
    fi
  else
    root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    [ ! -f "$root/$AUTOTEAM_CONF_REL" ] || return 0
    slug=$(detect_repo_from_remote) || return 0
    td=$(team_dir) || return 0
  fi
  if [ -f "$td/$AUTOTEAM_PROJECTS_REL/$slug/project.conf" ]; then
    AUTOTEAM_MODE=member AUTOTEAM_TEAM_ROOT=$td AUTOTEAM_PROJECT=$slug
    AUTOTEAM_PROJECT_DIR=$td/$AUTOTEAM_PROJECTS_REL/$slug
  elif [ -n "${AUTOTEAM_PROJECT:-}" ]; then
    die "$slug 没有在团队仓库登记：在团队仓库运行 autoteam project add $slug"
  fi
}

# 成员项目的配置：环境变量 > project.conf > 团队 autoteam.conf > 默认值；项目自己的键不继承团队的值
conf_load_member() {
  local td=$AUTOTEAM_TEAM_ROOT keys
  # shellcheck disable=SC2034  # multica、doctor、upgrade 在 source 后使用
  AUTOTEAM_AUTOPILOTS_CONFIGURED=1
  conf_load_file "$AUTOTEAM_PROJECT_DIR/project.conf"
  [ -n "${AUTOTEAM_REPO+x}" ] || AUTOTEAM_REPO=$AUTOTEAM_PROJECT
  [ -n "${AUTOTEAM_MULTICA_PROJECT+x}" ] || AUTOTEAM_MULTICA_PROJECT=${AUTOTEAM_PROJECT##*/}
  [ -n "${AUTOTEAM_CHECK_NAME+x}" ] || AUTOTEAM_CHECK_NAME='autoteam / check'
  [ -n "${AUTOTEAM_AUTOPILOTS+x}" ] || AUTOTEAM_AUTOPILOTS=
  [ -n "${AUTOTEAM_TEAM_HOME+x}" ] || AUTOTEAM_TEAM_HOME=$(conf_file_get "$td/$AUTOTEAM_CONF_REL" AUTOTEAM_REPO)
  keys=$(autoteam_project_keys | tr '\n' ' ')
  conf_fill_defaults_for "$keys"
  conf_load_file "$td/$AUTOTEAM_CONF_REL"
  conf_fill_defaults
}

# .autoteam/ 配置所在的目录：成员项目是团队仓库，其余是当前仓库
autoteam_conf_root() {
  if [ "${AUTOTEAM_MODE:-local}" = member ]; then
    printf '%s\n' "$AUTOTEAM_TEAM_ROOT"
  else
    repo_root
  fi
}

team_require_conf() {
  conf_exists || die "这里不是 autoteam 项目：没有 $AUTOTEAM_CONF_REL，也没有在团队仓库登记（autoteam project add）"
  conf_load
}

conf_usage() {
  cat <<'EOF'
用法：autoteam [-P <owner/name>] conf [KEY...]

打印当前项目生效的配置（成员项目 = 团队配置 + 本项目 project.conf）。给出键名时每行只打印值。
EOF
}

cmd_conf() {
  local key re='^AUTOTEAM_[A-Z0-9_]+$'
  case ${1:-} in -h|--help) conf_usage; return 0 ;; esac
  team_require_conf
  if [ $# -eq 0 ]; then
    if [ "$AUTOTEAM_MODE" = member ]; then
      printf '# 成员项目 %s，团队仓库 %s\n' "$AUTOTEAM_REPO" "$AUTOTEAM_TEAM_HOME"
    fi
    conf_write_effective /dev/stdout
    return 0
  fi
  for key in "$@"; do
    [[ $key =~ $re ]] || die "配置键写成 AUTOTEAM_ 开头的大写名字：$key"
    printf '%s\n' "${!key-}"
  done
}

# 团队目录：成员项目取团队仓库；在团队仓库或独立项目里取当前仓库；不在任何仓库里时取
# CLI 所在的团队仓库快照（启动器给的），这样 Planner 在 Chat 里不用先 checkout 也能列项目
projects_root() {
  local root
  if [ "${AUTOTEAM_MODE:-local}" = member ]; then
    printf '%s\n' "$AUTOTEAM_TEAM_ROOT"
  elif root=$(git rev-parse --show-toplevel 2>/dev/null); then
    conf_exists "$root" || die "这里不是 autoteam 项目"
    printf '%s\n' "$root"
  else
    team_dir || die "不在 autoteam 项目里，也找不到团队仓库：设置 AUTOTEAM_TEAM_DIR"
  fi
}

# 团队管理的全部项目，每行 owner/name<TAB>Multica 项目名，团队仓库自己排第一
projects_list() {
  local td=$1 f slug title
  slug=$(conf_file_get "$td/$AUTOTEAM_CONF_REL" AUTOTEAM_REPO)
  title=$(conf_file_get "$td/$AUTOTEAM_CONF_REL" AUTOTEAM_MULTICA_PROJECT)
  printf '%s\t%s\n' "$slug" "${title:-${slug##*/}}"
  for f in "$td/$AUTOTEAM_PROJECTS_REL"/*/*/project.conf; do
    [ -f "$f" ] || continue
    slug=${f#"$td/$AUTOTEAM_PROJECTS_REL/"}
    slug=${slug%/project.conf}
    title=$(conf_file_get "$f" AUTOTEAM_MULTICA_PROJECT)
    printf '%s\t%s\n' "$slug" "${title:-${slug##*/}}"
  done
}

cmd_projects() {
  local output=text rows
  while [ $# -gt 0 ]; do
    case $1 in
      --json) output=json; shift ;;
      -h|--help) echo "用法：autoteam projects [--json]   列出团队管理的项目：仓库和 Multica 项目名"; return 0 ;;
      *) die "未知选项：$1" ;;
    esac
  done
  rows=$(projects_list "$(projects_root)")
  if [ "$output" = json ]; then
    need_cmd jq
    jq -Rn '[inputs | split("\t") | {repo: .[0], project: .[1]}] | .[0].team = true' <<<"$rows"
  else
    printf '%s\n' "$rows"
  fi
}

project_usage() {
  cat <<'EOF'
用法：autoteam project add <owner/name> [--default-branch <分支>]

在团队仓库登记一个成员项目：新建 .autoteam/projects/<owner>/<name>/ 下的 project.conf 和
playbook.md（已存在就不动）。成员仓库里不装 autoteam 的文件，只需要 Makefile 的
check / dev / deploy 和 .github/workflows/autoteam.yml（在成员仓库 clone 里跑 autoteam init 生成）。
EOF
}

cmd_project() {
  local sub=${1:-} slug="" branch="" root dir
  [ $# -eq 0 ] || shift
  case $sub in
    add) ;;
    -h|--help|'') project_usage; return 0 ;;
    *) project_usage >&2; die "未知子命令：$sub" ;;
  esac
  while [ $# -gt 0 ]; do
    case $1 in
      --default-branch) [ $# -ge 2 ] || die "--default-branch 需要分支名"; branch=$2; shift 2 ;;
      -*) die "未知选项：$1" ;;
      *) [ -z "$slug" ] || die "一次只登记一个仓库"; slug=$1; shift ;;
    esac
  done
  [[ $slug =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "仓库写成 owner/name：${slug:-（空）}"
  [ "${AUTOTEAM_MODE:-local}" = local ] || die "在团队仓库里运行（团队仓库是 $AUTOTEAM_TEAM_HOME）"
  root=$(repo_root)
  conf_exists "$root" || die "这里不是团队仓库：没有 $AUTOTEAM_CONF_REL"
  conf_load "$root"
  [ -z "$AUTOTEAM_TEAM_HOME" ] || die "本仓库是成员仓库，到团队仓库 $AUTOTEAM_TEAM_HOME 登记"
  [ "$slug" != "$AUTOTEAM_REPO" ] || die "$slug 就是团队仓库，不用登记"
  dir=$AUTOTEAM_PROJECTS_REL/$slug
  if [ -f "$root/$dir/project.conf" ]; then
    ok "$slug 已登记（$dir/project.conf）"
    return 0
  fi
  if [ -z "$branch" ] && command -v gh >/dev/null 2>&1; then
    branch=$(gh api "repos/$slug" --jq .default_branch 2>/dev/null) || branch=""
  fi
  mkdir -p "$root/$dir"
  cat > "$root/$dir/project.conf" <<EOF
# 成员项目 $slug 的配置，格式同 autoteam.conf。没写的键用团队配置 $AUTOTEAM_CONF_REL。
# 下面这些键描述项目自己，不继承团队仓库的值，没写时用 autoteam 默认值：
#   AUTOTEAM_DEFAULT_BRANCH、AUTOTEAM_MULTICA_PROJECT（默认仓库名）、
#   AUTOTEAM_CHECK_NAME（默认 autoteam / check，即 .github/workflows/autoteam.yml 的检查）、
#   AUTOTEAM_PR_SIZE_EXCLUDE、AUTOTEAM_AUTOPILOTS（默认空：autopilot 是团队级的）。部署 environment 固定为 production
AUTOTEAM_DEFAULT_BRANCH=${branch:-main}
EOF
  cat > "$root/$dir/playbook.md" <<EOF
# $slug 的经验

Planner 用 \`autoteam playbook\` 读到团队的 playbook 和这一份。这里只记本项目特有的经验
（拆任务、验收口径、踩过的坑）；跨项目通用的写进团队的 $AUTOTEAM_DIR/playbook.md。
EOF
  ok "已登记 $slug：$dir/project.conf、$dir/playbook.md"
  info "下一步："
  info "1. 提交这两个文件（PR 合并后团队里的 agent 就认识这个项目）"
  info "2. 在 $slug 的 clone 里跑 autoteam init：生成 .github/workflows/autoteam.yml 和 Makefile 的 check / dev / deploy"
  info "3. autoteam -P $slug github --apply；团队仓库里 autoteam multica --apply（建 Multica 项目、写部署 webhook secret）"
}

cmd_playbook() {
  local root
  case ${1:-} in -h|--help) echo "用法：autoteam playbook   打印本项目的经验库（成员项目先打印团队的，再打印本项目的）"; return 0 ;; esac
  team_require_conf
  root=$(autoteam_conf_root)
  [ ! -f "$root/$AUTOTEAM_DIR/playbook.md" ] || cat "$root/$AUTOTEAM_DIR/playbook.md"
  if [ "$AUTOTEAM_MODE" = member ] && [ -f "$AUTOTEAM_PROJECT_DIR/playbook.md" ]; then
    printf '\n'
    cat "$AUTOTEAM_PROJECT_DIR/playbook.md"
  fi
}

# 运行时脚本的子命令：agent 在任何项目里都用 autoteam <名字>，不依赖仓库里装没装脚本。
# 独立项目和团队仓库优先用仓库里安装的那份（可能改过），成员项目用包内的。
script_file() {
  local name root
  case $1 in
    token) name=gh-app-token ;;
    metrics) name=health-metrics ;;
    instruction-budget) name=check-instruction-budget ;;
    open-pr|merge-mode|merge-status|loop-guard|protected-paths|deployed-issues) name=$1 ;;
    *) return 1 ;;
  esac
  if [ "${AUTOTEAM_MODE:-local}" = local ] && root=$(git rev-parse --show-toplevel 2>/dev/null) &&
    [ -f "$root/$AUTOTEAM_DIR/scripts/$name.sh" ]; then
    printf '%s\n' "$root/$AUTOTEAM_DIR/scripts/$name.sh"
  else
    printf '%s\n' "$AUTOTEAM_TEMPLATES/autoteam/scripts/$name.sh"
  fi
}

# 跑一个运行时脚本，配置已经 conf_load 过：脚本读 AUTOTEAM_CONF_FILE 指向的有效配置
autoteam_script() {
  local name=$1 file conf
  shift
  file=$(script_file "$name") || die "未知命令：$name"
  conf=$(autoteam_tmpdir)/effective.conf
  [ -f "$conf" ] || conf_write_effective "$conf"
  AUTOTEAM_CONF_FILE=$conf bash "$file" "$@"
}

# 不在 autoteam 项目里时不带配置直接跑，由脚本自己报缺什么
cmd_script() {
  local name=$1 rc=0
  shift
  script_file "$name" >/dev/null || die "未知命令：$name"
  if git rev-parse --show-toplevel >/dev/null 2>&1 && conf_exists; then
    conf_load
    autoteam_script "$name" "$@" || rc=$?
  else
    bash "$(script_file "$name")" "$@" || rc=$?
  fi
  return "$rc"
}
