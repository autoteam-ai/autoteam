# shellcheck shell=bash
# autoteam migrate：把旧版布局（配置放在下面这个目录里）一次性迁到 .autoteam/。
# 只碰迁移涉及的文件，不提交、不推送。旧路径的字面量只允许出现在这个文件里。
# shellcheck disable=SC2034  # AUTOTEAM_LEGACY_DIR 在 doctor.sh 里用

AUTOTEAM_LEGACY_DIR=ops/agents

migrate_usage() {
  cat <<EOF
用法：autoteam migrate [--dry-run]

把旧版布局迁到 $AUTOTEAM_DIR/：
  1. git mv $AUTOTEAM_LEGACY_DIR $AUTOTEAM_DIR（local/ 一起带走）
  2. 角色指令、autopilot、planner-mcp.json 不再落盘：和包内文件逐个比对，
     内容一致的删除；改过的保留到 $AUTOTEAM_DIR/instructions/，当作已 eject
  3. 更新 .gitignore、.github/CODEOWNERS、AGENTS.md 三个受管块里的路径
  4. 写 $AUTOTEAM_LOCK_REL
  5. 列出仓库里其余仍写着旧路径的文件，提示人工处理（不自动改）

选项：
  --dry-run   只打印计划，不改任何文件
不加就执行，但不提交、不推送。
EOF
}

# 文件是不是 git 跟踪的：跟踪的用 git mv / git rm，这样重命名和删除都进暂存区
migrate_tracked() { git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }

