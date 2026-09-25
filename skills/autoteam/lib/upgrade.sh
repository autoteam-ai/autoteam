# shellcheck shell=bash
# autoteam upgrade：按 .lock.json 升级已安装的文件。没改过的直接覆盖，改过的只报告、不写。
# AUTOTEAM_FORCE / AUTOTEAM_DRY_RUN 由 init_install 读取：
# shellcheck disable=SC2034

upgrade_usage() {
  cat <<'EOF'
用法：autoteam upgrade [--dry-run] [文件...]

把已安装的文件升级到当前 autoteam 的模板，结束后更新 .autoteam/.lock.json。
  - 现在的内容和 lock 记录一致（没改过）：直接覆盖
  - 不一致（本地改过）：打印差异，不写，交给你决定
  - autoteam.conf、registry.yaml、Makefile 是你的，不动

选项：
  --dry-run   只列出计划，不写任何文件
EOF
}

cmd_upgrade() {
  local only=" " a
  AUTOTEAM_FORCE=0 AUTOTEAM_DRY_RUN=0
  for a in "$@"; do
    case $a in
      -h|--help) upgrade_usage; return 0 ;;
      --dry-run) AUTOTEAM_DRY_RUN=1 ;;
      -*) upgrade_usage >&2; die "未知选项：$a" ;;
      *) only="$only${a#./} " ;;
    esac
  done
  local root tpl target mode content want have start kept=""
  root=$(repo_root)
  cd "$root" || die "进不去 $root"
  conf_exists "$root" || die "还没有 $AUTOTEAM_CONF_REL，先运行 autoteam init"
  conf_load "$root"
  init_derived_vars
  lock_load

  section "升级文件（${LOCK_VERSION:-没有 lock} → $(autoteam_version)）"
  if [ -z "$LOCK_VERSION" ]; then
    warn "没有 $AUTOTEAM_LOCK_REL（旧版 autoteam 装的项目）：和模板不一致的文件无法判断是否改过，一律不覆盖；结束后生成 lock"
  fi
  while read -r tpl target mode; do
    [ -n "$tpl" ] || continue
    [ "$only" = " " ] || case $only in *" $target "*) ;; *) continue ;; esac
    AUTOTEAM_FORCE=0
    start=$(block_markers "$target" | sed -n 1p)
    # 文件不存在、受管块还没追加：交给 init_install 新建 / 追加
    if lock_tracked "$mode" && [ -e "$target" ] && { [ "$mode" != block ] || grep -qxF "$start" "$target"; }; then
      content=$(render_file "$AUTOTEAM_TEMPLATES/$tpl"; printf x)
      content=${content%x}
      want=$(lock_sha_want "$mode" "$content")
      have=$(lock_sha_have "$target" "$mode")
      if [ "$have" != "$want" ]; then
        if [ "$have" = "$(lock_get "$target")" ]; then
          AUTOTEAM_FORCE=1
        else
          upgrade_report "$target" "$mode" "$content"
          lock_record "$target" "$mode" "$want"
          kept="$kept $target"
          continue
        fi
      fi
    fi
    init_install "$tpl" "$target" "$mode"
  done <<EOF
$(autoteam_manifest)
root/gitignore.block                  .gitignore                              block
EOF

  if [ "$AUTOTEAM_DRY_RUN" = 1 ]; then
    printf '\n%s以上是预览，没有写任何文件。%s\n' "$C_BLUE" "$C_RESET"
    return 0
  fi
  lock_save "$(autoteam_version)"
  ok "$AUTOTEAM_LOCK_REL 已同步（版本 $(autoteam_version)）"
  if [ -n "$kept" ]; then
    section "下一步：本地改过的文件没有动"
    info "逐个决定：$kept"
    info "- 保留你的改动：把上面差异里新模板需要的部分手工合进去（以后 upgrade 仍会列出它）"
    info "- 放弃你的改动：autoteam init --force <文件>"
  fi
}

upgrade_report() {
  local target=$1 mode=$2 content=$3
  if [ -n "$(lock_get "$target")" ]; then
    warn "本地已修改，未覆盖 $target"
  else
    warn "lock 里没有记录、无法判断是否改过，未覆盖 $target"
  fi
  # 包里不带历史模板，拿不到旧模板的渲染结果，只能给两方对比
  hint "两方对比（当前文件 → 新模板）；包里不带历史模板，给不出三方对比"
  init_diff_one "$target" "$mode" "$content" "新模板 $(autoteam_version)" || true
}
