#!/usr/bin/env bash
# 运行全部测试：bash tests/run.sh [--timing] [测试函数名的关键字]
# TEST_JOBS 默认取 CPU 核数；TEST_JOBS=1 退回串行。
set -o pipefail

# Runtime hosts can export AUTOTEAM_* credentials. Tests use fixture config.
while IFS= read -r var; do
  unset "$var"
done < <(compgen -v AUTOTEAM_)

runner=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run.sh
if [ "${1:-}" = --worker ]; then
  test_name=$2
  result_dir=$3
  TEST_BASE=$result_dir/$test_name/work
  mkdir -p "$TEST_BASE" || exit 1
else
  # Nested runners also own their directory; never clean up a caller's fixtures.
  TEST_BASE=$(mktemp -d "${TMPDIR:-/tmp}/autoteam-tests.XXXXXX") || exit 1
  trap 'rm -rf "$TEST_BASE"' EXIT
fi

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
for f in "$TESTS_DIR"/test_*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

if [ "${1:-}" = --worker ]; then
  TIMEFORMAT='%3R'
  # Each test gets a fresh shell, fixture directory and separate output files.
  run_test() {
    (T_FAILS=0; "$test_name"; exit "$T_FAILS") \
      > "$result_dir/$test_name/output" 2>&1
  }
  { time run_test; } 2> "$result_dir/$test_name/time"
  printf '%d\n' "$?" > "$result_dir/$test_name/status"
  exit 0
fi

timing=0 filter=
for arg in "$@"; do
  case $arg in
    --timing) timing=1 ;;
    --*) printf '未知选项：%s\n' "$arg" >&2; exit 2 ;;
    *) if [ -n "$filter" ]; then
         printf '只能指定一个测试名关键字\n' >&2; exit 2
       fi
       filter=$arg ;;
  esac
done
if [ -n "${TEST_JOBS:-}" ]; then
  jobs=$TEST_JOBS
elif command -v nproc >/dev/null 2>&1; then
  jobs=$(nproc)
else
  jobs=$(getconf _NPROCESSORS_ONLN)
fi
case $jobs in
  ''|*[!0-9]*) printf 'TEST_JOBS 必须是正整数\n' >&2; exit 2 ;;
esac
if ! [ "$jobs" -gt 0 ] 2>/dev/null; then
  printf 'TEST_JOBS 必须是正整数\n' >&2
  exit 2
fi

result_dir=$TEST_BASE/results
mkdir -p "$result_dir"
# extdebug supplies each function's source file (also available in bash 3.2).
shopt -s extdebug
while IFS= read -r t; do
  case $t in *"$filter"*) ;; *) continue ;; esac
  read -r name line file < <(declare -F "$t")
  printf '%s\t%s\n' "$t" "${file##*/}" >> "$result_dir/tests"
done < <(declare -F | awk '{print $3}' | LC_ALL=C sort | sed -n '/^t_/p')
shopt -u extdebug

# xargs waits for every worker. Workers record test failures without stopping it.
if [ -f "$result_dir/tests" ]; then
  cut -f1 "$result_dir/tests" | xargs -P "$jobs" -n 1 \
    bash -c 'exec bash "$1" --worker "$3" "$2"' _ "$runner" "$result_dir"
  worker_rc=$?
else
  worker_rc=0
  : > "$result_dir/tests"
fi

total=0 failed=0
while IFS=$'\t' read -r t file; do
  total=$((total + 1))
  rc=1
  if [ -f "$result_dir/$t/status" ]; then
    read -r rc < "$result_dir/$t/status"
  fi
  if [ "$rc" = 0 ]; then
    printf '  ✓ %s\n' "$t"
  else
    failed=$((failed + 1))
    printf '  ✗ %s\n' "$t"
    if [ -f "$result_dir/$t/output" ]; then
      cat "$result_dir/$t/output"
      printf '\n'
    else
      printf '测试进程未产生结果\n'
    fi
  fi
  if [ "$timing" = 1 ]; then
    elapsed=0
    [ ! -f "$result_dir/$t/time" ] || read -r elapsed < "$result_dir/$t/time"
    printf '    耗时 %s 秒\n' "$elapsed"
    printf '%s\t%s\t%s\n' "$elapsed" "$t" "$file" >> "$result_dir/timing"
  fi
done < "$result_dir/tests"

if [ "$timing" = 1 ] && [ "$total" -gt 0 ]; then
  printf '\n按文件合计（各测试耗时之和，秒）：\n'
  awk -F '\t' '{sum[$3]+=$1} END {for (f in sum) printf "  %s\t%.3f\n", f, sum[f]}' \
    "$result_dir/timing" | LC_ALL=C sort
  printf '\n最慢 10 个测试（秒）：\n'
  LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 "$result_dir/timing" | \
    awk -F '\t' 'NR <= 10 {printf "  %s\t%s\t%s\n", $2, $1, $3}'
fi
printf '\n%d 个测试，%d 个失败\n' "$total" "$failed"
[ "$failed" = 0 ] && [ "$worker_rc" = 0 ]
