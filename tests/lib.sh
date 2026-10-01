# shellcheck shell=bash
# 极简测试框架：test_*.sh 里定义 t_ 开头的函数，run.sh 逐个在子 shell 里执行。

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$TESTS_DIR/.." && pwd)
AUTOTEAM=$ROOT/skills/autoteam/bin/autoteam
TPL=$ROOT/skills/autoteam/templates
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

# 给已 init 的仓库填入真实 Makefile、桩 runtime 和登录配置。
configure_ready_repo() {
  printf 'check:\n\t@true\ndev:\n\t@true\ndeploy:\n\t@true\n' > Makefile
  cat > .autoteam/registry.yaml <<'EOF'
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

# worker 的 result_dir 是本次 run.sh 的共享目录；直接 source lib.sh 时用 TEST_BASE。
# 不跨测试运行复用，嵌套 runner 也不会读到外层的模板。
setup_repo_template() {
  local stage=$1 repo=${2:-acme/shop} cache key tries=0
  case $stage in init|ready|applied) ;; *) echo "未知仓库模板：$stage" >&2; exit 1 ;; esac
  key=$(printf '%s\n' "$repo" "${STUB_SCENARIO:-user-public}" "$AUTOTEAM" | git hash-object --stdin)
  cache=${result_dir:-$TEST_BASE}/repo-templates/$stage-$key
  mkdir -p "${cache%/*}" || exit 1
  while [ ! -d "$cache" ]; do
    if [ -f "$cache.failed" ]; then
      echo "仓库模板构建失败：$stage（见首次构建的测试输出）" >&2
      exit 1
    fi
    if mkdir "$cache.lock" 2>/dev/null; then
      # 获取锁之前可能已由另一个 worker 发布；再次确认，避免重复构建。
      if [ -f "$cache.failed" ]; then
        rmdir "$cache.lock"
        echo "仓库模板构建失败：$stage" >&2
        exit 1
      fi
      if [ ! -d "$cache" ]; then
        build_repo_template "$stage" "$repo" "$cache" || exit 1
      else
        rmdir "$cache.lock" || exit 1
      fi
    else
      tries=$((tries + 1))
      [ "$tries" -lt 1200 ] || { echo "等待仓库模板超时：$stage" >&2; exit 1; }
      sleep 0.1
    fi
  done
  WORK=$(mktemp -d "$TEST_BASE/repo.XXXXXX") || exit 1
  cp -a "$cache/." "$WORK/" || exit 1
  cd "$WORK" || exit 1
  STUB_LOG=$WORK/.stub/log
  STUB_STATE=$WORK/.stub
  export STUB_LOG STUB_STATE
  # git init 产生的 .git/config 不含 core.worktree 等绝对路径；配置和桩 JSON
  # 也不含仓库路径。调用日志里的临时仓库路径则要改成当前副本。
  if [ -f "$STUB_LOG" ]; then
    python3 - "$STUB_LOG" "$(cat "$cache.origin")" "$WORK" <<'PYTHON'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace(sys.argv[2], sys.argv[3]))
PYTHON
  fi
}

# 只有持锁者构建，原子发布完整目录；失败标记让其他 worker 直接报错。
# 子 shell 隔离 WORK、cwd、桩变量和 trap，不影响正在运行的用例。
build_repo_template() (
  local stage=$1 repo=$2 cache=$3
  trap 'touch "$cache.failed"; rmdir "$cache.lock"' EXIT
  trap 'exit 1' INT TERM
  case $stage in
    init)
      new_repo "$repo" || exit 1
      autoteam_offline init --owner alice >/dev/null || exit 1
      ;;
    ready)
      new_repo "$repo" || exit 1
      autoteam_stub init --owner alice --workspace test >/dev/null || exit 1
      configure_ready_repo || exit 1
      ;;
    applied)
      setup_ready_repo "$repo"
      autoteam_stub multica --apply >/dev/null || exit 1
      ;;
  esac
  printf '%s\n' "$WORK" > "$cache.origin" || exit 1
  mv "$WORK" "$cache" || exit 1
  trap - EXIT
  rmdir "$cache.lock"
)

setup_init_repo() { setup_repo_template init "${1:-acme/shop}"; }
setup_ready_repo() { setup_repo_template ready "${1:-acme/shop}"; }
setup_applied_repo() { setup_repo_template applied "${1:-acme/shop}"; }
