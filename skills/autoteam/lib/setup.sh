# shellcheck shell=bash
# 一次预览两端，确认后按 GitHub → Multica → doctor 执行。

setup_usage() {
  cat <<'EOF'
用法：autoteam setup [选项]

依次预览 GitHub 和 Multica。交互终端预览后确认一次；非交互默认只预览，
加 --apply 才执行。执行完成后自动运行 doctor。

  --apply                  预览后直接执行，无需交互确认
  --trial                  传给 github：单身份试用模式
  --apps <角色=App ID,...> 传给 github：三个 GitHub App ID
  --repo <owner/name>      传给 github：覆盖仓库
  --profile <名字>         传给 multica 和 doctor
  --workspace <slug|ID>    传给 multica 和 doctor
  --paused                 传给 multica：新建 autopilot 暂停
EOF
}

cmd_setup() {
  local apply=0 answer="" github_args=() multica_args=() doctor_args=()
  while [ $# -gt 0 ]; do
    case $1 in
      --apply) apply=1; shift ;;
      --trial|--paused)
        if [ "$1" = --trial ]; then github_args+=("$1"); else multica_args+=("$1"); fi
        shift ;;
      --apps|--repo|--profile|--workspace)
        [ $# -ge 2 ] && [ -n "$2" ] || die "$1 需要一个值"
        case $1 in
          --apps|--repo) github_args+=("$1" "$2") ;;
          --profile|--workspace) multica_args+=("$1" "$2"); doctor_args+=("$1" "$2") ;;
        esac
        shift 2 ;;
      -h|--help) setup_usage; return 0 ;;
      *) setup_usage >&2; die "未知选项：$1" ;;
    esac
  done

  section "第 1/2 步：预览 GitHub"
  if ! AUTOTEAM_APPLY=0 bash "$AUTOTEAM_HOME/bin/autoteam" github "${github_args[@]}"; then
    info "GitHub 预览失败；尚未执行改动。修复后重新运行 autoteam setup。"
    return 1
  fi
  section "第 2/2 步：预览 Multica"
  if ! AUTOTEAM_APPLY=0 bash "$AUTOTEAM_HOME/bin/autoteam" multica "${multica_args[@]}"; then
    info "GitHub 预览已完成，Multica 预览失败；尚未执行改动。修复后重新运行 autoteam setup。"
    return 1
  fi

  if [ "$apply" != 1 ]; then
    if [ ! -t 0 ]; then
      info "两端预览完成，未执行改动；加 --apply 执行。"
      return 0
    fi
    printf '\n确认按 GitHub → Multica → doctor 执行？[y/N] '
    read -r answer || return 0
    case $answer in y|Y|yes|YES) ;; *) info "已取消，未执行改动。"; return 0 ;; esac
  fi

  section "执行 GitHub"
  if ! bash "$AUTOTEAM_HOME/bin/autoteam" github "${github_args[@]}" --apply; then
    info "GitHub 执行失败；Multica 和 doctor 未执行。已写入的 GitHub 改动不会回滚；修复后重新运行 autoteam setup --apply。"
    return 1
  fi
  section "执行 Multica"
  if ! bash "$AUTOTEAM_HOME/bin/autoteam" multica "${multica_args[@]}" --apply; then
    info "GitHub 已完成，Multica 执行失败，doctor 未执行。已写入的改动不会回滚；修复后运行 autoteam multica --apply，再运行 autoteam doctor。"
    return 1
  fi
  section "运行 doctor"
  if ! bash "$AUTOTEAM_HOME/bin/autoteam" doctor "${doctor_args[@]}"; then
    info "GitHub 和 Multica 已完成，doctor 未通过。按上方提示修复后运行 autoteam doctor。"
    return 1
  fi
}
