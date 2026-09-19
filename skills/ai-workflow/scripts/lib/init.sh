# shellcheck shell=bash
# aiwf init / aiwf diff：把模板装进目标仓库。
# AIWF_* 变量通过 render_string 的间接展开写进模板，shellcheck 看不出来：
# shellcheck disable=SC2034

init_usage() {
  cat <<'EOF'
用法：aiwf init [选项] [文件...]

在当前 git 仓库生成工作流文件。已有文件不覆盖；AGENTS.md、CODEOWNERS、.gitignore 用受管块追加一次。
指定文件时只处理这些文件，升级时用来只覆盖没改过的文件：aiwf init --force ops/agents/reviewer.md

选项：
  --repo <owner/name>     GitHub 仓库（默认从 git remote 识别）
  --owner <GitHub 用户名>  规则文件的人类负责人（默认当前 gh 登录用户）
  --issue-prefix <前缀>    Multica 任务编号前缀，如 MUL（默认从 --workspace 读取，否则 MUL）
  --workspace <slug>       Multica 工作区
  --human <成员名>         在 Multica 里负责批准和接收升级的成员
  --timezone <时区>        autopilot 时区（默认 Asia/Shanghai）
  --force                  覆盖与模板不同的文件（aiwf.conf、registry.yaml 除外）
  --dry-run                只列出会做什么
EOF
}

cmd_init() {
  AIWF_FORCE=0 AIWF_DRY_RUN=0
  local only=" "
  while [ $# -gt 0 ]; do
    case $1 in
      --repo) AIWF_REPO=$2; shift 2 ;;
      --owner) AIWF_OWNER=${2#@}; shift 2 ;;
      --issue-prefix) AIWF_ISSUE_PREFIX=$2; shift 2 ;;
      --workspace) AIWF_MULTICA_WORKSPACE=$2; shift 2 ;;
      --human) AIWF_HUMAN=$2; shift 2 ;;
      --timezone) AIWF_TIMEZONE=$2; shift 2 ;;
      --force) AIWF_FORCE=1; shift ;;
      --dry-run) AIWF_DRY_RUN=1; shift ;;
      -h|--help) init_usage; return 0 ;;
      -*) init_usage >&2; die "未知选项：$1" ;;
      *) only="$only${1#./} "; shift ;;
    esac
  done

  local root
  root=$(repo_root)
  cd "$root" || die "进不去 $root"

  section "识别项目"
  init_detect "$root"
  info "仓库          $AIWF_REPO（默认分支 $AIWF_DEFAULT_BRANCH）"
  info "规则文件负责人 @$AIWF_OWNER"
  info "任务编号前缀   $AIWF_ISSUE_PREFIX"
  if [ -n "$AIWF_DEPLOY_ENVIRONMENT" ]; then
    info "部署 environment $AIWF_DEPLOY_ENVIRONMENT"
  else
    warn "私有仓库在 GitHub Free 下没有 environment，deploy.yml 不声明 environment"
  fi

  section "生成文件"
  local tpl target mode
  while read -r tpl target mode; do
    [ -n "$tpl" ] || continue
    [ "$only" = " " ] || case $only in *" $target "*) ;; *) continue ;; esac
    init_install "$tpl" "$target" "$mode"
  done <<EOF
$(aiwf_manifest)
gitignore.block                       .gitignore                              block
EOF

  if [ "$AIWF_DRY_RUN" = 1 ]; then
    printf '\n%s以上是预览，没有写任何文件。%s\n' "$C_BLUE" "$C_RESET"
    return 0
  fi
  [ "$only" = " " ] || return 0

  section "下一步"
  info "1. 把 Makefile 的 check / dev / deploy 改成真实命令，gate.yml 和 deploy.yml 里补上需要的运行时"
  info "2. 按你的订阅账号和机器填 ops/agents/registry.yaml（aiwf runtimes 列出可用的 runtime）"
  info "3. 提交这些文件，走 PR 由你合并"
  info "4. aiwf github    预览 GitHub 改动，确认后加 --apply"
  info "5. aiwf multica   预览 Multica 改动，确认后加 --apply"
  info "6. aiwf doctor    逐项检查"
}

