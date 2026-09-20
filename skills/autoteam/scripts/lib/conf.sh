# shellcheck shell=bash
# ops/agents/autoteam.conf 的读取。格式：每行 KEY=VALUE，# 开头是注释，不支持行尾注释和变量展开。
# 环境变量优先于文件，方便临时覆盖（例如 AUTOTEAM_REPO=acme/shop autoteam github）。

AUTOTEAM_CONF_REL=ops/agents/autoteam.conf

# 所有配置项和默认值（init 渲染模板时也用这张表）
autoteam_conf_defaults() {
  cat <<'EOF'
AUTOTEAM_REPO=
AUTOTEAM_DEFAULT_BRANCH=main
AUTOTEAM_OWNER=
AUTOTEAM_IMPLEMENTER_APP_ID=
AUTOTEAM_REVIEWER_APP_ID=
AUTOTEAM_PLANNER_APP_ID=
AUTOTEAM_MULTICA_WORKSPACE=
AUTOTEAM_MULTICA_PROJECT=
AUTOTEAM_HUMAN=
AUTOTEAM_AGENT_ACCESS=private
AUTOTEAM_ISSUE_PREFIX=MUL
AUTOTEAM_CHECK_NAME=check
AUTOTEAM_PR_MAX_LINES=400
AUTOTEAM_MAX_REVIEW_REJECTIONS=2
AUTOTEAM_MAX_ACCEPTANCE_FAILURES=2
AUTOTEAM_DEPLOY_ENVIRONMENT=production
AUTOTEAM_TIMEZONE=Asia/Shanghai
EOF
}

# 读取一个 KEY=VALUE 文件；只设置还没有值的变量（环境变量优先）。
# 同一个键出现多次时第一条生效——ops/agents/scripts/ 下的脚本也要按这个规则读（head -n 1）。
conf_load_file() {
  local file=$1 line key val re_skip='^[[:space:]]*(#|$)' re_key='^AUTOTEAM_[A-Z0-9_]+$'
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
  conf_load_file "$root/$AUTOTEAM_CONF_REL"
  local line key val
  while IFS= read -r line; do
    key=${line%%=*}
    val=${line#*=}
    if [ -z "${!key+x}" ]; then
      printf -v "$key" '%s' "$val"
    fi
  done <<EOF
$(autoteam_conf_defaults)
EOF
}

conf_exists() { [ -f "${1:-$(repo_root)}/$AUTOTEAM_CONF_REL" ]; }
