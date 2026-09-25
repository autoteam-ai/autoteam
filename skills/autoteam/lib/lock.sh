# shellcheck shell=bash
# .autoteam/.lock.json：装机版本 + 每个落盘文件的 sha256。upgrade / diff --check 靠它判断
# "用户改没改过"：现在的 sha 和 lock 一致就是原样，不一致就是有意改过。
# 受管块记块内容的 sha，整文件记整文件的 sha；autoteam.conf、registry.yaml、Makefile 是用户的，不记。
# 写入不依赖 jq：每个文件一行，读取也按行解析。查询可以用 jq：
#   jq -r '.files[".autoteam/playbook.md"].sha256' .autoteam/.lock.json

AUTOTEAM_LOCK_REL=$AUTOTEAM_DIR/.lock.json

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1
}

# lock 里记录的是不是这种文件
lock_tracked() { case $1 in file|exec|block) return 0 ;; esac; return 1; }

# 模板渲染结果的 sha：<方式> <渲染内容>。受管块和 block_extract 的比较口径一致
lock_sha_want() {
  case $1 in
    block) printf '%s' "${2%$'\n'}" | sha256_stdin ;;
    *) printf '%s' "$2" | sha256_stdin ;;
  esac
}

# 当前文件的 sha：<目标> <方式>；文件不存在时输出空
lock_sha_have() {
  [ -e "$1" ] || return 0
  case $2 in
    block) printf '%s' "$(block_extract "$1")" | sha256_stdin ;;
    *) sha256_stdin < "$1" ;;
  esac
}

# 读 lock 到临时文件，每行 "<路径> <kind> <sha>"；LOCK_VERSION 为空表示没有 lock
# shellcheck disable=SC2034  # LOCK_VERSION 在 init / upgrade 里用
lock_load() {
  LOCK_ENTRIES=$(autoteam_tmpdir)/lock.entries
  LOCK_VERSION=""
  : > "$LOCK_ENTRIES"
  [ -f "$AUTOTEAM_LOCK_REL" ] || return 0
  LOCK_VERSION=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$AUTOTEAM_LOCK_REL" | head -n 1)
  sed -n 's/^    "\([^"]*\)": { "kind": "\([a-z]*\)", "sha256": "\([0-9a-f]\{64\}\)" },\{0,1\}$/\1 \2 \3/p' \
    "$AUTOTEAM_LOCK_REL" > "$LOCK_ENTRIES"
}

lock_get() { awk -v p="$1" '$1 == p { print $3; exit }' "$LOCK_ENTRIES"; }

# 按装完之后的样子记：和模板一致就记模板的 sha；不一致（改过、没被覆盖）保留原记录，
# 没有记录时也记模板的 sha，下次一比就知道它不是原样。参数：<目标> <方式> <模板 sha>
lock_record() {
  local kind=file
  [ "$2" != block ] || kind=block
  if [ "$(lock_sha_have "$1" "$2")" = "$3" ] || [ -z "$(lock_get "$1")" ]; then
    awk -v p="$1" '$1 != p' "$LOCK_ENTRIES" > "$LOCK_ENTRIES.new"
    printf '%s %s %s\n' "$1" "$kind" "$3" >> "$LOCK_ENTRIES.new"
    mv "$LOCK_ENTRIES.new" "$LOCK_ENTRIES"
  fi
}

# lock 有记录、且现在的内容和记录不同：用户改过
lock_modified() {
  local locked
  locked=$(lock_get "$1")
  [ -n "$locked" ] && [ -e "$1" ] && [ "$(lock_sha_have "$1" "$2")" != "$locked" ]
}

# 内容没变就不写：只刷新 generated_at 会让每次 init / upgrade 都多出一处无意义的 diff
lock_save() {
  local new
  new=$(
    printf '{\n  "version": "%s",\n  "generated_at": "%s",\n  "files": {\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    LC_ALL=C sort "$LOCK_ENTRIES" | awk '{
      printf "%s    \"%s\": { \"kind\": \"%s\", \"sha256\": \"%s\" }", (NR > 1 ? ",\n" : ""), $1, $2, $3
    } END { if (NR) print "" }'
    printf '  }\n}'
  )
  if [ -f "$AUTOTEAM_LOCK_REL" ] &&
    [ "$(grep -v '"generated_at"' "$AUTOTEAM_LOCK_REL")" = "$(printf '%s\n' "$new" | grep -v '"generated_at"')" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$AUTOTEAM_LOCK_REL")"
  printf '%s\n' "$new" > "$AUTOTEAM_LOCK_REL"
}
