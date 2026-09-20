#!/usr/bin/env bash
# make dev：起一个沙盒仓库，用 tests/stubs 里的 gh / multica / curl 桩把 autoteam 跑一遍。
# Implementer 每次开工先跑它，确认当前代码是好的，再动手改。可重复执行。
#
# 沙盒在 tests/.work/sandbox（已被 gitignore），每次重建。不碰网络、不碰任何真实的
# GitHub 仓库和 Multica 工作区。
set -eo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SANDBOX=$ROOT/tests/.work/sandbox

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
cd "$SANDBOX"

git init -q -b main .
git config user.email dev@example.com
git config user.name dev
git remote add origin https://github.com/acme/sandbox.git

export STUB_STATE=$SANDBOX/.stub
export STUB_LOG=$STUB_STATE/log
export STUB_SCENARIO=${STUB_SCENARIO:-org-public}
export STUB_FIXTURES=$HERE/fixtures
mkdir -p "$STUB_STATE" "$SANDBOX/.home"

run() {  # 带桩跑 autoteam
  env PATH="$HERE/stubs:$(dirname "$(command -v jq)"):$(dirname "$(command -v git)"):/usr/bin:/bin" \
    HOME="$SANDBOX/.home" NO_COLOR=1 \
    STUB_LOG="$STUB_LOG" STUB_STATE="$STUB_STATE" STUB_FIXTURES="$STUB_FIXTURES" \
    STUB_SCENARIO="$STUB_SCENARIO" AUTOTEAM_MULTICA_BIN="$HERE/stubs/multica" \
    bash "$ROOT/bin/autoteam" "$@"
}

echo "== init =="
run init --owner dev --workspace test

echo
echo "== 把 Makefile 和 registry 填成能过 doctor 的样子 =="
printf 'check:\n\t@true\ndev:\n\t@true\ndeploy:\n\t@true\n' > Makefile
cat > ops/agents/registry.yaml <<'YAML'
accounts:
  claude-max: { billing: subscription, windows: [5h, weekly] }

agents:
  planner:  { role: planner,     account: claude-max, runtime: claude@machine-c, model: default, max_tasks: 1 }
  impl:     { role: implementer, account: claude-max, runtime: claude@machine-a, model: default, max_tasks: 2 }
  rev:      { role: reviewer,    account: claude-max, runtime: codex@machine-b,  model: default, max_tasks: 2 }
  auditor:  { role: auditor,     account: claude-max, runtime: rt-c-claude-0000, model: default, max_tasks: 1 }
YAML

echo
echo "== doctor（只看本地部分）=="
run doctor --skip-github --skip-multica || true

echo
echo "== diff --check（漂移闸门）=="
run diff --check

echo
echo "沙盒在 $SANDBOX"
echo "可以在里面直接试：bash $ROOT/bin/autoteam -C $SANDBOX <命令>"
