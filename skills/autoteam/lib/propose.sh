# shellcheck shell=bash
# autoteam propose：把人本地的改动用 Implementer App 身份推到新分支并开 PR。
# 规则集开了 require_last_push_approval 后，人自己推的规则文件改动没法自己批准；
# 换成 App 身份推送，人只负责批准。

propose_usage() {
  cat <<'EOF'
用法：autoteam propose [--title <PR 标题>] [--apply]

把当前工作区未提交的改动（含未跟踪文件），连同当前分支相对默认分支的提交，用 Implementer App
身份推到新分支 propose/<UTC 时间戳> 并开 PR。默认只预览（分支名、标题、改动文件）；--apply 才执行。
- 标题默认取分支上最新提交的标题（没有提交就按改动文件生成）；标题需要任务编号时用 --title 传入；
- 不动你的工作区、暂存区和分支，不改 git 配置和 remote：改动快照用临时索引生成，
  push 直接推到 https://github.com/<AUTOTEAM_REPO>.git，凭据只通过一次性的 credential.helper 传给这次 push；
- PR 由 .autoteam/scripts/open-pr.sh 在临时 worktree 里开（合并模式、自动合并都按它的约定）；
- 执行后临时 worktree 和临时本地分支会移除，远端分支保留给 PR；不替你批准或合并。
EOF
}

propose_slug_title() { # <文件数> <首个文件>
  if [ "$1" = 1 ]; then printf '更新 %s' "$2"; else printf '更新 %s 等 %s 个文件' "$2" "$1"; fi
}

