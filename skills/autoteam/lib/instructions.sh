# shellcheck shell=bash
# 角色指令、autopilot、planner-mcp.json 的读取和 eject。
# 这些文件默认不落盘在用户仓库里：读取时优先用 .autoteam/instructions/ 下已 eject 的那份，
# 没有就回落到 autoteam 包内的 instructions/。落盘 = 用户有意改过，升级不会覆盖。

AUTOTEAM_INSTRUCTIONS_REL=$AUTOTEAM_DIR/instructions

# 指令文件的实际路径：instructions_path <kind> <name>
# kind 是 roles / autopilots / runbooks，或空串（planner-mcp.json 直接放在 instructions/ 下）
instructions_path() {
  local rel=${1:+$1/}$2
  if [ -f "$AUTOTEAM_INSTRUCTIONS_REL/$rel" ]; then
    printf '%s\n' "$AUTOTEAM_INSTRUCTIONS_REL/$rel"
  elif [ -f "$AUTOTEAM_HOME/instructions/$rel" ]; then
    printf '%s\n' "$AUTOTEAM_HOME/instructions/$rel"
  else
    return 1
  fi
}

# 所有角色指令和 autopilot 正文共用的前言（开工先检查暂停）只在包内 instructions/_preamble.md
# 维护一份，不 eject：同步到 Multica 时渲染（{{AUTOTEAM_LANGUAGE}}）并加在最前面。
instructions_with_preamble() {
  local pre
  pre=$(render_file "$AUTOTEAM_HOME/instructions/_preamble.md") || return 1
  pre=${pre%$'\n'}
  printf '%s\n\n%s' "$pre" "$1"
}

# 角色在 Multica 上应有的指令全文：前言 + 角色文件。agent 同步和 doctor 漂移对比共用
instructions_role_text() {
  local f
  f=$(instructions_path roles "$1.md") || return 1
  instructions_with_preamble "$(read_file "$f")"
}

# 指令来自哪里，写进 Multica agent 的描述：不能写包内的绝对路径，那是机器相关的
instructions_source() {
  local rel=${1:+$1/}$2
  if [ -f "$AUTOTEAM_INSTRUCTIONS_REL/$rel" ]; then
    printf '%s' "$AUTOTEAM_INSTRUCTIONS_REL/$rel"
  else
    printf 'autoteam 包内 instructions/%s' "$rel"
  fi
}

# 列出某一类指令的文件路径：包内和已 eject 的合成一份清单，同名以 eject 的为准
instructions_list() {
  local kind=$1 f name
  for f in "$AUTOTEAM_HOME/instructions/$kind"/*.md "$AUTOTEAM_INSTRUCTIONS_REL/$kind"/*.md; do
    [ -f "$f" ] && printf '%s\n' "${f##*/}"
  done | sort -u | while IFS= read -r name; do
    instructions_path "$kind" "$name"
  done
}

# eject 目标：角色名、autopilot 名或 planner-mcp.json。输出 "<kind> <文件名>"（kind 可为空）
instructions_resolve_target() {
  case $1 in
    planner|implementer|reviewer|auditor) printf 'roles %s.md\n' "$1" ;;
    planner-mcp.json) printf ' planner-mcp.json\n' ;;
    *)
      if [ -f "$AUTOTEAM_HOME/instructions/autopilots/${1%.md}.md" ]; then
        printf 'autopilots %s.md\n' "${1%.md}"
      elif [ -f "$AUTOTEAM_HOME/instructions/runbooks/${1%.md}.md" ]; then
        printf 'runbooks %s.md\n' "${1%.md}"
      else
        return 1
      fi ;;
  esac
}

instructions_all_targets() {
  local f
  printf '%s\n' planner implementer reviewer auditor planner-mcp.json
  for f in "$AUTOTEAM_HOME"/instructions/autopilots/*.md; do
    [ -f "$f" ] || continue
    f=${f##*/}
    printf '%s\n' "${f%.md}"
  done
  for f in "$AUTOTEAM_HOME"/instructions/runbooks/*.md; do
    [ -f "$f" ] || continue
    f=${f##*/}
    printf '%s\n' "${f%.md}"
  done
}

