#!/usr/bin/env bash
# 把 autoteam 发布到 npm，由 `make deploy` 调用（本仓库的 deploy 就是发包）。
#
#   make deploy              真的发布；版本已经发过就跳过，CI 重跑不会失败
#   make deploy DRY_RUN=1    只做检查和打包，不需要 npm 凭据
#
# 发布前会挡住三件事：三处版本号不一致、CHANGELOG 没定版、打出来的包跑不起来。
set -eo pipefail

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

die() { printf '发布中止：%s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

for release_cmd in npm jq tar; do
  command -v "$release_cmd" >/dev/null 2>&1 || die "没有 $release_cmd"
done

name=$(jq -r '.name // empty' package.json)
version=$(jq -r '.version // empty' package.json)
[ -n "$name" ] || die "package.json 里没有 name"
[ -n "$version" ] || die "package.json 里没有 version"

# 版本号有三份（package.json、CLI、CHANGELOG），发布前必须对得上
cli_version=$(sed -n 's/^AUTOTEAM_VERSION="\(.*\)"/\1/p' skills/autoteam/scripts/lib/common.sh)
[ "$cli_version" = "$version" ] ||
  die "版本不一致：package.json 是 $version，common.sh 是 ${cli_version:-空}"
grep -q "^## $version" CHANGELOG.md ||
  die "CHANGELOG.md 里没有 \"## $version\" 段落：发布前先把「未发布」那段定版"

dirty=$(git status --porcelain 2>/dev/null) || dirty=""
if [ -n "$dirty" ] && [ -z "${DRY_RUN:-}" ]; then
  die "工作区有未提交的改动，不要从这种状态发布（本地验证用 make deploy DRY_RUN=1）"
fi

# 打一个真包出来跑一遍：files 漏了实现的话，装完的 autoteam 是个空壳
tmp=$(mktemp -d "${TMPDIR:-/tmp}/autoteam-release.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

tarball=$(npm pack --silent --pack-destination "$tmp" "$ROOT") || die "npm pack 失败"
tar -xzf "$tmp/$tarball" -C "$tmp" || die "解包失败：$tarball"
for f in bin/autoteam skills/autoteam/SKILL.md skills/autoteam/scripts/autoteam \
  skills/autoteam/scripts/lib/common.sh skills/autoteam/assets/templates/Makefile; do
  [ -f "$tmp/package/$f" ] || die "包里少了 $f（看 package.json 的 files）"
done
packed=$(bash "$tmp/package/bin/autoteam" version) || die "包里的 autoteam 跑不起来"
[ "$packed" = "autoteam $version" ] || die "包里的 autoteam 报的版本是「$packed」"
info "打包检查通过：$tarball"

published=$(npm view "$name@$version" version 2>/dev/null) || published=""
if [ -n "$published" ]; then
  info "跳过：$name@$version 已经在 npm 上了"
  exit 0
fi

publish_args=()
if [ -n "${NPM_PROVENANCE:-}" ]; then publish_args+=(--provenance); fi
if [ -n "${DRY_RUN:-}" ]; then
  publish_args+=(--dry-run)
  info "DRY_RUN=1：只演练 npm publish，不会真的发出去"
else
  npm whoami >/dev/null 2>&1 ||
    die "npm 没有登录：本地用 npm login，CI 里设置 NODE_AUTH_TOKEN（secrets.NPM_TOKEN）"
fi

npm publish ${publish_args[@]+"${publish_args[@]}"}
info "完成：$name@$version"
