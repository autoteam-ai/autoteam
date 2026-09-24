# shellcheck shell=bash
# 角色指令、autopilot、planner-mcp.json 的读取和 eject。
# 这些文件默认不落盘在用户仓库里：读取时优先用 .autoteam/instructions/ 下已 eject 的那份，
# 没有就回落到 autoteam 包内的 instructions/。落盘 = 用户有意改过，升级不会覆盖。

AUTOTEAM_INSTRUCTIONS_REL=$AUTOTEAM_DIR/instructions

# 指令文件的实际路径：instructions_path <kind> <name>
# kind 是 roles / autopilots，或空串（planner-mcp.json 直接放在 instructions/ 下）
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
      [ -f "$AUTOTEAM_HOME/instructions/autopilots/${1%.md}.md" ] || return 1
      printf 'autopilots %s.md\n' "${1%.md}" ;;
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
}

eject_usage() {
  cat <<'EOF'
用法：autoteam eject [--diff] <目标>...
      autoteam eject [--diff] --all

把 autoteam 包内的指令文件复制到 .autoteam/instructions/，此后由你维护，升级不会覆盖。
autoteam multica 优先读这里的文件，没有才用包内的那份。

<目标>：角色名（planner / implementer / reviewer / auditor）、autopilot 名（如 patrol）、
       planner-mcp.json。

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
    spec=$(instructions_resolve_target "$a") || die "不认识的目标：$a（角色名、autopilot 名或 planner-mcp.json）"
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
