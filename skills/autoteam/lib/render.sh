# shellcheck shell=bash
# 模板渲染和安装清单。
# 占位符写成 {{AUTOTEAM_名字}}，取同名 shell 变量的值；未定义的占位符原样保留。
# 刻意不用 ${var//pat/rep}：bash 5.2 起替换串里的 & 有特殊含义，值里带 & 会被改坏。

render_string() {
  local s=$1 out="" rest name re_name='^AUTOTEAM_[A-Z0-9_]+$'
  while :; do
    case $s in
      *"{{AUTOTEAM_"*"}}"*) ;;
      *) break ;;
    esac
    out+=${s%%"{{AUTOTEAM_"*}
    rest=${s#*"{{AUTOTEAM_"}
    name=AUTOTEAM_${rest%%"}}"*}
    if [[ $name =~ $re_name ]] && [ -n "${!name+x}" ]; then
      out+=${!name}
      s=${rest#*"}}"}
    else
      # 不认识的占位符原样输出，从占位符后面继续找
      out+="{{AUTOTEAM_"
      s=$rest
    fi
  done
  out+=$s
  printf '%s' "$out"
}

render_file() {
  local content
  content=$(cat "$1"; printf x)
  render_string "${content%x}"
}

# 安装清单：<模板路径> <目标路径> <方式>
#   file     整文件，已存在则跳过（--force 覆盖）
#   exec     同 file，写完加可执行位
#   config   只在不存在时创建，--force 也不覆盖（用户数据）
#   block    受管块，追加到已有文件末尾；已有受管块则跳过（--force 替换块内内容）
#   makefile 只在不存在时创建；已存在时只检查 check/dev/deploy 目标
autoteam_manifest() {
  cat <<'EOF'
root/AGENTS.block.md                  AGENTS.md                               block
root/Makefile                         Makefile                                makefile
root/jscpd.json                       .jscpd.json                             file
root/github/CODEOWNERS.block          .github/CODEOWNERS                      block
root/github/pull_request_template.md  .github/pull_request_template.md        file
root/github/workflows/gate.yml        .github/workflows/gate.yml              file
root/github/workflows/deploy.yml      .github/workflows/deploy.yml            file
root/github/workflows/rollback.yml    .github/workflows/rollback.yml          file
autoteam/autoteam.conf                ops/agents/autoteam.conf                config
autoteam/registry.yaml                ops/agents/registry.yaml                config
autoteam/README.md                    ops/agents/README.md                    file
../instructions/roles/planner.md      ops/agents/planner.md                   file
../instructions/roles/implementer.md  ops/agents/implementer.md               file
../instructions/roles/reviewer.md     ops/agents/reviewer.md                  file
../instructions/roles/auditor.md      ops/agents/auditor.md                   file
../instructions/planner-mcp.json      ops/agents/planner-mcp.json             file
autoteam/playbook.md                  ops/agents/playbook.md                  file
autoteam/scripts/gh-app-token.sh      ops/agents/scripts/gh-app-token.sh      exec
autoteam/scripts/loop-guard.sh        ops/agents/scripts/loop-guard.sh        exec
autoteam/scripts/merge-mode.sh        ops/agents/scripts/merge-mode.sh        exec
autoteam/scripts/health-metrics.sh    ops/agents/scripts/health-metrics.sh    exec
EOF
  local f name
  for f in "$AUTOTEAM_TEMPLATES"/../instructions/autopilots/*.md; do
    [ -f "$f" ] || continue
    name=${f##*/}
    printf '%-37s %-39s %s\n' "../instructions/autopilots/$name" "ops/agents/autopilots/$name" file
  done
}

# 受管块的开始/结束标记（按目标文件类型）
block_markers() {
  case $1 in
    *.md) printf '%s\n%s\n' '<!-- >>> autoteam >>> -->' '<!-- <<< autoteam <<< -->' ;;
    *)    printf '%s\n%s\n' '# >>> autoteam >>>' '# <<< autoteam <<<' ;;
  esac
}

# 取出文件里受管块的内容（含标记行）
block_extract() {
  local file=$1 start end
  start=$(block_markers "$file" | sed -n 1p)
  end=$(block_markers "$file" | sed -n 2p)
  awk -v s="$start" -v e="$end" '$0 == s {on = 1} on {print} $0 == e {on = 0}' "$file"
}

# 把文件里的受管块替换成新内容（新内容自带标记行）
block_replace() {
  local file=$1 new=$2 start end tmp
  start=$(block_markers "$file" | sed -n 1p)
  end=$(block_markers "$file" | sed -n 2p)
  tmp=$(autoteam_tmpdir)/block.$$
  printf '%s' "$new" > "$tmp.new"
  awk -v s="$start" -v e="$end" -v newfile="$tmp.new" '
    $0 == s { while ((getline line < newfile) > 0) print line; skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp" "$tmp.new"
}
