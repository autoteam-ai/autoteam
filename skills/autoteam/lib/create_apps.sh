# shellcheck shell=bash
# autoteam github --create-apps：用 GitHub App Manifest 流程创建三个角色的 App。默认只预览。
#
# 流程：为每个角色生成一个本地 HTML 页（带预填权限的表单）→ 人在浏览器里打开并点确认 →
# GitHub 跳转到 redirect_url?code=...&state=... → 人把地址栏里的完整 URL 粘回终端 →
# 用 code 调 POST /app-manifests/{code}/conversions 换回 App ID 和私钥。
#
# 回调用“粘贴 URL”而不是本地监听：不占端口、不依赖 nc/python、macOS bash 3.2 和没有浏览器的
# 远端机器都能用（HTML 拷到有浏览器的机器上打开即可）。redirect_url 指向没人监听的本机端口，
# 浏览器会报连接失败，但地址栏里的 code 已经在了。

AUTOTEAM_APP_ROLES="implementer reviewer planner"
GH_APP_REDIRECT_URL=http://localhost:3000/autoteam-callback

# 各角色的 App 权限（与 docs/setup/github.md 的表一致）
github_app_permissions() {
  case $1 in
    implementer) echo '{"contents":"write","pull_requests":"write","workflows":"write"}' ;;
    reviewer)    echo '{"contents":"write","pull_requests":"write"}' ;;
    planner)     echo '{"actions":"write","contents":"read","pull_requests":"read"}' ;;
    *) die "未知角色：$1" ;;
  esac
}

github_app_conf_key() {
  printf 'AUTOTEAM_%s_APP_ID' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
}

# autoteam.conf（或环境变量）里这个角色已有的 App ID
github_app_conf_value() {
  local key
  key=$(github_app_conf_key "$1")
  printf '%s' "${!key:-}"
}

# 键目录展开 ~（与 gh-app-token.sh 一致）
github_keys_dir() {
  local d=$AUTOTEAM_KEYS_DIR
  # shellcheck disable=SC2088  # pattern 是字面量 ~
  case $d in
    "~") d=$HOME ;;
    "~/"*) d=$HOME/${d#\~/} ;;
  esac
  printf '%s' "$d"
}