eject_usage() {
  cat <<'EOF'
用法：autoteam eject [--diff] <目标>...
      autoteam eject [--diff] --all

把 autoteam 包内的指令文件复制到 .autoteam/instructions/，此后由你维护，升级不会覆盖。
autoteam multica 优先读这里的文件，没有才用包内的那份。

<目标>：角色名（planner / implementer / reviewer / auditor）、autopilot 名（如 patrol）、
       runbook 名（autoteam runbook --list）、planner-mcp.json。

选项：
  --all    对全部指令文件操作
  --diff   只打印包内文本与已 eject 文本的差异，不写文件（没 eject 过的目标提示“未 eject”）
EOF
}

cmd_eject() {
  local diff_only=0 all=0 targets=() a
  for a in "$@"; do
    case $a in
      -h|--help) eject_usage; return 0 ;;
      --diff) diff_only=1 ;;
      --all) all=1 ;;
      -*) eject_usage >&2; die "未知选项：$a" ;;
      *) targets+=("$a") ;;
    esac
  done
  if [ "$all" = 1 ]; then
    [ ${#targets[@]} -eq 0 ] || die "--all 不能和具体目标一起用"
    while IFS= read -r a; do targets+=("$a"); done <<EOF
$(instructions_all_targets)
EOF
  fi
  [ ${#targets[@]} -gt 0 ] || { eject_usage >&2; die "需要指定目标或 --all"; }

  local root spec kind name src dst
  root=$(repo_root)
  cd "$root" || die "进不去 $root"
  for a in "${targets[@]}"; do
    spec=$(instructions_resolve_target "$a") || die "不认识的目标：$a（角色名、autopilot 名、runbook 名或 planner-mcp.json）"
    kind=${spec%% *} name=${spec#* }
    src=$AUTOTEAM_HOME/instructions/${kind:+$kind/}$name
    dst=$AUTOTEAM_INSTRUCTIONS_REL/${kind:+$kind/}$name
    if [ "$diff_only" = 1 ]; then
      if [ ! -f "$dst" ]; then
        info "$a：未 eject，生效的是包内版本"
      elif diff -u --label "包内 $name" --label "$dst" "$src" "$dst"; then
        info "$a：已 eject，与包内一致"
      fi
    elif [ -f "$dst" ]; then
      info "已存在，保留 $dst"
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      ok "已 eject $dst"
    fi
  done
  [ "$diff_only" = 1 ] || hint "此后由你维护，升级不会覆盖；autoteam eject --diff 可对比包内新版本"
}

runbook_usage() {
  cat <<'EOF'
用法：autoteam runbook <名字>
      autoteam runbook --list

只读：输出一份 runbook 的正文（去掉 front matter）。有 .autoteam/instructions/runbooks/ 下 eject 的
就用它，没有才用 autoteam 包内的。runbook 不同步到 Multica，由 agent 运行时按需读取。

选项：
  --list   列出可用的名字和一句话说明（front matter 的 description）
EOF
}

runbook_names() {
  local f
  instructions_list runbooks | while IFS= read -r f; do
    f=${f##*/}
    printf '%s\n' "${f%.md}"
  done
}

runbook_list() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    printf '%s\t%s\n' "$name" "$(fm_get "$(instructions_path runbooks "$name.md")" description)"
  done <<EOF
$(runbook_names)
EOF
}

cmd_runbook() {
  case ${1:-} in
    -h|--help) runbook_usage; return 0 ;;
    --list) [ $# -eq 1 ] || { runbook_usage >&2; die "--list 不带参数"; }; runbook_list; return 0 ;;
    -*|'') runbook_usage >&2; die "需要一个 runbook 名字或 --list" ;;
  esac
  [ $# -eq 1 ] || { runbook_usage >&2; die "只能指定一个 runbook"; }
  local name=${1%.md} f
  if [[ ! $name =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || ! f=$(instructions_path runbooks "$name.md"); then
    printf '没有名为 %s 的 runbook。可用的：\n' "$1" >&2
    runbook_list >&2
    return 1
  fi
  if [ "$(sed -n 1p "$f")" = "---" ]; then fm_body "$f"; else cat "$f"; fi
}
