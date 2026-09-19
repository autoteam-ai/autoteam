# shellcheck shell=bash
# ops/agents/registry.yaml 的解析。
# 只解析 agents: 段，而且要求每个 agent 写成一行 flow 映射：
#   impl-claude: { role: implementer, account: claude-max, runtime: claude@machine-a, model: default, max_tasks: 2 }
# 输出制表符分隔：name role account runtime model max_tasks mcp env_file（缺省字段输出 -）

AIWF_REGISTRY_REL=ops/agents/registry.yaml

registry_agents() {
  local file=${1:-$(repo_root)/$AIWF_REGISTRY_REL}
  [ -f "$file" ] || die "找不到 $AIWF_REGISTRY_REL，先运行 aiwf init"
  awk '
    function t(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[^ \t#]/ { insec = ($0 ~ /^agents:[ \t]*(#.*)?$/); next }
    !insec { next }
    /^[ \t]*(#|$)/ { next }
    {
      line = $0
      if (line !~ /^[ \t]+[A-Za-z0-9_.-]+:[ \t]*\{.*\}[ \t]*(#.*)?$/) {
        printf "!\t%s\n", t(line)
        next
      }
      name = t(line); sub(/:.*/, "", name)
      body = line; sub(/^[^{]*\{/, "", body); sub(/\}[^}]*$/, "", body)
      split("", kv)
      n = split(body, parts, ",")
      for (i = 1; i <= n; i++) {
        k = parts[i]; sub(/:.*/, "", k); k = t(k)
        v = parts[i]; if (index(v, ":") == 0) continue
        sub(/^[^:]*:/, "", v); v = t(v)
        gsub(/^["\047]|["\047]$/, "", v)
        kv[k] = v
      }
      printf "%s", name
      split("role account runtime model max_tasks mcp env_file", keys, " ")
      for (i = 1; i <= 7; i++) printf "\t%s", ((keys[i] in kv) && kv[keys[i]] != "" ? kv[keys[i]] : "-")
      printf "\n"
    }
  ' "$file"
}

# 校验注册表；有问题时打印并返回非 0
registry_validate() {
  local rows=$1 bad=0 name role runtime max seen_names=" " n_impl=0 n_rev=0 n_plan=0 n_aud=0
  while IFS=$'\t' read -r name role _ runtime _ max _; do
    [ -n "$name" ] || continue
    if [ "$name" = "!" ]; then
      fail "registry.yaml 里这一行不是单行 flow 映射，aiwf 读不了：$role"
      bad=1; continue
    fi
    case $role in
      planner) n_plan=$((n_plan + 1)) ;;
      implementer) n_impl=$((n_impl + 1)) ;;
      reviewer) n_rev=$((n_rev + 1)) ;;
      auditor) n_aud=$((n_aud + 1)) ;;
      *) fail "agent $name 的 role 不对：$role（应为 planner / implementer / reviewer / auditor）"; bad=1 ;;
    esac
    if [ "$runtime" = "-" ]; then fail "agent $name 没写 runtime"; bad=1; fi
    case $max in -|[1-9]|[1-4][0-9]|50) ;; *) fail "agent $name 的 max_tasks 应为 1-50：$max"; bad=1 ;; esac
    case $seen_names in *" $name "*) fail "agent 名重复：$name"; bad=1 ;; esac
    seen_names="$seen_names$name "
  done <<EOF
$rows
EOF
  [ "$n_plan" -eq 1 ] || { fail "需要正好 1 个 planner，现在 $n_plan 个"; bad=1; }
  [ "$n_aud" -le 1 ] || { fail "auditor 最多 1 个，现在 $n_aud 个"; bad=1; }
  [ "$n_impl" -ge 1 ] || { fail "至少要 1 个 implementer"; bad=1; }
  [ "$n_rev" -ge 1 ] || { fail "至少要 1 个 reviewer"; bad=1; }
  return $bad
}

# 按角色取唯一 agent 名（planner / auditor）
registry_agent_by_role() {
  local rows=$1 want=$2
  printf '%s\n' "$rows" | awk -F'\t' -v r="$want" '$2 == r {print $1; exit}'
}
