# shellcheck shell=bash
# 文档：相对链接和锚点都要有效

t_docs_links_are_valid() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "      （没有 python3，跳过）"
    return 0
  fi
  out=$(python3 "$TESTS_DIR/check-links.py" "$ROOT" 2>&1) || tfail "文档里有坏链接：$out"
}
