# shellcheck shell=bash
# 模板渲染和安装清单。
# 占位符写成 {{AIWF_名字}}，取同名 shell 变量的值；未定义的占位符原样保留。
# 刻意不用 ${var//pat/rep}：bash 5.2 起替换串里的 & 有特殊含义，值里带 & 会被改坏。

render_string() {
  local s=$1 out="" rest name re_name='^AIWF_[A-Z0-9_]+$'
  while :; do
    case $s in
      *"{{AIWF_"*"}}"*) ;;
      *) break ;;
    esac
    out+=${s%%"{{AIWF_"*}
    rest=${s#*"{{AIWF_"}
    name=AIWF_${rest%%"}}"*}
    if [[ $name =~ $re_name ]] && [ -n "${!name+x}" ]; then
      out+=${!name}
      s=${rest#*"}}"}
    else
      # 不认识的占位符原样输出，从占位符后面继续找
      out+="{{AIWF_"
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
aiwf_manifest() {
  cat <<'EOF'
AGENTS.block.md                       AGENTS.md                               block
Makefile                              Makefile                                makefile
jscpd.json                            .jscpd.json                             file
github/CODEOWNERS.block               .github/CODEOWNERS                      block
github/pull_request_template.md       .github/pull_request_template.md        file
github/workflows/gate.yml             .github/workflows/gate.yml              file
github/workflows/deploy.yml           .github/workflows/deploy.yml            file
github/workflows/rollback.yml         .github/workflows/rollback.yml          file
ops/agents/aiwf.conf                  ops/agents/aiwf.conf                    config
ops/agents/registry.yaml              ops/agents/registry.yaml                config
ops/agents/README.md                  ops/agents/README.md                    file
ops/agents/planner.md                 ops/agents/planner.md                   file
ops/agents/implementer.md             ops/agents/implementer.md               file
ops/agents/reviewer.md                ops/agents/reviewer.md                  file
ops/agents/auditor.md                 ops/agents/auditor.md                   file
ops/agents/planner-mcp.json           ops/agents/planner-mcp.json             file
ops/agents/scripts/loop-guard.sh      ops/agents/scripts/loop-guard.sh        exec
ops/agents/scripts/health-metrics.sh  ops/agents/scripts/health-metrics.sh    exec
EOF
  local f
  for f in "$AIWF_TEMPLATES"/ops/agents/autopilots/*.md; do
    [ -f "$f" ] || continue
    f=ops/agents/autopilots/${f##*/}
    printf '%-37s %-39s %s\n' "$f" "$f" file
  done
}

# 受管块的开始/结束标记（按目标文件类型）
block_markers() {
  case $1 in
    *.md) printf '%s\n%s\n' '<!-- >>> ai-workflow >>> -->' '<!-- <<< ai-workflow <<< -->' ;;
    *)    printf '%s\n%s\n' '# >>> ai-workflow >>>' '# <<< ai-workflow <<<' ;;
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
  tmp=$(aiwf_tmpdir)/block.$$
  printf '%s' "$new" > "$tmp.new"
  awk -v s="$start" -v e="$end" -v newfile="$tmp.new" '
    $0 == s { while ((getline line < newfile) > 0) print line; skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp" "$tmp.new"
}
