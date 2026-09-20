#!/usr/bin/env bash
# 代码健康指标，Auditor 每周跑一次；看趋势，不看绝对值。
# 用法：ops/agents/scripts/health-metrics.sh [--md | --json] [--days N]
#   duplication_pct   重复代码占比（jscpd，配置在 .jscpd.json）
#   legacy_touch_pct  近 N 天（默认 30）改过的文件里，上一次改动在一年以前的比例：老代码有没有人维护
#   rework_14d_pct    近 14 天改过的文件里，前 14 天也改过的比例：两周内返工
#   prs_7d            近 7 天合并的 PR：数量、改动行数中位数和 75 分位、一次通过率、平均打回次数
#   human_7d          近 7 天人（autoteam.conf 的 AUTOTEAM_OWNER）在 GitHub 上的介入次数：
#                     自己提交了多少次、评审了多少个 PR。这套流程做得好不好，看它降不降
# 依赖 git、jq；PR 指标需要已登录的 gh；重复代码需要 npx（设 AUTOTEAM_SKIP_JSCPD=1 跳过）。
set -eo pipefail

format=md
days=$(sed -n 's/^AUTOTEAM_METRICS_DAYS=//p' "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/ops/agents/autoteam.conf" 2>/dev/null | head -n 1 | tr -d '[:space:]')
days=${days:-30}
while [ $# -gt 0 ]; do
  case $1 in
    --json) format=json ;;
    --md) format=md ;;
    --days) days=$2; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
  shift
done

root=$(git rev-parse --show-toplevel)
cd "$root"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pct() { awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) print "null"; else printf "%.1f\n", a * 100 / b }'; }

# 1. 重复代码占比
dup=null
if [ "${AUTOTEAM_SKIP_JSCPD:-0}" != 1 ] && command -v npx >/dev/null 2>&1; then
  cfg=()
  [ -f .jscpd.json ] && cfg=(--config .jscpd.json)
  npx --yes jscpd@5 ${cfg[@]+"${cfg[@]}"} --reporters json --output "$tmp/jscpd" --silent . >/dev/null 2>&1 || true
  if [ -f "$tmp/jscpd/jscpd-report.json" ]; then
    dup=$(jq '.statistics.total.percentage // null' "$tmp/jscpd/jscpd-report.json")
  fi
fi

# 某个时间窗口内改过、现在还存在的文件
changed_files() {
  git log --since="$1" ${2:+--until="$2"} --name-only --pretty=format: | sed '/^$/d' | sort -u \
    | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done
}

# 2. 老文件改动占比
changed_files "$days days ago" > "$tmp/recent"
total=0 legacy=0
year_ago=$(( $(date +%s) - 365 * 86400 ))
while IFS= read -r f; do
  total=$((total + 1))
  prev=$(git log -1 --format=%ct --until="$days days ago" -- "$f")
  if [ -n "$prev" ] && [ "$prev" -lt "$year_ago" ]; then legacy=$((legacy + 1)); fi
done < "$tmp/recent"

# 3. 两周返工率
changed_files "14 days ago" > "$tmp/w1"
changed_files "28 days ago" "14 days ago" > "$tmp/w0"
w1=$(grep -c . "$tmp/w1" || true)
both=$(comm -12 "$tmp/w1" "$tmp/w0" | grep -c . || true)

# 4. 近 7 天合并的 PR
prs=null
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  since=$(jq -rn 'now - 7 * 86400 | strftime("%Y-%m-%d")')
  if raw=$(gh pr list --state merged --search "merged:>=$since" --limit 200 --json number,additions,deletions,reviews 2>/dev/null); then
    prs=$(jq '
      def quant($p): sort | if length == 0 then null else .[((length - 1) * $p | floor)] end;
      [.[] | {size: (.additions + .deletions),
              rej: ([.reviews[]? | select(.state == "CHANGES_REQUESTED" or ((.body // "") | startswith("【阻塞】")))] | length)}] as $p
      | ($p | length) as $n
      | {
          merged: $n,
          size_p50: ([$p[].size] | quant(0.5)),
          size_p75: ([$p[].size] | quant(0.75)),
          first_pass_pct: (if $n == 0 then null else (([$p[] | select(.rej == 0)] | length) * 1000 / $n | round / 10) end),
          avg_rejections: (if $n == 0 then null else (([$p[].rej] | add) * 10 / $n | round / 10) end)
        }' <<<"$raw")
  fi
fi

# 5. 近 7 天人的介入。批准任务是设计内的动作不算，这里只数人自己动手写和评审代码：
#    它应该随着规则变好而下降，是"越来越符合人工期望"唯一客观的指标
human=null
owner=$(sed -n 's/^AUTOTEAM_OWNER=//p' "$root/ops/agents/autoteam.conf" 2>/dev/null | head -n 1 | tr -d '[:space:]')
if [ -n "$owner" ]; then
  commits=$(git log --since="7 days ago" --author="$owner" --oneline 2>/dev/null | grep -c . || true)
  reviews=null
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    since7=$(jq -rn 'now - 7 * 86400 | strftime("%Y-%m-%d")')
    if rv=$(gh pr list --state all --search "reviewed-by:$owner updated:>=$since7" --limit 100 --json number 2>/dev/null); then
      reviews=$(jq 'length' <<<"$rv")
    fi
  fi
  human=$(jq -n --argjson c "${commits:-0}" --argjson r "$reviews" '{commits: $c, reviews: $r}')
fi

json=$(jq -n \
  --argjson human "$human" \
  --argjson dup "$dup" \
  --argjson legacy "$(pct "$legacy" "$total")" --argjson files "$total" --argjson days "$days" \
  --argjson rework "$(pct "$both" "$w1")" \
  --argjson prs "$prs" '
  {
    generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    duplication_pct: $dup,
    legacy_touch_pct: $legacy,
    legacy_window_days: $days,
    files_changed: $files,
    rework_14d_pct: $rework,
    prs_7d: $prs,
    human_7d: $human
  }')

if [ "$format" = json ]; then
  printf '%s\n' "$json"
  exit 0
fi

jq -r '
  def v: if . == null then "—" else tostring end;
  "| 指标 | 数值 |",
  "|---|---|",
  "| 重复代码占比 % | \(.duplication_pct | v) |",
  "| 老文件改动占比 %（近 \(.legacy_window_days) 天，\(.files_changed) 个文件） | \(.legacy_touch_pct | v) |",
  "| 两周返工率 % | \(.rework_14d_pct | v) |",
  "| 近 7 天合并 PR 数 | \(.prs_7d.merged | v) |",
  "| PR 改动行数 中位数 / 75 分位 | \(.prs_7d.size_p50 | v) / \(.prs_7d.size_p75 | v) |",
  "| 评审一次通过率 % | \(.prs_7d.first_pass_pct | v) |",
  "| 平均打回次数 | \(.prs_7d.avg_rejections | v) |",
  "| 人工介入：本人提交 / 评审 PR（近 7 天） | \(.human_7d.commits | v) / \(.human_7d.reviews | v) |",
  "",
  "生成时间 \(.generated_at)"
' <<<"$json"
