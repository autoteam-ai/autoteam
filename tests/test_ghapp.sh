# shellcheck shell=bash
# gh-app-token.sh：铸 token、缓存、git 身份和凭据。
# 这个脚本是"写代码的不能评审自己"的落地方式——Implementer 和 Reviewer 是两个不同的
# GitHub App，所以它出问题等于整条硬约束失效，用例要覆盖到每种模式。

# RSA 私钥在整次 run.sh 里只生成一次（各用例共享 result_dir），先写临时文件再原子改名，
# 并行的 worker 不会读到写了一半的私钥
ghapp_test_key() {
  APP_PEM=${result_dir:-$TEST_BASE}/app.pem
  if [ ! -f "$APP_PEM" ]; then
    openssl genrsa -out "$APP_PEM.$$" 2048 2>/dev/null && mv -f "$APP_PEM.$$" "$APP_PEM"
  fi
}

# 建一个配好 App 的仓库
ghapp_repo() {
  new_repo acme/shop
  mkdir -p .autoteam/scripts .autoteam/local
  cp "$TPL/autoteam/scripts/gh-app-token.sh" .autoteam/scripts/
  chmod +x .autoteam/scripts/gh-app-token.sh
  printf 'AUTOTEAM_REPO=acme/shop\nAUTOTEAM_IMPLEMENTER_APP_ID=111\n' > .autoteam/autoteam.conf
  ghapp_test_key
  cp "$APP_PEM" .autoteam/local/implementer.pem
  mkdir -p "$WORK/.cache"
}

ghapp() {
  env PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" \
    HOME="$WORK/.home" NO_COLOR=1 XDG_CACHE_HOME="$WORK/.cache" \
    STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" \
    bash .autoteam/scripts/gh-app-token.sh "$@"
}

# 铸 token、缓存、git 凭据助手、--run：同一个仓库顺序走完，token 缓存让后面的调用不再重铸
t_ghapp_mints_caches_and_serves_token() {
  ghapp_repo
  out=$(ghapp implementer)
  assert_eq "$out" "ghs_stubtoken" "应该拿到 installation token"
  assert_log "JWT segments=3"
  assert_log "BODY POST access_tokens"
  before=$(grep -c "BODY POST access_tokens" "$STUB_LOG")

  out=$(ghapp implementer)
  assert_eq "$out" "ghs_stubtoken"

  out=$(ghapp --credential implementer get </dev/null)
  assert_contains "$out" "username=x-access-token"
  assert_contains "$out" "password=ghs_stubtoken"
  # store / erase 不该有输出，也不该报错
  out=$(ghapp --credential implementer store </dev/null)
  assert_eq "$out" "" "store 应该静默"

  printf '#!/usr/bin/env bash\necho "TOKEN=${GH_TOKEN:-none}"\nexit 7\n' > fake-gh
  chmod +x fake-gh
  out=$(ghapp --run implementer ./fake-gh) ; rc=$?
  assert_contains "$out" "TOKEN=ghs_stubtoken" "--run 要把 token 传进子命令"
  assert_eq "$rc" 7 "子命令的退出码要透传"

  after=$(grep -c "BODY POST access_tokens" "$STUB_LOG")
  assert_eq "$after" "$before" "token 没过期时不该重铸"
}

