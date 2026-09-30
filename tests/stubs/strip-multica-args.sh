# shellcheck shell=bash
# 供命令桩 source：去掉 Multica 的全局选项，保留命令参数。
args=()
while [ $# -gt 0 ]; do
  case $1 in --profile|--workspace-id|--output) shift 2 ;; *) args+=("$1"); shift ;; esac
done
set -- "${args[@]}"
