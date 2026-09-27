#!/usr/bin/env bash
# 在开发镜像（dev/Dockerfile）里执行命令。make check / dev / deploy / publish 都经过这里，
# 本机、cloud runtime、CI 用的是同一个镜像、同一套工具。
#
#   scripts/in-container.sh <命令...>           例：scripts/in-container.sh bash tests/run.sh multica
#   scripts/in-container.sh --npmrc <命令...>   另把宿主机的 npm 配置只读挂进去（make publish 用）
#   scripts/in-container.sh --image             只构建镜像，打印 tag
#
# - 已经在开发镜像里（AUTOTEAM_DEV_IMAGE=1）就直接执行，不嵌套；
# - 镜像 tag 是 dev/Dockerfile 内容的 hash，本机已有就复用，改了 Dockerfile 自动重建；
# - 能把仓库目录挂进容器（本机、CI）就挂载执行；docker 连的是远端 daemon、挂进去看不到文件
#   （cloud runtime）就用 docker cp 把仓库拷进去执行，再把产物 build/pkg/ 拷回来；
# - 以宿主的 uid/gid 执行，产物不会变成 root 所有；退出码原样返回。
# 没有 docker 就报错：不留"不用容器直接跑"的路，否则又回到两套环境。
set -eo pipefail

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
die() { printf 'in-container 中止：%s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*" >&2; }

npmrc_wanted="" image_only=""
case ${1:-} in
  --npmrc) npmrc_wanted=1; shift ;;
  --image) image_only=1; shift ;;
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[ $# -gt 0 ] || [ -n "$image_only" ] || die "没有要执行的命令（用法见 --help）"

if [ "${AUTOTEAM_DEV_IMAGE:-}" = 1 ]; then
  [ -z "$image_only" ] || die "已经在开发镜像里了"
  exec "$@"
fi

command -v docker >/dev/null 2>&1 ||
  die "没有 docker：make check/dev/deploy/publish 都在开发镜像里执行，先装 docker（https://docs.docker.com/get-docker/）"
docker info >/dev/null 2>&1 || die "连不上 docker daemon：先启动 docker，或检查 DOCKER_HOST"

if command -v sha256sum >/dev/null 2>&1; then
  hash=$(sha256sum < "$ROOT/dev/Dockerfile")
else
  hash=$(shasum -a 256 < "$ROOT/dev/Dockerfile")
fi
image=autoteam-dev:${hash:0:12}
if ! docker image inspect "$image" >/dev/null 2>&1; then
  info "构建开发镜像 $image（本机还没有，或 dev/Dockerfile 改过）"
  docker build -t "$image" "$ROOT/dev" >&2 || die "构建开发镜像失败"
fi
if [ -n "$image_only" ]; then
  echo "$image"
  exit 0
fi

name=autoteam-dev-$$-$RANDOM
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
# 调用方要用的环境变量显式透传；没设的 docker 不会传
opts=(--name "$name" --init --user "$(id -u):$(id -g)" -e HOME=/tmp
  -e DRY_RUN -e NPM_PROVENANCE -e STUB_SCENARIO -e NO_COLOR -e CI -e GITHUB_ACTIONS)

# 远端 daemon 上 -v 挂载的是那台机器上的同名路径，容器里看到的是空目录
if docker run --rm -v "$ROOT:/probe:ro" "$image" test -f /probe/scripts/in-container.sh >/dev/null 2>&1; then
  mode=mount
else
  mode=copy
fi

if [ -n "$npmrc_wanted" ]; then
  [ "$mode" = mount ] ||
    die "docker daemon 看不到本机的文件（远端 daemon），没法只读挂载 npm 登录信息：make publish 只能在能挂载目录的机器上执行（凭据不用 docker cp 拷进容器）"
  npmrc=${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}
  [ -f "$npmrc" ] || die "没有 npm 配置 $npmrc：先在本机 npm login"
  npmrc=$(cd "$(dirname "$npmrc")" && pwd)/$(basename "$npmrc")
  opts+=(-v "$npmrc:/run/autoteam/npmrc:ro" -e NPM_CONFIG_USERCONFIG=/run/autoteam/npmrc)
  info "npm 配置：宿主机 $npmrc 只读挂载为 /run/autoteam/npmrc"
fi

rc=0
if [ "$mode" = mount ]; then
  # 挂在同一个绝对路径上。git worktree 的 .git 是指向公共目录的文件，公共目录也挂进去，容器里的 git 才能用
  opts+=(-v "$ROOT:$ROOT" -w "$ROOT")
  if [ -f "$ROOT/.git" ]; then
    common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir) ||
      die "$ROOT 是 git worktree，但找不到它的公共 git 目录"
    opts+=(-v "$common:$common")
  fi
  info "在开发镜像 $image 里执行（挂载仓库目录）：$*"
  docker run --rm "${opts[@]}" "$image" "$@" || rc=$?
else
  info "在开发镜像 $image 里执行（docker cp：daemon 看不到本机目录，把仓库拷进容器）：$*"
  docker create "${opts[@]}" -w /w "$image" "$@" >/dev/null
  docker cp -a "$ROOT/." "$name:/w" || die "把仓库拷进容器失败"
  docker start -a "$name" || rc=$?
  # 约定的产物只有 build/pkg/（make deploy 打的包）
  back=$(mktemp -d "${TMPDIR:-/tmp}/autoteam-dev.XXXXXX")
  if docker cp "$name:/w/build/pkg" "$back/" >/dev/null 2>&1; then
    mkdir -p "$ROOT/build/pkg"
    cp -R "$back/pkg/." "$ROOT/build/pkg/"
    info "已把产物拷回 build/pkg/"
  fi
  rm -rf "$back"
fi
exit "$rc"
