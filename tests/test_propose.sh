# shellcheck shell=bash
# autoteam propose：真的 git（本地裸仓库当远端），gh 用桩，令牌脚本换成桩。

propose_fixture() {
  setup_ready_repo
  cat > .autoteam/scripts/gh-app-token.sh <<'STUB'
#!/usr/bin/env bash
case $1 in
  --identity) printf 'stub-app[bot]\t1+stub-app[bot]@users.noreply.github.com\n' ;;
  --credential) printf 'username=x-access-token\npassword=stub-secret-token\n' ;;
  --run) shift 2; printf 'run-as-implementer\n' >> "$STUB_LOG"; exec "$@" ;;
esac
STUB
  printf 'AUTOTEAM_REPO=acme/shop\n' >> .autoteam/autoteam.conf
  printf '.stub/\n.home/\n' >> .git/info/exclude
  git add -A && git commit -qm init
  git update-ref refs/remotes/origin/main HEAD
  REMOTE=$(mktemp -d "$TEST_BASE/remote.XXXXXX")
  git init -q --bare "$REMOTE"
  HOME="$WORK/.home" git config --global user.name human
  HOME="$WORK/.home" git config --global user.email human@example.com
  printf '[]' > "$STUB_STATE/branch-rules.json"
  export AUTOTEAM_PROPOSE_REMOTE=$REMOTE
}

propose_env() { # 人本地会被改动的东西
  printf '%s\n' "$(HOME="$WORK/.home" git config --global user.name)" "$(git remote -v)" "$(git branch --list)" "$(git worktree list | wc -l)" "$(git status --porcelain)"
}

t_propose_preview_changes_nothing() {
  propose_fixture
  echo "rule" >> .autoteam/playbook.md
  before=$(propose_env)
  out=$(autoteam_stub propose --title 'HDGCS-1 改规则')
  assert_contains "$out" 'propose/'
  assert_contains "$out" 'HDGCS-1 改规则'
  assert_contains "$out" 'M .autoteam/playbook.md'
  assert_contains "$out" '加 --apply'
  assert_eq "$(propose_env)" "$before"
  assert_eq "$(git -C "$REMOTE" branch --list)" ''
  assert_no_log 'gh pr create'
}

t_propose_apply_uncommitted() {
  propose_fixture
  echo "rule" >> .autoteam/playbook.md
  echo "new" > notes.md
  before=$(propose_env)
  out=$(autoteam_stub propose --title 'HDGCS-1 改规则' --apply)
  assert_contains "$out" 'PR：https://github.com/acme/shop/pull/12'
  assert_not_contains "$out" 'stub-secret-token'
  assert_eq "$(propose_env)" "$before" '人本地的 git 身份、remote、分支、worktree、工作区都不应变'
  branch=$(git -C "$REMOTE" for-each-ref --format='%(refname:short)' refs/heads)
  case $branch in propose/*) ;; *) tfail "远端应有 propose/ 分支：[$branch]" ;; esac
  assert_eq "$(git -C "$REMOTE" log -1 --format=%an "$branch")" 'stub-app[bot]'
  assert_eq "$(git -C "$REMOTE" show "$branch:notes.md")" new '未跟踪文件也应进快照'
  assert_log "gh pr create --repo acme/shop --base main --head $branch --title HDGCS-1 改规则"
  assert_log 'run-as-implementer'
}

t_propose_commits_ahead_of_base() {
  propose_fixture
  git checkout -qb feature
  echo "rule" >> .autoteam/playbook.md
  git commit -qam 'HDGCS-2 调整手册'
  out=$(autoteam_stub propose --apply)
  assert_contains "$out" '分支上 1 个提交'
  assert_log '--title HDGCS-2 调整手册'
  branch=$(git -C "$REMOTE" for-each-ref --format='%(refname:short)' refs/heads)
  assert_eq "$(git -C "$REMOTE" rev-parse "$branch")" "$(git rev-parse HEAD)" '干净工作区应直接推 HEAD'
  assert_eq "$(git branch --list | tr -d ' *\n')" 'featuremain'
}

t_propose_nothing_to_propose() {
  propose_fixture
  out=$(autoteam_stub propose --apply 2>&1) && tfail '没有改动应失败'
  assert_contains "$out" '没有可提议的改动'
  assert_no_log 'gh pr create'
}

t_propose_pr_failure_reports_pushed_branch() {
  propose_fixture
  echo "rule" >> .autoteam/playbook.md
  # open-pr.sh 要 --title 和 body 都在：让 gh 桩的 pr create 缺席即可复现不了，改为目标分支不是默认分支
  printf '{"number":12,"url":"https://github.com/acme/shop/pull/12","state":"CLOSED","baseRefName":"main"}' > "$STUB_STATE/pr.json"
  out=$(autoteam_stub propose --apply 2>&1) && tfail 'PR 已关闭时应失败'
  assert_contains "$out" '已推到远端'
  assert_eq "$(git branch --list | tr -d ' *\n')" 'main' '失败后也要清理临时分支'
}

t_propose_refuses_rewritten_url() {
  propose_fixture
  echo "rule" >> .autoteam/playbook.md
  HOME="$WORK/.home" git config --global url.git@github.com:.insteadOf https://github.com/
  unset AUTOTEAM_PROPOSE_REMOTE
  out=$(autoteam_stub propose --apply 2>&1) && tfail 'URL 被改写时应失败'
  assert_contains "$out" 'insteadOf'
  assert_eq "$(git -C "$REMOTE" branch --list)" ''
}