propose_body() { # <改动文件清单，每行 状态<TAB>路径>
  cat <<EOF
## 任务

- 任务编号：无（人在本地改动，用 \`autoteam propose\` 以 Implementer App 身份提交）
- 验收标准：由 Code Owner 审阅改动后批准

## 检查

CI 检查见本 PR；本地是否跑过 \`make check\` 由提交人自行确认。

改动文件：

$(while IFS=$'\t' read -r st path; do printf -- "- \`%s\` %s\n" "$path" "$st"; done <<<"$1")

## 范围外发现

无
EOF
}

cmd_propose() {
  local title="" apply=0 root base baseref mb head tree commit="" files n first ahead dirty src branch remote
  local tok openpr idx tmp wt body ident name email rc=0 out
  while [ $# -gt 0 ]; do
    case $1 in
      --apply) apply=1; shift ;;
      --title) [ $# -ge 2 ] && [ -n "$2" ] || die '--title 需要标题'; title=$2; shift 2 ;;
      -h|--help) propose_usage; return ;;
      *) propose_usage >&2; die "未知参数：$1" ;;
    esac
  done
  need_cmd git; need_cmd gh; need_cmd jq
  root=$(repo_root)
  conf_load "$root"
  [ -n "$AUTOTEAM_REPO" ] || die "$AUTOTEAM_CONF_REL 里没有 AUTOTEAM_REPO"
  base=$AUTOTEAM_DEFAULT_BRANCH
  tok=$root/$AUTOTEAM_DIR/scripts/gh-app-token.sh
  openpr=$root/$AUTOTEAM_DIR/scripts/open-pr.sh
  [ -f "$tok" ] && [ -f "$openpr" ] || die "缺少 $AUTOTEAM_DIR/scripts/gh-app-token.sh 或 open-pr.sh：先 autoteam init / upgrade"
  remote=${AUTOTEAM_PROPOSE_REMOTE:-https://github.com/$AUTOTEAM_REPO.git}
  if [ -z "${AUTOTEAM_PROPOSE_REMOTE:-}" ] && [ "$(git ls-remote --get-url "$remote")" != "$remote" ]; then
    die "git 配置（url.*.insteadOf）改写了 $remote，push 会绕过 App 身份；先去掉这条改写"
  fi

  baseref=refs/remotes/origin/$base
  git rev-parse --verify -q "$baseref" >/dev/null || baseref=refs/heads/$base
  git rev-parse --verify -q "$baseref" >/dev/null || die "找不到默认分支 $base（先 git fetch origin）"
  head=$(git rev-parse --verify -q HEAD) || die "当前分支还没有提交"
  mb=$(git merge-base "$baseref" "$head") || die "当前分支和 $base 没有共同祖先"

  # 快照：临时索引 = HEAD + 工作区全部改动（含未跟踪、遵守 .gitignore），不碰真实索引
  idx=$(autoteam_tmpdir)/propose-index
  dirty=$(git -C "$root" status --porcelain) || die "读取工作区状态失败"
  if [ -n "$dirty" ]; then
    GIT_INDEX_FILE=$idx git -C "$root" read-tree "$head" || die "读取 HEAD 失败"
    GIT_INDEX_FILE=$idx git -C "$root" add -A || die "生成改动快照失败"
    tree=$(GIT_INDEX_FILE=$idx git -C "$root" write-tree) || die "生成改动快照失败"
  else
    tree=$(git rev-parse "$head^{tree}")
  fi
  files=$(git diff-tree -r --no-renames --name-status "$mb" "$tree") || die "计算改动文件失败"
  [ -n "$files" ] || die "没有可提议的改动：工作区干净，当前分支相对 $base 也没有新内容"
  n=$(grep -c . <<<"$files")
  first=$(head -n 1 <<<"$files" | cut -f2)
  ahead=$(git rev-list --count "$mb..$head")
  src=
  [ "$ahead" = 0 ] || src="分支上 $ahead 个提交"
  [ -z "$dirty" ] || src="${src:+$src + }未提交的改动"
  if [ -z "$title" ]; then
    if [ -z "$dirty" ]; then title=$(git log -1 --format=%s "$head"); else title=$(propose_slug_title "$n" "$first"); fi
  fi
  branch=propose/$(date -u +%Y%m%d-%H%M%S)

  section "propose：$AUTOTEAM_REPO ← $branch"
  info "改动来源：$src"
  info "PR 标题：$title"
  info "目标分支：$base"
  info "改动文件（$n）："
  while IFS=$'\t' read -r st path; do info "  $st $path"; done <<<"$files"
  if [ "$apply" != 1 ]; then
    hint "标题需要任务编号时用 --title 传入；预览完成，加 --apply 执行"
    return
  fi

  # 身份：提交作者和 push、开 PR 都是 Implementer App，人的全局 git 身份不动
  ident=$(bash "$tok" --identity implementer) || die "取不到 Implementer App 身份，见上面的报错"
  IFS=$'\t' read -r name email <<<"$ident"
  if [ -n "$dirty" ]; then
    commit=$(GIT_AUTHOR_NAME=$name GIT_AUTHOR_EMAIL=$email GIT_COMMITTER_NAME=$name GIT_COMMITTER_EMAIL=$email \
      git commit-tree "$tree" -p "$head" -m "$title") || die "生成提交失败"
  else
    commit=$head
  fi

  # 清空继承来的凭据助手（系统钥匙串里是人的凭据），再换成一次性的 App 助手；token 不落盘、不打印
  GIT_TERMINAL_PROMPT=0 git -C "$root" -c credential.helper= -c "credential.helper=!'$tok' --credential implementer" \
    push --quiet "$remote" "$commit:refs/heads/$branch" || die "push 失败，见上面的报错（没有创建 PR）"
  info "已推送 $branch"

  tmp=$(autoteam_tmpdir)
  wt=$tmp/propose-wt
  body=$tmp/propose-body.md
  propose_body "$files" > "$body"
  git -C "$root" worktree add -q -b "$branch" "$wt" "$commit" || die "创建临时 worktree 失败（分支 $branch 已在远端）"
  # 令牌脚本要在原仓库里跑（私钥可能在这里的 .autoteam/local/）；open-pr.sh 用当前目录的分支，所以在 worktree 里执行
  out=$(cd "$root" && bash "$tok" --run implementer \
    bash -c 'cd "$1" && shift && exec bash "$@"' _ "$wt" "$openpr" --title "$title" --body-file "$body" 2>&1) || rc=$?
  printf '%s\n' "$out"
  git -C "$root" worktree remove --force "$wt" || warn "清理临时 worktree 失败，可手动 git worktree prune"
  git -C "$root" branch -q -D "$branch" || warn "清理临时本地分支 $branch 失败，可手动删除"
  if [ "$rc" != 0 ]; then
    printf 'autoteam propose：分支 %s 已推到远端，但 open-pr.sh 失败（上面是原因）。处理后可在该分支上重跑 .autoteam/scripts/open-pr.sh。\n' "$branch" >&2
    return 1
  fi
  info "PR 由 Implementer App 开出，等你（Code Owner）批准；本命令不批准也不合并"
}