# 识别仓库信息：命令行参数 > 已有 aiwf.conf > 自动识别 > 默认值
init_detect() {
  local root=$1 have_gh=0 visibility probe
  conf_load_file "$root/$AIWF_CONF_REL"
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && have_gh=1

  if [ -z "$AIWF_REPO" ]; then
    AIWF_REPO=$(detect_repo_from_remote) || true
  fi
  if [ -z "$AIWF_REPO" ] && [ "$have_gh" = 1 ]; then
    AIWF_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
  fi
  [ -n "$AIWF_REPO" ] || die "识别不出 GitHub 仓库，用 --repo owner/name 指定"

  if [ -z "$AIWF_DEFAULT_BRANCH" ] && [ "$have_gh" = 1 ]; then
    AIWF_DEFAULT_BRANCH=$(gh repo view "$AIWF_REPO" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)
  fi
  if [ -z "$AIWF_DEFAULT_BRANCH" ]; then
    AIWF_DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  fi
  if [ -z "$AIWF_DEFAULT_BRANCH" ]; then
    AIWF_DEFAULT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo main)
  fi

  if [ -z "$AIWF_OWNER" ] && [ "$have_gh" = 1 ]; then
    AIWF_OWNER=$(gh api user --jq .login 2>/dev/null || true)
  fi
  [ -n "$AIWF_OWNER" ] || AIWF_OWNER=${AIWF_REPO%%/*}

  # GitHub Free 的私有仓库没有 environment；用规则集接口探测套餐（这类仓库会返回“Upgrade to GitHub Pro”）
  if [ -z "${AIWF_DEPLOY_ENVIRONMENT+x}" ] && [ "$have_gh" = 1 ]; then
    visibility=$(gh api "repos/$AIWF_REPO" --jq .visibility 2>/dev/null || true)
    if [ "$visibility" = private ]; then
      probe=$(gh api "repos/$AIWF_REPO/rulesets" 2>&1 || true)
      case $probe in
        *"Upgrade to GitHub Pro"*) AIWF_DEPLOY_ENVIRONMENT="" ;;
      esac
    fi
  fi

  if [ -z "$AIWF_ISSUE_PREFIX" ] && [ -n "$AIWF_MULTICA_WORKSPACE" ]; then
    AIWF_ISSUE_PREFIX=$(mc_workspace_prefix "$AIWF_MULTICA_WORKSPACE" 2>/dev/null) || true
  fi
  [ -n "$AIWF_MULTICA_PROJECT" ] || AIWF_MULTICA_PROJECT=${AIWF_REPO##*/}

  conf_load "$root"
  init_derived_vars
}

