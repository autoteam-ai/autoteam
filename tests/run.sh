#!/usr/bin/env bash
# 运行全部测试：bash tests/run.sh [测试函数名的关键字]
set -o pipefail

# Runtime hosts can export AUTOTEAM_* credentials.  Tests create their own
# configuration fixtures, so inherited values must not override those files.
while IFS= read -r var; do
  unset "$var"
done < <(compgen -v AUTOTEAM_)

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

trap 'rm -rf "$TEST_BASE"' EXIT
filter=${1:-}
for f in "$TESTS_DIR"/test_*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

total=0 failed=0
for t in $(declare -F | awk '{print $3}' | grep '^t_' | sort); do
  case $t in *"$filter"*) ;; *) continue ;; esac
  total=$((total + 1))
  out=$( (T_FAILS=0; "$t"; exit "$T_FAILS") 2>&1 )
  rc=$?
  if [ "$rc" = 0 ]; then
    printf '  ✓ %s\n' "$t"
  else
    failed=$((failed + 1))
    printf '  ✗ %s\n%s\n' "$t" "$out"
  fi
done

printf '\n%d 个测试，%d 个失败\n' "$total" "$failed"
[ "$failed" = 0 ]
