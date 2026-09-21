# shellcheck shell=bash
# gh-app-token.sh：铸 token、缓存、git 身份和凭据。
# 这个脚本是"写代码的不能评审自己"的落地方式——Implementer 和 Reviewer 是两个不同的
# GitHub App，所以它出问题等于整条硬约束失效，用例要覆盖到每种模式。

# 建一个配好 App 的仓库；RSA 私钥只生成一次，之后各用例复用
ghapp_repo() {
  new_repo acme/shop
  mkdir -p ops/agents/scripts ops/agents/local
  cp "$TPL/ops/agents/scripts/gh-app-token.sh" ops/agents/scripts/
  chmod +x ops/agents/scripts/gh-app-token.sh
  printf 'AUTOTEAM_REPO=acme/shop\nAUTOTEAM_IMPLEMENTER_APP_ID=111\n' > ops/agents/autoteam.conf
  if [ ! -f "$TEST_BASE/app.pem" ]; then
    openssl genrsa -out "$TEST_BASE/app.pem" 2048 2>/dev/null
  fi
  cp "$TEST_BASE/app.pem" ops/agents/local/implementer.pem
  mkdir -p "$WORK/.cache"
}

ghapp() {
  env PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" \
    HOME="$WORK/.home" NO_COLOR=1 XDG_CACHE_HOME="$WORK/.cache" \
    STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" \
    bash ops/agents/scripts/gh-app-token.sh "$@"
}

t_ghapp_mints_token_with_valid_jwt() {
  ghapp_repo
  out=$(ghapp implementer)
  assert_eq "$out" "ghs_stubtoken" "应该拿到 installation token"
  assert_log "JWT segments=3"
  assert_log "BODY POST access_tokens"
}

t_ghapp_reuses_cached_token() {
  ghapp_repo
  ghapp implementer >/dev/null
  before=$(grep -c "BODY POST access_tokens" "$STUB_LOG")
  out=$(ghapp implementer)
  after=$(grep -c "BODY POST access_tokens" "$STUB_LOG")
  assert_eq "$out" "ghs_stubtoken"
  assert_eq "$after" "$before" "token 没过期时不该重铸"
}

t_ghapp_credential_helper_speaks_git_protocol() {
  ghapp_repo
  out=$(ghapp --credential implementer get </dev/null)
  assert_contains "$out" "username=x-access-token"
  assert_contains "$out" "password=ghs_stubtoken"
  # store / erase 不该有输出，也不该报错
  out=$(ghapp --credential implementer store </dev/null)
  assert_eq "$out" "" "store 应该静默"
}

t_ghapp_run_injects_identity_and_passes_exit_code() {
  ghapp_repo
  printf '#!/usr/bin/env bash\necho "TOKEN=${GH_TOKEN:-none}"\nexit 7\n' > fake-gh
  chmod +x fake-gh
  out=$(ghapp --run implementer ./fake-gh) ; rc=$?
  assert_contains "$out" "TOKEN=ghs_stubtoken" "--run 要把 token 传进子命令"
  assert_eq "$rc" 7 "子命令的退出码要透传"
}

# agent 每次工具调用都是新 shell，所以必须是 --run 这种随命令走的方式
t_ghapp_run_without_command_fails() {
  ghapp_repo
  out=$(ghapp --run implementer 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "后面要跟要执行的命令"
}

t_ghapp_setup_git_sets_bot_identity() {
  ghapp_repo
  # 模拟机器上已有的全局凭据助手：不清掉它，agent 会以人的身份推代码
  git config --local credential.helper "osxkeychain"
  ghapp --setup-git implementer >/dev/null
  assert_eq "$(git config --get user.name)" "acme-impl[bot]"
  assert_eq "$(git config --get user.email)" "4242+acme-impl[bot]@users.noreply.github.com"
  first=$(git config --local --get-all credential.helper | head -n 1)
  assert_eq "$first" "" "第一个助手要是空串，用来清掉继承来的凭据助手"
  assert_contains "$(git config --local --get-all credential.helper | tail -n 1)" "--credential implementer"
}

# Multica 托管 checkout 的 config.worktree 里带着人的身份，比 --local 优先：必须写 worktree 级
t_ghapp_setup_git_overrides_worktree_identity() {
  ghapp_repo
  git config --local extensions.worktreeConfig true
  git config --worktree user.name "Human"
  git config --worktree user.email "human@example.com"
  ghapp --setup-git implementer >/dev/null
  assert_eq "$(git config --get user.name)" "acme-impl[bot]"
  assert_eq "$(git config --get user.email)" "4242+acme-impl[bot]@users.noreply.github.com"
}

t_ghapp_identity_prints_name_and_email() {
  ghapp_repo
  out=$(ghapp --identity implementer)
  assert_contains "$out" "acme-impl[bot]"
  assert_contains "$out" "4242+acme-impl[bot]@users.noreply.github.com"
}

t_ghapp_rejects_bad_role_and_missing_config() {
  ghapp_repo
  out=$(ghapp auditor 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "角色只能是"
  out=$(ghapp reviewer 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "AUTOTEAM_REVIEWER_APP_ID" "没配 App ID 要说清楚缺哪个键"
}

# agent 每次 checkout 都是新目录，私钥只放仓库里就要跟着重放一遍——真机上两个
# Implementer 就是这么同时卡住的。仓库里没有时要能回退到机器上的固定目录。
t_ghapp_falls_back_to_keys_dir() {
  ghapp_repo
  rm -f ops/agents/local/implementer.pem
  mkdir -p "$WORK/.home/machine-keys"
  cp "$TEST_BASE/app.pem" "$WORK/.home/machine-keys/autoteam-implementer.2026-01-01.private-key.pem"
  printf 'AUTOTEAM_KEYS_DIR=~/machine-keys\n' >> ops/agents/autoteam.conf
  out=$(ghapp implementer 2>&1) ; rc=$?
  assert_eq "$rc" 0 "$out"
  assert_eq "$out" "ghs_stubtoken" "机器级目录里的私钥也要能铸出 token"
}

t_ghapp_prefers_repo_key_over_keys_dir() {
  ghapp_repo
  mkdir -p "$WORK/.home/machine-keys"
  : > "$WORK/.home/machine-keys/implementer.pem"   # 坏的私钥，被选中就会铸不出来
  printf 'AUTOTEAM_KEYS_DIR=~/machine-keys\n' >> ops/agents/autoteam.conf
  out=$(ghapp implementer 2>&1)
  assert_eq "$out" "ghs_stubtoken" "仓库里的私钥优先于机器级目录"
}

t_ghapp_reports_all_searched_locations() {
  ghapp_repo
  rm -f ops/agents/local/implementer.pem
  printf 'AUTOTEAM_KEYS_DIR=~/machine-keys\n' >> ops/agents/autoteam.conf
  out=$(ghapp implementer 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "找不到 implementer 的私钥"
  assert_contains "$out" "ops/agents/local/" "要说清两个位置都找过了"
  assert_contains "$out" "machine-keys"
}