# 这些都在铸 token 之前就失败，不碰网络
# agent 每次工具调用都是新 shell，所以必须是 --run 这种随命令走的方式
t_ghapp_rejects_bad_usage() {
  ghapp_repo
  out=$(ghapp --run implementer 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "后面要跟要执行的命令"
  out=$(ghapp auditor 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "角色只能是"
  out=$(ghapp reviewer 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "AUTOTEAM_REVIEWER_APP_ID" "没配 App ID 要说清楚缺哪个键"
}

# --identity 和 --setup-git 共用身份查询；请求都要带超时、凭据走 stdin
t_ghapp_identity_and_setup_git() {
  ghapp_repo
  out=$(AUTOTEAM_GH_CONNECT_TIMEOUT=2 AUTOTEAM_GH_MAX_TIME=3 ghapp --identity implementer)
  assert_contains "$out" "acme-impl[bot]"
  assert_contains "$out" "4242+acme-impl[bot]@users.noreply.github.com"
  assert_eq "$(grep -c 'curl connect-timeout=2' "$STUB_LOG")" 3
  assert_eq "$(grep -c 'curl max-time=3' "$STUB_LOG")" 3
  assert_eq "$(grep -c 'curl auth-stdin' "$STUB_LOG")" 3

  # 模拟机器上已有的全局凭据助手：不清掉它，agent 会以人的身份推代码
  git config --local credential.helper "osxkeychain"
  ghapp --setup-git implementer >/dev/null
  assert_eq "$(git config --get user.name)" "acme-impl[bot]"
  assert_eq "$(git config --get user.email)" "4242+acme-impl[bot]@users.noreply.github.com"
  first=$(git config --local --get-all credential.helper | head -n 1)
  assert_eq "$first" "" "第一个助手要是空串，用来清掉继承来的凭据助手"
  assert_contains "$(git config --local --get-all credential.helper | tail -n 1)" "--credential implementer"

  # Multica 托管 checkout 的 config.worktree 里带着人的身份，比 --local 优先：必须写 worktree 级
  git config --local extensions.worktreeConfig true
  git config --worktree user.name "Human"
  git config --worktree user.email "human@example.com"
  ghapp --setup-git implementer >/dev/null
  assert_eq "$(git config --get user.name)" "acme-impl[bot]"
  assert_eq "$(git config --get user.email)" "4242+acme-impl[bot]@users.noreply.github.com"
}

# agent 每次 checkout 都是新目录，私钥只放仓库里就要跟着重放一遍——真机上两个
# Implementer 就是这么同时卡住的。仓库里没有时要能回退到机器上的固定目录。
# 每一步都先清 token 缓存，否则命中缓存就根本不读私钥了。
t_ghapp_key_lookup_order() {
  ghapp_repo
  mkdir -p "$WORK/.home/machine-keys"
  printf 'AUTOTEAM_KEYS_DIR=~/machine-keys\n' >> .autoteam/autoteam.conf
  # 仓库里的私钥优先于机器级目录：机器级目录里放个坏的，被选中就会铸不出来
  : > "$WORK/.home/machine-keys/implementer.pem"
  out=$(ghapp implementer 2>&1)
  assert_eq "$out" "ghs_stubtoken" "仓库里的私钥优先于机器级目录"

  rm -rf "$WORK/.cache" .autoteam/local/implementer.pem "$WORK/.home/machine-keys/implementer.pem"
  cp "$APP_PEM" "$WORK/.home/machine-keys/autoteam-implementer.2026-01-01.private-key.pem"
  out=$(ghapp implementer 2>&1) ; rc=$?
  assert_eq "$rc" 0 "$out"
  assert_eq "$out" "ghs_stubtoken" "机器级目录里的私钥也要能铸出 token"

  rm -rf "$WORK/.cache" "$WORK/.home/machine-keys"
  out=$(ghapp implementer 2>&1) ; rc=$?
  assert_eq "$rc" 1
  assert_contains "$out" "找不到 implementer 的私钥"
  assert_contains "$out" ".autoteam/local/" "要说清两个位置都找过了"
  assert_contains "$out" "machine-keys"
}

t_ghapp_timeout_and_private_process_arguments() {
  ghapp_repo
  mkdir -p "$WORK/bin"
  # 仅替换目的地址，真正的 curl 负责超时和 stdin 头处理。
  cat > "$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
args=("${@:1:$#-1}")
printf '%s' "$$" > "$STUB_STATE/curl-pid"
exec /usr/bin/curl "${args[@]}" --noproxy '*' "http://127.0.0.1:$TEST_PORT"
SH
  chmod +x "$WORK/bin/curl"
  out=$(python3 - <<'PY'
import os
import socket
import subprocess
import threading
import time

server = socket.socket()
server.bind(('127.0.0.1', 0))
server.listen()
received = []

def stall():
    conn, _ = server.accept()
    with conn:
        received.append(conn.recv(8192))
        time.sleep(1)

thread = threading.Thread(target=stall, daemon=True)
thread.start()
env = dict(os.environ, PATH=os.getcwd() + '/bin:' + os.environ['PATH'],
           XDG_CACHE_HOME=os.getcwd() + '/.cache',
           TEST_PORT=str(server.getsockname()[1]),
           AUTOTEAM_GH_CONNECT_TIMEOUT='0.2', AUTOTEAM_GH_MAX_TIME='0.5')
start = time.monotonic()
proc = subprocess.Popen(['bash', '.autoteam/scripts/gh-app-token.sh', 'implementer'],
                        env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    deadline = start + 3
    while not received and time.monotonic() < deadline:
        time.sleep(0.01)
    assert received, '本地服务器未收到请求'
    pid = open(os.environ['STUB_STATE'] + '/curl-pid').read()
    args = open('/proc/' + pid + '/cmdline', 'rb').read()
    auth = received[0].split(b'Authorization: Bearer ')[1].split(b'\r\n')[0]
    assert b'Authorization' not in args and auth not in args, '进程参数泄露凭据'
    stdout, stderr = proc.communicate(timeout=3)
    assert proc.returncode != 0 and not stdout
    assert '调用 GitHub 超时'.encode() in stderr, stderr
    assert time.monotonic() - start < 3, '未在规定时间内返回'
    print('真实 curl 超时且进程参数无凭据')
finally:
    if proc.poll() is None:
        proc.kill()
    proc.communicate()
    server.close()
PY
  ) ; rc=$?
  assert_eq "$rc" 0 "$out"
  assert_contains "$out" '真实 curl 超时且进程参数无凭据'
}
