# shellcheck shell=bash
# autoteam migrate：旧版布局 → .autoteam/。
# 旧路径的字面量只允许出现在 skills/autoteam/lib/migrate.sh，所以这里分两段拼。

# 造一个旧布局的仓库：先 init 出新布局，再倒回旧样子（指令落盘、路径写旧的），提交
new_legacy_repo() {
  local sub=agent legacy pkg=$ROOT/skills/autoteam/instructions f
  legacy=ops/${sub}s
  new_repo acme/shop
  autoteam_offline init --owner alice >/dev/null
  mkdir -p ops
  mv .autoteam "$legacy"
  rm "$legacy/.lock.json"
  cp "$pkg"/roles/*.md "$legacy/"
  cp -R "$pkg/autopilots" "$legacy/autopilots"
  cp "$pkg/planner-mcp.json" "$legacy/"
  mkdir -p "$legacy/local"
  echo fakekey > "$legacy/local/implementer.pem"
  for f in .gitignore .github/CODEOWNERS AGENTS.md; do
    sed "s#\.autoteam#$legacy#g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
  LEGACY=$legacy
  git add -A && git commit -qm legacy
}

t_migrate_dry_run_changes_nothing() {
  new_legacy_repo
  echo "评审必须跑 e2e" >> "$LEGACY/reviewer.md"
  before=$(git status --short; find . -path ./.git -prune -o -type f -print0 | xargs -0 shasum | sort)
  out=$(autoteam_offline migrate --dry-run)
  after=$(git status --short; find . -path ./.git -prune -o -type f -print0 | xargs -0 shasum | sort)
  assert_eq "$after" "$before" "--dry-run 不应改任何文件"
  assert_contains "$out" "保留 reviewer.md → .autoteam/instructions/roles/reviewer.md"
  assert_contains "$out" "删除 planner.md（与包内一致"
  assert_contains "$out" "以上是计划，没有改任何文件"
  [ -d "$LEGACY" ] || tfail "旧目录应还在"
  assert_no_file .autoteam
}

t_migrate_moves_and_splits_instructions() {
  new_legacy_repo
  echo "评审必须跑 e2e" >> "$LEGACY/reviewer.md"
  echo "自己加的 autopilot" > "$LEGACY/autopilots/mine.md"
  out=$(autoteam_offline migrate)
  assert_no_file ops
  for f in autoteam.conf registry.yaml playbook.md README.md scripts/loop-guard.sh .lock.json local/implementer.pem; do
    assert_file ".autoteam/$f"
  done
  # 与包内一致的删除；改过的、自己写的保留成 eject
  for f in planner.md implementer.md auditor.md planner-mcp.json autopilots/patrol.md; do
    assert_no_file ".autoteam/$f"
  done
  assert_no_file .autoteam/instructions/roles/planner.md
  assert_no_file .autoteam/autopilots
  assert_file_contains .autoteam/instructions/roles/reviewer.md "评审必须跑 e2e"
  assert_file .autoteam/instructions/autopilots/mine.md
  assert_contains "$out" "删除 planner.md（与包内一致"
  assert_contains "$out" "保留 autopilots/mine.md → .autoteam/instructions/autopilots/mine.md（包内没有同名文件"
  # 受管块里的路径换成新布局
  assert_file_contains .gitignore "/.autoteam/local/"
  assert_file_contains .github/CODEOWNERS "/.autoteam/     @alice"
  assert_file_contains AGENTS.md "在 \`.autoteam/\`"
  # lock 写好，upgrade 能接着用
  assert_file_contains .autoteam/.lock.json '".autoteam/playbook.md"'
  assert_file_contains .autoteam/.lock.json '".gitignore": { "kind": "block"'
  assert_contains "$(autoteam_offline upgrade)" "已是最新 .autoteam/playbook.md"
  # 不提交、不推送
  assert_eq "$(git log --oneline | wc -l | tr -d ' ')" 1 "migrate 不应提交"
}

t_migrate_lists_leftover_references() {
  new_legacy_repo
  printf '# Shop\n\n见 %s/playbook.md\n' "$LEGACY" > README.md
  out=$(autoteam_offline migrate)
  assert_contains "$out" "README.md:1"
  assert_not_contains "$out" "AGENTS.md:" "受管块里的旧路径已经被换掉"
  assert_file_contains README.md "$LEGACY/playbook.md" # 用户自己写的不自动改
}

t_migrate_autopilot_cron_becomes_cron_key() {
  new_legacy_repo
  # 旧版渲染出的是 cron: <conf 里的值>：值没改过就算和包内一致，改过的保留并转成 cron_key
  sed 's/^cron_key: AUTOTEAM_CRON_PATROL$/cron: 0 *\/2 * * */' "$ROOT/skills/autoteam/instructions/autopilots/patrol.md" > "$LEGACY/autopilots/patrol.md"
  sed 's/^cron_key: AUTOTEAM_CRON_SCORECARD$/cron: 0 7 * * */' "$ROOT/skills/autoteam/instructions/autopilots/scorecard.md" > "$LEGACY/autopilots/scorecard.md"
  out=$(autoteam_offline migrate)
  assert_no_file .autoteam/instructions/autopilots/patrol.md
  assert_file_contains .autoteam/instructions/autopilots/scorecard.md "cron_key: AUTOTEAM_CRON_SCORECARD"
  assert_contains "$out" "scorecard.md 的 cron 和 autoteam.conf 的 AUTOTEAM_CRON_SCORECARD 不同"
}

t_migrate_refuses_when_not_applicable() {
  new_repo
  out=$(autoteam_offline migrate 2>&1) && tfail "没有旧布局时应失败"
  assert_contains "$out" "不是旧版布局"
  new_legacy_repo
  mkdir .autoteam
  out=$(autoteam_offline migrate 2>&1) && tfail ".autoteam 已存在时应失败"
  assert_contains "$out" "已经存在"
  assert_file "$LEGACY/autoteam.conf"
}

t_doctor_points_to_migrate_on_legacy_layout() {
  new_legacy_repo
  out=$(autoteam_offline doctor --skip-github --skip-multica) && tfail "旧布局应报错"
  assert_contains "$out" "检测到旧版布局 $LEGACY/：运行 autoteam migrate"
}
