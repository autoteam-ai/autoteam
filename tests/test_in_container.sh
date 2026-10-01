# shellcheck shell=bash

# 假 docker：不连 daemon，把 "容器" 文件系统映射到 $CTR；探测挂载失败，强制走 docker cp 路径
make_fake_docker() {
  mkdir -p "$WORK/fakebin"
  cat > "$WORK/fakebin/docker" <<'EOS'
#!/usr/bin/env bash
case $1 in
  info) exit 0 ;;
  image) exit 0 ;;
  run) exit 1 ;;
  create) mkdir -p "$CTR/w" ;;
  cp)
    shift; [ "$1" = -a ] && shift
    src=$1 dst=${2#*:}
    case $1 in *:*) exit 1 ;; esac
    mkdir -p "$CTR$(dirname "$dst")"
    if [ -d "$src" ]; then rm -rf "$CTR$dst"; mkdir -p "$CTR$dst"; cp -a "$src/." "$CTR$dst"; else cp -a "$src" "$CTR$dst"; fi ;;
  start) ;;
  rm) ;;
esac
EOS
  chmod +x "$WORK/fakebin/docker"
}

# worktree 的 .git 指向宿主机路径，docker cp 进容器后必须仍能被容器里的 git 解析到同一个提交
t_in_container_copy_mode_keeps_git_worktree_usable() {
  local repo wt head
  WORK=$(mktemp -d "$TEST_BASE/in-container.XXXXXX")
  repo=$WORK/repo wt=$WORK/wt
  make_fake_docker
  mkdir -p "$repo/scripts" "$repo/dev"
  cp "$ROOT/scripts/in-container.sh" "$repo/scripts/"
  echo FROM scratch > "$repo/dev/Dockerfile"
  git -C "$repo" init -q -b main
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qm init
  git -C "$repo" worktree add -q -b feature "$wt"
  echo changed >> "$wt/dev/Dockerfile.local"
  head=$(git -C "$wt" rev-parse HEAD)

  CTR=$WORK/ctr PATH=$WORK/fakebin:$PATH bash "$wt/scripts/in-container.sh" true >/dev/null 2>&1
  assert_eq "$?" 0 "in-container 应成功"
  assert_file_contains "$WORK/ctr/w/.git" "gitdir: /gitcommon/worktrees/"

  # 把容器里的 /gitcommon 还原到宿主机同名相对位置后，.git 文件要解析到同一个提交
  local gitdir
  gitdir=$(sed 's/^gitdir: //' "$WORK/ctr/w/.git")
  assert_eq "$(git --git-dir="$WORK/ctr$gitdir" rev-parse HEAD)" "$head" "容器里的 .git 应解析到 worktree 的提交"
}
