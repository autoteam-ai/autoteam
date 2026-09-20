#!/usr/bin/env bash
# 打包和发布。本仓库的"上线"是打出一个能装能跑的包，发版是另一回事。
#
#   scripts/release.sh            打包 + 冒烟（make deploy 调它，CI 每次合并都跑）
#   scripts/release.sh --publish  打包 + 冒烟 + 发到 npm（make publish，由人执行）
#
# 为什么分开：npm publish 是对外的、撤不回的动作（72 小时后连 unpublish 都不行），
# 不该由"合并即触发"的流程自动做。合并产出的是 dist/ 里的 tarball，Planner 下载它
# 做线上验收；什么时候对外发版，由人改版本号并执行 make publish 来决定。
#
# 两种模式都会挡住：三处版本号不一致、CHANGELOG 没定版、打出来的包跑不起来。
set -eo pipefail

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

die() { printf '%s中止：%s\n' "${MODE_LABEL:-打包}" "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

mode=pack MODE_LABEL=打包
case ${1:-} in
  --publish) mode=publish; MODE_LABEL=发布 ;;
  --pack|"") ;;
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "未知参数：$1" ;;
esac

for release_cmd in npm jq tar; do
  command -v "$release_cmd" >/dev/null 2>&1 || die "没有 $release_cmd"
done

name=$(jq -r '.name // empty' package.json)
version=$(jq -r '.version // empty' package.json)
[ -n "$name" ] || die "package.json 里没有 name"
[ -n "$version" ] || die "package.json 里没有 version"

# 版本号有三份（package.json、CLI、CHANGELOG），必须对得上
cli_version=$(sed -n 's/^AUTOTEAM_VERSION="\(.*\)"/\1/p' skills/autoteam/scripts/lib/common.sh)
[ "$cli_version" = "$version" ] ||
  die "版本不一致：package.json 是 $version，common.sh 是 ${cli_version:-空}"
grep -q "^## $version" CHANGELOG.md ||
  die "CHANGELOG.md 里没有 ## $version 这一段：发布前先把「未发布」那段定版"

# 打一个真包出来跑一遍：files 漏了实现的话，装完的 autoteam 是个空壳
tmp=$(mktemp -d "${TMPDIR:-/tmp}/autoteam-release.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
# dist/ 是文档站的构建输出（会发布到 autoteam.hdgcs.com），包不能放那里
mkdir -p build/pkg

tarball=$(npm pack --silent --pack-destination "$tmp" "$ROOT") || die "npm pack 失败"
tar -xzf "$tmp/$tarball" -C "$tmp" || die "解包失败：$tarball"
for f in bin/autoteam skills/autoteam/SKILL.md skills/autoteam/scripts/autoteam \
  skills/autoteam/scripts/lib/common.sh skills/autoteam/assets/templates/Makefile; do
  [ -f "$tmp/package/$f" ] || die "包里少了 $f（看 package.json 的 files）"
done
packed=$(bash "$tmp/package/bin/autoteam" version) || die "包里的 autoteam 跑不起来"
[ "$packed" = "autoteam $version" ] || die "包里的 autoteam 报的版本是「$packed」"

# 再往前一步：用这个包在一个干净仓库里真的装一遍，确认装出来的东西是完整的。
# 只验证包能用，不碰网络、不碰用户的 GitHub 和 Multica
sandbox=$tmp/sandbox
mkdir -p "$sandbox" && cd "$sandbox"
git init -q -b main . && git remote add origin https://github.com/acme/smoke.git
NO_COLOR=1 bash "$tmp/package/bin/autoteam" init --owner smoke-owner >/dev/null ||
  die "用打出来的包跑 autoteam init 失败"
for f in ops/agents/planner.md ops/agents/scripts/gh-app-token.sh .github/workflows/gate.yml; do
  [ -f "$f" ] || die "装出来的项目缺 $f"
done
grep -rq '{{AUTOTEAM_' . 2>/dev/null && die "装出来的文件里还有没替换的占位符"
cd "$ROOT"

cp "$tmp/$tarball" "build/pkg/$tarball"
info "打包检查通过：build/pkg/$tarball（版本 $version，装到干净仓库跑通）"

[ "$mode" = publish ] || exit 0

dirty=$(git status --porcelain 2>/dev/null) || dirty=""
if [ -n "$dirty" ] && [ -z "${DRY_RUN:-}" ]; then
  die "工作区有未提交的改动，不要从这种状态发布"
fi

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
  npm whoami >/dev/null 2>&1 || die "npm 没有登录：先 npm login"
fi

npm publish ${publish_args[@]+"${publish_args[@]}"}
info "完成：$name@$version"