# 该角色在 keys 目录里已有的私钥（约定名或名字里带角色名的 .pem），没有则返回 1
github_existing_key() {
  local dir=$1 role=$2 f
  [ -d "$dir" ] || return 1
  for f in "$dir/$role.pem" "$dir"/*"$role"*.pem; do
    [ -e "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

# manifest JSON：不带 webhook，私有 App（只能装在自己账号下）
github_app_manifest() {
  local role=$1 name=$2
  jq -nc --arg name "$name" --arg url "https://github.com/$AUTOTEAM_REPO" --arg redirect "$GH_APP_REDIRECT_URL" \
    --argjson perms "$(github_app_permissions "$role")" \
    '{name: $name, url: $url, redirect_url: $redirect, public: false, default_permissions: $perms, default_events: []}'
}

# 自动提交的表单页：manifest 只是公开的配置，不含任何凭据
github_app_form_html() {
  local action=$1 manifest=$2 role=$3 esc
  esc=$(jq -rn --arg m "$manifest" '$m | @html')
  cat <<EOF
<!doctype html>
<meta charset="utf-8">
<title>autoteam：创建 $role App</title>
<p>正在跳转到 GitHub 创建 <b>$role</b> App。没有自动跳转就点下面的按钮。</p>
<form id="f" method="post" action="$action">
  <input type="hidden" name="manifest" value="$esc">
  <button type="submit">在 GitHub 上创建 $role App</button>
</form>
<script>document.getElementById("f").submit();</script>
EOF
}

# 从粘贴的内容里取 code 和 state。接受完整 URL，或只有 code
github_parse_callback() {
  local input=$1 query
  case $input in
    *\?*) query=${input#*\?}; query=${query%%#*} ;;
    *=*) query=$input ;;
    *) printf '%s\n' "$input"; printf '\n'; return 0 ;;
  esac
  local kv code="" state=""
  for kv in $(printf '%s' "$query" | tr '&' ' '); do
    case $kv in
      code=*) code=${kv#code=} ;;
      state=*) state=${kv#state=} ;;
    esac
  done
  printf '%s\n%s\n' "$code" "$state"
}

# 往 autoteam.conf 写 App ID：只填空值，已有值不动
github_write_app_id() {
  local conf=$1 key=$2 id=$3 tmp
  tmp=$(autoteam_tmpdir)/conf.new
  if grep -q "^$key=" "$conf"; then
    awk -v k="$key" -v v="$id" 'BEGIN{done=0} index($0, k "=") == 1 && !done { print k "=" v; done=1; next } { print }' "$conf" > "$tmp"
  else
    { cat "$conf"; printf '%s=%s\n' "$key" "$id"; } > "$tmp"
  fi
  cat "$tmp" > "$conf"
}

# 换回 App 并落盘。私钥、client secret、webhook secret 只在这个函数里经过，不打印
github_convert_and_store() {
  local role=$1 code=$2 keys_dir=$3 conf=$4 owner=$5 owner_type=$6
  local resp id slug key_path settings
  gh_call POST "app-manifests/$code/conversions" || { fail "$role：用 code 换取 App 失败（code 只能用一次、一小时内有效）：$GH_OUT"; return 1; }
  resp=$GH_OUT
  id=$(jq -r '.id // empty' <<<"$resp")
  slug=$(jq -r '.slug // empty' <<<"$resp")
  if [ -z "$id" ] || [ -z "$slug" ] || ! jq -e '.pem | type == "string" and length > 0' <<<"$resp" >/dev/null; then
    fail "$role：GitHub 返回的内容里缺 id / slug / pem"
    return 1
  fi
  key_path=$keys_dir/$role.pem
  if [ -e "$key_path" ]; then
    fail "$role：$key_path 在等待期间出现了，不覆盖。App 已在 GitHub 上建好（$slug，ID $id），私钥需要到 App 设置页重新生成"
    return 1
  fi
  if [ ! -d "$keys_dir" ]; then
    (umask 077 && mkdir -p "$keys_dir") || { fail "建不了目录 $keys_dir"; return 1; }
  fi
  (umask 077 && jq -r '.pem' <<<"$resp" > "$key_path") || { fail "写不进 $key_path"; return 1; }
  chmod 600 "$key_path"
  github_write_app_id "$conf" "$(github_app_conf_key "$role")" "$id"
  if [ "$owner_type" = Organization ]; then
    settings=https://github.com/organizations/$owner/settings/apps/$slug
  else
    settings=https://github.com/settings/apps/$slug
  fi
  ok "$role App $slug（ID $id）已建好：私钥 $key_path（权限 600），App ID 已写进 $AUTOTEAM_CONF_REL"
  info "设置页：$settings"
  info "下一步安装到仓库（Only select repositories，只选 $AUTOTEAM_REPO）：https://github.com/apps/$slug/installations/new"
}

github_create_apps() {
  local prefix=$1 owner owner_type keys_dir conf role name manifest state action html code_in parsed code got_state
  local pending=0 root
  root=$(pwd)
  conf=$root/$AUTOTEAM_CONF_REL
  [ -f "$conf" ] || die "找不到 $AUTOTEAM_CONF_REL，先运行 autoteam init"
  [ -n "$prefix" ] || prefix=${AUTOTEAM_REPO##*/}

  owner=${AUTOTEAM_REPO%%/*}
  gh_call GET "repos/$AUTOTEAM_REPO" || die "读不到仓库 $AUTOTEAM_REPO：$GH_OUT"
  owner_type=$(jq -r '.owner.type' <<<"$GH_OUT")
  keys_dir=$(github_keys_dir)

  section "创建 GitHub App（manifest 流程）"
  info "App 归属：$( [ "$owner_type" = Organization ] && printf '组织 %s' "$owner" || printf '当前登录的个人账号' )；私钥目录：$keys_dir"
  info "只创建 App，不安装：装到仓库还要你在 App 的 Install 页面点一次（只选 $AUTOTEAM_REPO）"

  for role in $AUTOTEAM_APP_ROLES; do
    name=$prefix-$role
    if github_existing_key "$keys_dir" "$role" >/dev/null; then
      info "$role：$keys_dir 里已有私钥，跳过（不覆盖）"
      continue
    fi
    if [ -n "$(github_app_conf_value "$role")" ]; then
      warn "$role：autoteam.conf 已有 $(github_app_conf_key "$role")，但 $keys_dir 里没有私钥，不重复建 App"
      hint "到该 App 的设置页 Generate a private key，把 .pem 放进 $keys_dir/$role.pem（chmod 600）"
      continue
    fi
    pending=$((pending + 1))
    planned "创建 App $name（$role）：权限 $(github_app_permissions "$role")；私钥写入 $keys_dir/$role.pem"
  done

  if [ "$pending" = 0 ]; then
    ok "没有需要新建的 App"
    preview_footer
    return 0
  fi
  if [ "$AUTOTEAM_APPLY" != 1 ]; then
    hint "--apply 后会为每个角色生成一个表单页，你在浏览器里点确认，再把跳转后的地址栏 URL 粘回来"
    preview_footer
    return 0
  fi

  for role in $AUTOTEAM_APP_ROLES; do
    github_existing_key "$keys_dir" "$role" >/dev/null && continue
    [ -z "$(github_app_conf_value "$role")" ] || continue
    name=$prefix-$role
    manifest=$(github_app_manifest "$role" "$name")
    state=$role-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
    if [ "$owner_type" = Organization ]; then
      action="https://github.com/organizations/$owner/settings/apps/new?state=$state"
    else
      action="https://github.com/settings/apps/new?state=$state"
    fi
    html=$(autoteam_tmpdir)/create-$role.html
    github_app_form_html "$action" "$manifest" "$role" > "$html"

    section "$role App"
    info "1. 在有浏览器的机器上打开这个文件（远端机器先把它拷过去）：$html"
    info "2. 在 GitHub 页面确认名称（$name 被占用时改一个）、点 Create GitHub App"
    info "3. 页面会跳到 $GH_APP_REDIRECT_URL?code=...，浏览器显示连接失败是正常的；把地址栏里的完整 URL 粘到这里"
    printf '  URL> '
    code_in=""
    IFS= read -r code_in || true
    code_in=$(trim "$code_in")
    if [ -z "$code_in" ]; then
      fail "$role：没有收到 URL，跳过（重新运行 --apply 会从这个角色接着来）"
      continue
    fi
    parsed=$(github_parse_callback "$code_in")
    code=$(printf '%s\n' "$parsed" | sed -n 1p)
    got_state=$(printf '%s\n' "$parsed" | sed -n 2p)
    if [ -n "$got_state" ] && [ "$got_state" != "$state" ]; then
      fail "$role：URL 里的 state 与这次创建的不一致（可能粘错了角色的 URL），跳过"
      continue
    fi
    [ -n "$code" ] || { fail "$role：URL 里没有 code 参数"; continue; }
    github_convert_and_store "$role" "$code" "$keys_dir" "$conf" "$owner" "$owner_type" || true
  done
  hint "装好后运行 autoteam github 核对安装状态和权限，再运行 autoteam doctor 检查私钥"
}