# 只在渲染时用的派生变量
init_derived_vars() {
  AIWF_REPO_NAME=${AIWF_REPO##*/}
  if [ -n "$AIWF_DEPLOY_ENVIRONMENT" ]; then
    AIWF_DEPLOY_ENVIRONMENT_LINE="environment: $AIWF_DEPLOY_ENVIRONMENT"
  else
    AIWF_DEPLOY_ENVIRONMENT_LINE="# 未声明 environment：GitHub Free 的私有仓库不支持（见 ops/agents/aiwf.conf 的 AIWF_DEPLOY_ENVIRONMENT）"
  fi
}

init_write() {
  local target=$1 content=$2 mode=$3
  if [ "$AIWF_DRY_RUN" = 1 ]; then return 0; fi
  mkdir -p "$(dirname "$target")"
  printf '%s' "$content" > "$target"
  if [ "$mode" = exec ]; then chmod +x "$target"; fi
}

init_install() {
  local tpl=$AIWF_TEMPLATES/$1 target=$2 mode=$3 content current start missing t
  [ -f "$tpl" ] || die "模板缺失：$tpl"
  content=$(render_file "$tpl"; printf x)
  content=${content%x}

  case $mode in
    file|exec|config)
      if [ ! -e "$target" ]; then
        init_write "$target" "$content" "$mode"
        ok "新建 $target"
        return 0
      fi
      current=$(cat "$target"; printf x)
      current=${current%x}
      if [ "$current" = "$content" ]; then
        info "已是最新 $target"
        if [ "$mode" = exec ] && [ "$AIWF_DRY_RUN" != 1 ]; then chmod +x "$target"; fi
      elif [ "$mode" != config ] && [ "$AIWF_FORCE" = 1 ]; then
        init_write "$target" "$content" "$mode"
        ok "覆盖 $target"
      elif [ "$mode" = config ]; then
        info "保留已有配置 $target"
      else
        warn "已存在且与模板不同，跳过 $target（aiwf diff 看差异，--force 覆盖）"
      fi
      ;;
    block)
      start=$(block_markers "$target" | sed -n 1p)
      if [ ! -e "$target" ]; then
        init_write "$target" "$content" file
        ok "新建 $target"
      elif grep -qxF "$start" "$target"; then
        current=$(block_extract "$target")
        if [ "$current" = "${content%$'\n'}" ]; then
          info "已是最新 $target（受管块）"
        elif [ "$AIWF_FORCE" = 1 ]; then
          [ "$AIWF_DRY_RUN" = 1 ] || block_replace "$target" "$content"
          ok "更新 $target 的受管块"
        else
          warn "$target 的受管块与模板不同，跳过（aiwf diff 看差异，--force 替换）"
        fi
      else
        if [ "$AIWF_DRY_RUN" != 1 ]; then
          if [ -s "$target" ] && [ -n "$(tail -c 1 "$target")" ]; then printf '\n' >> "$target"; fi
          printf '\n%s' "$content" >> "$target"
        fi
        ok "追加受管块到 $target"
      fi
      ;;
    makefile)
      if [ ! -e "$target" ]; then
        init_write "$target" "$content" file
        ok "新建 $target（check / dev / deploy 还是 AIWF-TODO 桩，必须改成真实命令）"
        return 0
      fi
      missing=""
      for t in check dev deploy; do
        grep -Eq "^${t}[[:space:]]*:" "$target" || missing="$missing $t"
      done
      if [ -n "$missing" ]; then
        warn "Makefile 已存在但缺少目标：$missing（参考模板：aiwf diff Makefile）"
      else
        info "Makefile 已有 check / dev / deploy"
      fi
      ;;
  esac
}

diff_usage() {
  cat <<'EOF'
用法：aiwf diff [文件...]

对比已安装的文件和当前模板渲染结果（受管块只比较块内内容）。不指定文件时对比全部。
EOF
}

cmd_diff() {
  local only=" " a
  for a in "$@"; do
    case $a in
      -h|--help) diff_usage; return 0 ;;
      *) only="$only$a " ;;
    esac
  done
  local root tmp tpl target mode content changed=0
  root=$(repo_root)
  cd "$root" || die "进不去 $root"
  conf_exists "$root" || die "还没有 $AIWF_CONF_REL，先运行 aiwf init"
  conf_load "$root"
  init_derived_vars
  tmp=$(aiwf_tmpdir)
  while read -r tpl target mode; do
    [ -n "$tpl" ] || continue
    [ "$only" = " " ] || case $only in *" $target "*) ;; *) continue ;; esac
    content=$(render_file "$AIWF_TEMPLATES/$tpl"; printf x)
    content=${content%x}
    if [ ! -e "$target" ]; then
      printf '%s缺失%s %s\n' "$C_YELLOW" "$C_RESET" "$target"; changed=1; continue
    fi
    case $mode in
      block)
        printf '%s' "${content%$'\n'}" > "$tmp/want"
        block_extract "$target" > "$tmp/have" || true
        printf '%s' "$(cat "$tmp/have")" > "$tmp/have2"
        if ! diff -u --label "$target（受管块）" --label "模板" "$tmp/have2" "$tmp/want"; then changed=1; fi
        ;;
      makefile)
        [ "$only" = " " ] || { printf '%s' "$content" > "$tmp/want"; diff -u --label "$target" --label "模板" "$target" "$tmp/want" || true; }
        ;;
      *)
        printf '%s' "$content" > "$tmp/want"
        if ! diff -u --label "$target" --label "模板" "$target" "$tmp/want"; then changed=1; fi
        ;;
    esac
  done <<EOF
$(aiwf_manifest)
gitignore.block                       .gitignore                              block
EOF
  [ "$changed" = 0 ] && info "与模板一致"
  return 0
}