# autopilot 的 cron 行改成 cron_key：<旧文件> <KEY> <conf 里 KEY 的值> <1=不管值是否一致都改>。
# 旧版渲染出的是 "cron: <值>"，只在 front matter 内替换
migrate_cron_key() {
  awk -v key="$2" -v val="$3" -v force="$4" '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { fm = 0 }
    fm && /^cron:/ {
      v = $0; sub(/^cron:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (key != "" && (force == 1 || v == val)) { print "cron_key: " key; next }
    }
    { print }
  ' "$1"
}

# 处理一个旧指令文件：<旧文件> <包内对应文件> <eject 目的地>
migrate_one() {
  local src=$1 pkg=$2 dst=$3 name shown key="" val="" tmp
  [ -f "$src" ] || return 0
  name=${src#"$AUTOTEAM_LEGACY_DIR"/}
  shown=$AUTOTEAM_DIR/${dst#"$AUTOTEAM_LEGACY_DIR"/}
  tmp=$(autoteam_tmpdir)/migrate
  [ ! -f "$pkg" ] || key=$(fm_get "$pkg" cron_key)
  [ -z "$key" ] || val=${!key}
  # 和包内比之前先做两处机械换算：旧路径换成新路径；cron 值等于 conf 里的值就换成 cron_key
  migrate_cron_key "$src" "$key" "$val" 0 | sed "s#$AUTOTEAM_LEGACY_DIR#$AUTOTEAM_DIR#g" > "$tmp.norm"
  if [ -f "$pkg" ] && cmp -s "$tmp.norm" "$pkg"; then
    planned "删除 $name（与包内一致，不再落盘）"
    [ "$AUTOTEAM_DRY_RUN" = 1 ] && return 0
    if migrate_tracked "$src"; then git rm -qf -- "$src"; else rm -f "$src"; fi
    return 0
  fi
  if [ -f "$pkg" ]; then
    planned "保留 $name → $shown（与包内不同，按已 eject 处理）"
  else
    planned "保留 $name → $shown（包内没有同名文件，按你自己写的处理）"
  fi
  if grep -q '^cron:' "$src"; then
    if [ -z "$key" ]; then
      warn "$name 写的是 cron: 而包内没有对应的 cron_key，同步会缺定时触发，请手工改成 cron_key"
    elif [ "$(migrate_cron_key "$src" "$key" "$val" 0 | grep -c '^cron:')" != 0 ]; then
      warn "$name 的 cron 和 autoteam.conf 的 $key 不同，改成 cron_key 后以 conf 为准，请核对"
    fi
  fi
  [ "$AUTOTEAM_DRY_RUN" = 1 ] && return 0
  migrate_cron_key "$src" "$key" "$val" 1 > "$tmp.keep"
  mkdir -p "$(dirname "$dst")"
  if migrate_tracked "$src"; then git mv -- "$src" "$dst"; else mv "$src" "$dst"; fi
  cat "$tmp.keep" > "$dst"
}

migrate_instructions() {
  local legacy=$1 pkg=$AUTOTEAM_HOME/instructions inst role f
  inst=$legacy/instructions
  for role in planner implementer reviewer auditor; do
    migrate_one "$legacy/$role.md" "$pkg/roles/$role.md" "$inst/roles/$role.md"
  done
  for f in "$legacy"/autopilots/*.md; do
    [ -f "$f" ] || continue
    migrate_one "$f" "$pkg/autopilots/${f##*/}" "$inst/autopilots/${f##*/}"
  done
  migrate_one "$legacy/planner-mcp.json" "$pkg/planner-mcp.json" "$inst/planner-mcp.json"
  rmdir "$legacy/autopilots" 2>/dev/null || true # 全删光了就别把空目录带过去
}

# 三个受管块：重新渲染新模板，路径就都对了。文件里没有受管块的不碰
migrate_blocks() {
  local tpl target mode start
  while read -r tpl target mode; do
    start=$(block_markers "$target" | sed -n 1p)
    if [ -e "$target" ] && grep -qxF "$start" "$target"; then
      planned "更新 $target 的受管块（路径换成 $AUTOTEAM_DIR/）"
      [ "$AUTOTEAM_DRY_RUN" = 1 ] || { AUTOTEAM_FORCE=1 init_install "$tpl" "$target" "$mode" >/dev/null; }
    else
      info "$target 里没有 autoteam 受管块，跳过"
    fi
  done <<EOF
root/AGENTS.block.md AGENTS.md block
root/github/CODEOWNERS.block .github/CODEOWNERS block
root/gitignore.block .gitignore block
EOF
}

# lock：按装完之后的样子记每个落盘文件。和模板一致的记模板的 sha，upgrade 可以直接覆盖；
# 不一致的（旧版装的、或你改过的）也记模板的 sha，upgrade 只报告、不覆盖
migrate_lock() {
  local tpl target mode content start
  planned "写 $AUTOTEAM_LOCK_REL"
  [ "$AUTOTEAM_DRY_RUN" = 1 ] && return 0
  while read -r tpl target mode; do
    [ -n "$tpl" ] && lock_tracked "$mode" && [ -e "$target" ] || continue
    if [ "$mode" = block ]; then
      start=$(block_markers "$target" | sed -n 1p)
      grep -qxF "$start" "$target" || continue
    fi
    content=$(render_file "$AUTOTEAM_TEMPLATES/$tpl"; printf x)
    lock_record "$target" "$mode" "$(lock_sha_want "$mode" "${content%x}")"
  done <<EOF
$(autoteam_manifest)
root/gitignore.block .gitignore block
EOF
  lock_save "$(autoteam_version)"
}

# 列出仍写着旧路径的文件（含未跟踪但没被忽略的）。dry-run 时旧目录还没搬，不算它自己
migrate_residue() {
  local out
  section "仍写着旧路径的文件"
  if [ "$AUTOTEAM_DRY_RUN" = 1 ]; then
    out=$(git grep -cIF --untracked -e "$AUTOTEAM_LEGACY_DIR" -- . ":(exclude)$AUTOTEAM_LEGACY_DIR" || true)
  else
    out=$(git grep -cIF --untracked -e "$AUTOTEAM_LEGACY_DIR" || true)
  fi
  if [ -z "$out" ]; then
    ok "没有"
    return 0
  fi
  warn "下面这些文件里还有 $AUTOTEAM_LEGACY_DIR（文件:出现次数），autoteam 不自动改，请人工处理："
  [ "$AUTOTEAM_DRY_RUN" != 1 ] || hint "（受管块里的会在执行时更新；下面按现状统计）"
  printf '%s\n' "$out" | sed 's/^/     /'
  hint "由 autoteam 生成的文件（.github/workflows/*.yml、$AUTOTEAM_DIR/scripts/*.sh 等）没手改过的话，"
  hint "autoteam diff 看差异，autoteam init --force <文件> 换成新模板；自己写的（README、workflow、AGENTS.md 正文）手工改"
}

cmd_migrate() {
  AUTOTEAM_DRY_RUN=0 AUTOTEAM_APPLY=1
  local a
  for a in "$@"; do
    case $a in
      -h|--help) migrate_usage; return 0 ;;
      --dry-run) AUTOTEAM_DRY_RUN=1 AUTOTEAM_APPLY=0 ;;
      *) migrate_usage >&2; die "未知参数：$a" ;;
    esac
  done
  local root
  root=$(repo_root)
  cd "$root" || die "进不去 $root"
  [ -d "$AUTOTEAM_LEGACY_DIR" ] || die "没有 $AUTOTEAM_LEGACY_DIR/，不是旧版布局，不需要迁移"
  [ ! -e "$AUTOTEAM_DIR" ] || die "$AUTOTEAM_DIR 已经存在，无法迁移：两边都有内容需要人工合并"
  [ -f "$AUTOTEAM_LEGACY_DIR/autoteam.conf" ] || die "$AUTOTEAM_LEGACY_DIR/autoteam.conf 不存在，不像是 autoteam 装的目录"
  conf_load_file "$AUTOTEAM_LEGACY_DIR/autoteam.conf"
  conf_load "$root"
  init_derived_vars
  lock_load

  section "指令文件（不再落盘）"
  migrate_instructions "$AUTOTEAM_LEGACY_DIR"

  section "移动目录"
  planned "git mv $AUTOTEAM_LEGACY_DIR $AUTOTEAM_DIR（local/ 一起带走）"
  if [ "$AUTOTEAM_DRY_RUN" != 1 ]; then
    if migrate_tracked "$AUTOTEAM_LEGACY_DIR"; then git mv "$AUTOTEAM_LEGACY_DIR" "$AUTOTEAM_DIR"; else mv "$AUTOTEAM_LEGACY_DIR" "$AUTOTEAM_DIR"; fi
    # 上一级目录空了就删掉；里面还有别的东西说明是用户自己的，不动
    rmdir "$(dirname "$AUTOTEAM_LEGACY_DIR")" 2>/dev/null || true
  fi

  section "受管块"
  migrate_blocks
  section "lock"
  migrate_lock
  migrate_residue

  if [ "$AUTOTEAM_DRY_RUN" = 1 ]; then
    printf '\n%s以上是计划，没有改任何文件。去掉 --dry-run 执行。%s\n' "$C_BLUE" "$C_RESET"
  else
    section "下一步"
    info "没有提交：git status 看改动，处理完上面列出的残留后走 PR 提交（$AUTOTEAM_DIR/ 受 CODEOWNERS 保护）"
    info "保留下来的指令已按 eject 处理，合并后 autoteam multica --apply 同步；「与包内不同」可能只是包升级过，"
    info "autoteam eject --diff <名字> 看差异，没有自己的改动就删掉那份，回到包内版本；autoteam doctor 检查"
  fi
}
