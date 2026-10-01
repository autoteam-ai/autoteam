# shellcheck shell=bash

t_multica_default_profile_survives_pipefail() {
  local i out
  # 只解析 CLI 的默认 profile，不读取仓库配置或调用 init。
  new_repo
  for ((i=0; i<50; i++)); do
    if ! out=$(env -u MULTICA_SERVER_URL -u MULTICA_TOKEN STUB_CONFIG_SHOW_BULK=1 HOME="$WORK/.home" \
      bash -c 'set -eo pipefail; . "$1"; MC_BIN=$2; mc_resolve_profile ""; [ -z "$MC_PROFILE" ]' \
      _ "$ROOT/skills/autoteam/lib/multica.sh" "$TESTS_DIR/stubs/multica" 2>&1); then
      tfail "第 $((i + 1)) 次默认 profile 判断失败：$out"
      return
    fi
  done
}

t_no_pipe_to_quiet_grep_in_package() {
  local matches rc
  matches=$(grep -nE '(^|[^|])\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' \
    "$ROOT"/skills/autoteam/bin/* \
    "$ROOT"/skills/autoteam/lib/*.sh)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    tfail "bin/、lib/ 中不要用命令 | grep -q 判断；先把命令输出存进变量，再匹配变量：$matches"
  elif [ "$rc" -ne 1 ]; then
    tfail "静态检查读取 bin/、lib/ 失败（grep 退出码 $rc）"
  fi
}
