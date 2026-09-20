#!/usr/bin/env bash
# 把模板里的工作流渲染到 <输出目录>/.github/workflows，给 actionlint 检查。
# 渲染两套：有 environment 的（公开仓库）和没有 environment 的（GitHub Free 私有仓库）。
set -eo pipefail
out=${1:?用法：render-workflows.sh <输出目录>}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$out/.github/workflows"
out=$(cd "$out" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/autoteam-render.XXXXXX")
trap 'rm -rf "$work"' EXIT
render() {  # 子目录 environment 值 文件后缀
  mkdir -p "$work/$1" && cd "$work/$1"
  git init -q -b main && git remote add origin https://github.com/acme/shop.git
  env PATH="$(dirname "$(command -v jq)"):$(dirname "$(command -v git)"):/usr/bin:/bin" NO_COLOR=1 \
    AUTOTEAM_DEPLOY_ENVIRONMENT="$2" bash "$here/../bin/autoteam" init --owner alice >/dev/null
  for f in .github/workflows/*.yml; do
    base=$(basename "$f" .yml)
    cp "$f" "$out/.github/workflows/$base$3.yml"
  done
}
render with-env production ""
render no-env "" "-noenv"
ls "$out/.github/workflows"
