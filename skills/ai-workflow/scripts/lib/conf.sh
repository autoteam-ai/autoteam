# shellcheck shell=bash
# ops/agents/aiwf.conf 的读取。格式：每行 KEY=VALUE，# 开头是注释，不支持行尾注释和变量展开。
# 环境变量优先于文件，方便临时覆盖（例如 AIWF_REPO=acme/shop aiwf github）。

AIWF_CONF_REL=ops/agents/aiwf.conf

# 所有配置项和默认值（init 渲染模板时也用这张表）
aiwf_conf_defaults() {
  cat <<'EOF'
AIWF_REPO=
AIWF_DEFAULT_BRANCH=main
AIWF_OWNER=
AIWF_IMPL_BOT=
AIWF_REVIEW_BOT=
AIWF_PLANNER_BOT=
AIWF_MULTICA_WORKSPACE=
AIWF_MULTICA_PROJECT=
AIWF_HUMAN=
AIWF_AGENT_ACCESS=private
AIWF_ISSUE_PREFIX=MUL
AIWF_CHECK_NAME=check
AIWF_PR_MAX_LINES=400
AIWF_MAX_REVIEW_REJECTIONS=2
AIWF_MAX_ACCEPTANCE_FAILURES=2
AIWF_DEPLOY_ENVIRONMENT=production
AIWF_TIMEZONE=Asia/Shanghai
EOF
}

# 读取一个 KEY=VALUE 文件；只设置还没有值的变量（环境变量优先）
conf_load_file() {
  local file=$1 line key val re_skip='^[[:space:]]*(#|$)' re_key='^AIWF_[A-Z0-9_]+$'
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ $re_skip ]] && continue
    case $line in *=*) ;; *) continue ;; esac
    key=$(trim "${line%%=*}")
    val=$(trim "${line#*=}")
    [[ $key =~ $re_key ]] || continue
    case $val in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    if [ -z "${!key+x}" ]; then
      printf -v "$key" '%s' "$val"
    fi
  done < "$file"
}

# 加载仓库配置，再用默认值补齐
conf_load() {
  local root=${1:-$(repo_root)}
  conf_load_file "$root/$AIWF_CONF_REL"
  local line key val
  while IFS= read -r line; do
    key=${line%%=*}
    val=${line#*=}
    if [ -z "${!key+x}" ]; then
      printf -v "$key" '%s' "$val"
    fi
  done <<EOF
$(aiwf_conf_defaults)
EOF
}

conf_exists() { [ -f "${1:-$(repo_root)}/$AIWF_CONF_REL" ]; }
