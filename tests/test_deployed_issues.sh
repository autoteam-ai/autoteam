# shellcheck shell=bash
# The gh stub uses the shape observed from the read-only production API query:
# workflow_runs: [{id, head_sha, status, conclusion, created_at, event}].

setup_deployed_issues() {
  new_repo acme/shop
  mkdir -p .autoteam "$WORK/bin"
  cat > .autoteam/autoteam.conf <<'EOF'
AUTOTEAM_REPO=acme/shop
AUTOTEAM_ISSUE_PREFIX=SHOP
AUTOTEAM_DEPLOY_ENVIRONMENT=production
EOF
  cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -eu
endpoint=''
for arg in "$@"; do case $arg in repos/*) endpoint=$arg ;; esac; done
printf '%s\n' "$endpoint" >> "$STUB_LOG"
case "$endpoint" in
  */deployments\?*)
    case $DEPLOY_CASE in first) : ;; *) printf '99\n90\n88\n' ;; esac ;;
  */deployments/99/statuses\?*) echo in_progress ;;
  */deployments/90/statuses\?*) echo failure ;;
  */deployments/88/statuses\?*) echo success ;;
  */deployments/88) echo base ;;
  */runs\?*) : ;;
  */compare/base...head\?*) printf 'merge1\nmerge2\n' ;;
  */compare/target...base\?*) echo merge1 ;;
  */commits/merge1/pulls\?*) printf 'SHOP-12 Add first\nSHOP-12 Another association\n' ;;
  */commits/merge2/pulls\?*) printf 'SHOP-13 Add second\nOther PR\n' ;;
  */commits/head/pulls\?*) echo 'SHOP-14 First deployment' ;;
  *) echo "unexpected endpoint: $endpoint" >&2; exit 1 ;;
esac
EOF
  chmod +x "$WORK/bin/gh"
}

t_deployed_issues_includes_merges_after_cancelled_deploy() {
  setup_deployed_issues
  out=$(DEPLOY_CASE=cancelled PATH="$WORK/bin:$PATH" bash "$ROOT/skills/autoteam/templates/autoteam/scripts/deployed-issues.sh" deploy head)
  assert_eq "$(printf '%s' "$out" | jq -c .)" '["SHOP-12","SHOP-13"]'
  assert_log 'compare/base...head'
}

t_deployed_issues_first_deployment_only_uses_head_pr() {
  setup_deployed_issues
  out=$(DEPLOY_CASE=first PATH="$WORK/bin:$PATH" bash "$ROOT/skills/autoteam/templates/autoteam/scripts/deployed-issues.sh" deploy head)
  assert_eq "$(printf '%s' "$out" | jq -c .)" '["SHOP-14"]'
  assert_no_log 'compare/'
}

t_deployed_issues_empty_list_skips_notification() {
  setup_deployed_issues
  mkdir -p .autoteam/scripts
  cp "$ROOT/skills/autoteam/templates/autoteam/scripts/deployed-issues.sh" .autoteam/scripts/
  awk '/^        run: \|$/ {on=1; next} on {sub(/^          /, ""); print}' \
    "$ROOT/skills/autoteam/templates/root/github/workflows/deploy.yml" > "$WORK/notify.sh"
  cat > "$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo curl-called >> "$STUB_LOG"
exit 99
EOF
  chmod +x "$WORK/bin/curl"
  out=$(DEPLOY_CASE=cancelled PATH="$WORK/bin:$PATH" HOOK=https://example.test SHA=base \
    RESULT=success REPO=acme/shop RUN_URL=https://example.test/run KEY=deploy-1 bash "$WORK/notify.sh")
  assert_contains "$out" '没有相关任务，跳过通知 Planner'
  assert_no_log 'curl-called'
}

t_deployed_issues_rollback_lists_removed_prs() {
  setup_deployed_issues
  out=$(DEPLOY_CASE=cancelled PATH="$WORK/bin:$PATH" bash "$ROOT/skills/autoteam/templates/autoteam/scripts/deployed-issues.sh" rollback target)
  assert_eq "$(printf '%s' "$out" | jq -c .)" '["SHOP-12"]'
}
