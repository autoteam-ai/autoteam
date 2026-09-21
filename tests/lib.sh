# shellcheck shell=bash
# 极简测试框架：test_*.sh 里定义 t_ 开头的函数，run.sh 逐个在子 shell 里执行。

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$TESTS_DIR/.." && pwd)
AUTOTEAM=$ROOT/bin/autoteam
TPL=$ROOT/skills/autoteam/assets/templates
REAL_JQ_DIR=$(dirname "$(command -v jq)")
REAL_GIT_DIR=$(dirname "$(command -v git)")

T_FAILS=0
# 所有临时仓库都建在这个目录下，run.sh 结束时删除
TEST_BASE=${TEST_BASE:-$(mktemp -d "${TMPDIR:-/tmp}/autoteam-tests.XXXXXX")}

tfail() { printf '      ✗ %s\n' "$*"; T_FAILS=$((T_FAILS + 1)); }
assert_eq() { [ "$1" = "$2" ] || tfail "${3:-值不相等}：得到 [$1]，期望 [$2]"; }
assert_contains() { case $1 in *"$2"*) ;; *) tfail "${3:-输出里应包含} [$2]" ;; esac; }
assert_not_contains() { case $1 in *"$2"*) tfail "${3:-输出里不应包含} [$2]" ;; esac; }
assert_file() { [ -f "$1" ] || tfail "文件不存在：$1"; }
assert_no_file() { [ ! -e "$1" ] || tfail "文件不应存在：$1"; }
assert_file_contains() { grep -qF -- "$2" "$1" 2>/dev/null || tfail "$1 应包含 [$2]"; }
assert_log() { grep -qF -- "$1" "$STUB_LOG" 2>/dev/null || tfail "桩调用记录里应有 [$1]"; }
assert_no_log() { ! grep -qF -- "$1" "$STUB_LOG" 2>/dev/null || tfail "桩调用记录里不应有 [$1]"; }

# 新建临时 git 仓库并进入；参数是 owner/name
new_repo() {
  WORK=$(mktemp -d "$TEST_BASE/repo.XXXXXX")
  cd "$WORK" || exit 1
  git init -q -b main
  git config user.email tester@example.com
  git config user.name tester
  git remote add origin "https://github.com/${1:-acme/shop}.git"
  STUB_LOG=$WORK/.stub/log
  STUB_STATE=$WORK/.stub
  mkdir -p "$STUB_STATE" "$WORK/.home"
  export STUB_LOG STUB_STATE
}

# 带桩运行 autoteam：gh / multica / curl 都换成 tests/stubs 下的桩。
# 宿主的 MULTICA_SERVER_URL / MULTICA_TOKEN（agent runtime 里有）不能漏进来；要测环境变量
# 凭据就设 TEST_MULTICA_SERVER_URL / TEST_MULTICA_TOKEN。
autoteam_stub() {
  env -u MULTICA_SERVER_URL -u MULTICA_TOKEN \
    ${TEST_MULTICA_SERVER_URL:+MULTICA_SERVER_URL="$TEST_MULTICA_SERVER_URL"} \
    ${TEST_MULTICA_TOKEN:+MULTICA_TOKEN="$TEST_MULTICA_TOKEN"} \
    PATH="$TESTS_DIR/stubs:$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" \
    HOME="$WORK/.home" NO_COLOR=1 \
    STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" STUB_FIXTURES="$TESTS_DIR/fixtures" \
    STUB_SCENARIO="${STUB_SCENARIO:-user-public}" STUB_FAILED_RUN="${STUB_FAILED_RUN:-}" \
    STUB_AGENT_GET="${STUB_AGENT_GET:-}" STUB_LOCAL_RUNTIMES="${STUB_LOCAL_RUNTIMES:-}" \
    STUB_AUTOPILOT_GET="${STUB_AUTOPILOT_GET:-}" \
    AUTOTEAM_MULTICA_BIN="$TESTS_DIR/stubs/multica" \
    bash "$AUTOTEAM" "$@"
}

# 不带 gh 的环境运行 autoteam（init 的离线路径）
autoteam_offline() {
  env PATH="$REAL_JQ_DIR:$REAL_GIT_DIR:/usr/bin:/bin" HOME="$WORK/.home" NO_COLOR=1 bash "$AUTOTEAM" "$@"
}

# 生成一套可用的配置：init + 把 Makefile 改成真实命令 + registry 用桩里的 runtime
setup_ready_repo() {
  new_repo "${1:-acme/shop}"
  autoteam_stub init --owner alice --workspace test >/dev/null
  printf 'check:\n\t@true\ndev:\n\t@true\ndeploy:\n\t@true\n' > Makefile
  cat > ops/agents/registry.yaml <<'EOF'
accounts:
  claude-max:   { billing: subscription, windows: [5h, weekly] }
  chatgpt-plus: { billing: subscription, windows: [5h, weekly] }

agents:
  planner:     { role: planner,     account: claude-max,   runtime: claude@machine-c, model: default, max_tasks: 1 }
  impl-claude: { role: implementer, account: claude-max,   runtime: claude@machine-a, model: default, max_tasks: 2 }
  rev-codex:   { role: reviewer,    account: chatgpt-plus, runtime: codex@machine-b,  model: gpt-5.5, max_tasks: 2 }
  auditor:     { role: auditor,     account: claude-max,   runtime: rt-c-claude-0000, model: default, max_tasks: 1 }
EOF
  mkdir -p "$WORK/.home/.multica/profiles/test"
  printf '{"server_url":"https://api.multica.test","token":"mul_test_token"}' > "$WORK/.home/.multica/profiles/test/config.json"
}
