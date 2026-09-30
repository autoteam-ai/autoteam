# shellcheck shell=bash
# autoteam github --create-apps：用 GitHub App Manifest 流程创建三个角色的 App。默认只预览。
# 每个角色：本地 HTML 表单 → 人在浏览器点确认 → 跳到 redirect_url?code=&state= → 人把完整 URL 粘回终端 →
# 用 code 换回 App ID 和私钥。用“粘贴 URL”而不是本地监听，不占端口，bash 3.2 和无浏览器的远端机器都能用。

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

github_app_conf_key() { printf 'AUTOTEAM_%s_APP_ID' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; }

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

# 校验粘贴的回调 URL 并取出 code：必须是完整的回调 URL（以 redirect_url 开头），
# 带 code 和 state，且 state 与本轮、本角色生成的一致。成功时 code 打到 stdout，失败时把原因打到 stderr 并返回 1
github_callback_code() {
  local input=$1 want_state=$2 query kv code="" state="" re='^[A-Za-z0-9_-]+$'
  case $input in
    "$GH_APP_REDIRECT_URL"\?*) query=${input#*\?}; query=${query%%#*} ;;
    *) echo "不是完整的回调 URL（应以 $GH_APP_REDIRECT_URL?code= 开头，裸 code 不接受）" >&2; return 1 ;;
  esac
  for kv in $(printf '%s' "$query" | tr '&' ' '); do
    case $kv in
      code=*) code=${kv#code=} ;;
      state=*) state=${kv#state=} ;;
    esac
  done
  [ -n "$state" ] || { echo "URL 里没有 state 参数" >&2; return 1; }
  [ "$state" = "$want_state" ] || { echo "URL 里的 state 与这次创建的不一致（可能粘了另一轮或另一个角色的 URL）" >&2; return 1; }
  [[ $code =~ $re ]] || { echo "URL 里没有有效的 code 参数" >&2; return 1; }
  printf '%s' "$code"
}

# 往 autoteam.conf 写 App ID：有该键就替换第一处，没有就追加；每一步都检查，最后读回确认
github_write_app_id() {
  local conf=$1 key=$2 id=$3 tmp
  tmp=$(autoteam_tmpdir)/conf.new
  if grep -q "^$key=" "$conf"; then
    awk -v k="$key" -v v="$id" 'BEGIN{done=0} index($0, k "=") == 1 && !done { print k "=" v; done=1; next } { print }' "$conf" > "$tmp" || return 1
  else
    { cat "$conf" && printf '%s=%s\n' "$key" "$id"; } > "$tmp" || return 1
  fi
  cat "$tmp" > "$conf" || return 1
  [ "$(grep -m1 "^$key=" "$conf")" = "$key=$id" ]
}

# 换回 App 并落盘。私钥、client secret、webhook secret 只在这个函数里经过，不打印
github_convert_and_store() {
  local role=$1 code=$2 keys_dir=$3 conf=$4 owner=$5 owner_type=$6
  local resp id slug key_path settings conf_key recover
  if [ "$owner_type" = Organization ]; then
    settings=https://github.com/organizations/$owner/settings/apps
  else
    settings=https://github.com/settings/apps
  fi
  gh_call POST "app-manifests/$code/conversions" || { fail "$role：用 code 换取 App 失败（code 只能用一次、一小时内有效）：$GH_OUT"; return 1; }
  resp=$GH_OUT
  id=$(jq -r '.id // empty' <<<"$resp")
  slug=$(jq -r '.slug // empty' <<<"$resp")
  if [ -z "$id" ] || [ -z "$slug" ] || ! jq -e '.pem | type == "string" and length > 0' <<<"$resp" >/dev/null; then
    fail "$role：GitHub 返回的内容里缺 id / slug / pem"
    return 1
  fi
  key_path=$keys_dir/$role.pem
  conf_key=$(github_app_conf_key "$role")
  # 到这里 code 已经被消费、App 已经建好，任何一步失败都要给出恢复办法
  recover="App 已在 GitHub 上建好：$slug（ID $id）。恢复：到 $settings/$slug 的 Private keys 点 Generate a private key，把 .pem 存为 $key_path（chmod 600），并把 $conf_key=$id 写进 $AUTOTEAM_CONF_REL"
  if [ ! -d "$keys_dir" ] && ! (umask 077 && mkdir -p "$keys_dir"); then
    fail "$role：建不了目录 $keys_dir。$recover"
    return 1
  fi
  # noclobber：文件已存在（包括等待期间才出现的）时这一步失败，绝不覆盖
  if ! (umask 077 && set -C && jq -r '.pem' <<<"$resp" > "$key_path") 2>/dev/null; then
    fail "$role：写不进 $key_path（已存在或目录不可写），没有覆盖任何文件。$recover"
    return 1
  fi
  if ! chmod 600 "$key_path" || [ ! -s "$key_path" ]; then
    rm -f "$key_path"
    fail "$role：私钥文件权限设置或写入不完整，已删除该文件。$recover"
    return 1
  fi
  if ! github_write_app_id "$conf" "$conf_key" "$id"; then
    fail "$role：私钥已写入 $key_path，但 App ID 没能写进 $AUTOTEAM_CONF_REL（文件只读？）。手工加一行 $conf_key=$id 即可；App 是 $slug"
    return 1
  fi
  settings=$settings/$slug
  ok "$role App $slug（ID $id）已建好：私钥 $key_path（权限 600），App ID 已写进 $AUTOTEAM_CONF_REL"
  info "设置页：$settings"
  info "下一步安装到仓库（Only select repositories，只选 $AUTOTEAM_REPO）：https://github.com/apps/$slug/installations/new"
}

github_create_apps() {
  local prefix=$1 owner owner_type keys_dir conf role name manifest state action html code_in code
  local pending=0 root failed=0
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
    state=$role-${AUTOTEAM_APP_STATE_NONCE:-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')}
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
      failed=$((failed + 1))
      continue
    fi
    if ! code=$(github_callback_code "$code_in" "$state" 2>"$(autoteam_tmpdir)/cb.err"); then
      fail "$role：$(cat "$(autoteam_tmpdir)/cb.err")，跳过（重新运行 --apply 会从这个角色接着来）"
      failed=$((failed + 1))
      continue
    fi
    github_convert_and_store "$role" "$code" "$keys_dir" "$conf" "$owner" "$owner_type" || failed=$((failed + 1))
  done
  hint "装好后运行 autoteam github 核对安装状态和权限，再运行 autoteam doctor 检查私钥"
  [ "$failed" = 0 ] || return 1
}
