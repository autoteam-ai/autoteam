#!/usr/bin/env bash
# 判断这个仓库由谁来合并 PR，Implementer 开自动合并前、Reviewer 批准后使用。
# 用法：ops/agents/scripts/merge-mode.sh
# 输出 platform：规则集 autoteam 生效且允许自动合并，Implementer 开自动合并，平台在评审和检查都通过后合并；
# 输出 reviewer：没有平台闸门（比如 GitHub Free 的私有仓库），不要开自动合并——这时 `gh pr merge --auto`
#   会立即合并、绕过评审和检查——由 Reviewer 批准后、检查全部通过时手动合并。
# 查不到（没权限、网络错误）时按 reviewer 处理。依赖 gh、git。
set -o pipefail

if [ "${1:-}" = -h ] || [ "${1:-}" = --help ]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
repo=$(sed -n 's/^AUTOTEAM_REPO=//p' "$root/ops/agents/autoteam.conf" 2>/dev/null | tail -n 1 | tr -d '[:space:]')
[ -n "$repo" ] || repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)

auto=$(gh api "repos/$repo" --jq '.allow_auto_merge' 2>/dev/null)
active=$(gh api "repos/$repo/rulesets" --jq '[.[] | select(.name == "autoteam" and .enforcement == "active")] | length' 2>/dev/null)

if [ "$auto" = true ] && [ "${active:-0}" -ge 1 ] 2>/dev/null; then
  echo platform
else
  echo reviewer
fi
