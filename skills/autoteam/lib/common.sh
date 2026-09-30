# shellcheck shell=bash
# 公共函数：输出、依赖检查、预览/执行、临时文件。

# 装进用户仓库的目录（相对仓库根）。代码里的路径都从这里拼，别再写死
# shellcheck disable=SC2034  # 在其他 lib 里使用
AUTOTEAM_DIR=.autoteam

# 版本号只在包内 package.json 里存一份，用 sed 取（autoteam version 不该依赖 jq）
autoteam_version() {
  sed -n 's/^  "version": "\(.*\)",$/\1/p' "$AUTOTEAM_HOME/package.json" | head -n 1
}

# 根入口必须固定到当前 CLI 的源码提交。发布包带 source-ref；源码 checkout 读自身提交；
# npx skills add 复制的目录没有 git 元数据时，只接受与远端 main 完全一致的 CLI。
autoteam_source_ref() {
  local ref source_root tmp
  if [ -f "$AUTOTEAM_HOME/source-ref" ]; then
    ref=$(cat "$AUTOTEAM_HOME/source-ref")
  else
    source_root=$(git -C "$AUTOTEAM_HOME" rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$source_root" ] && [ "$AUTOTEAM_HOME" = "$source_root/skills/autoteam" ]; then
      ref=$(git -C "$source_root" rev-parse HEAD)
    else
      need_cmd curl
      ref=$(git ls-remote https://github.com/autoteam-ai/autoteam.git HEAD | cut -f1)
      [[ $ref =~ ^[0-9a-f]{40}$ ]] || die "无法确定 autoteam 源码提交：检查 GitHub 网络连接"
      tmp=$(autoteam_tmpdir)/source-ref-check
      mkdir -p "$tmp"
      curl -fsSL "https://codeload.github.com/autoteam-ai/autoteam/tar.gz/$ref" |
        tar -xz -C "$tmp" --strip-components=1 || die "下载 autoteam $ref 失败"
      for source_root in bin lib templates; do
        diff -qr "$AUTOTEAM_HOME/$source_root" "$tmp/skills/autoteam/$source_root" >/dev/null ||
          die "本机 skill 与 GitHub main 不一致：先运行 npx skills update autoteam，再运行 autoteam init / upgrade"
      done
    fi
  fi
  [[ $ref =~ ^[0-9a-f]{40}$ ]] || die "autoteam source-ref 不是 40 位提交 SHA：$ref"
  printf '%s' "$ref"
}

# 预览模式：github / multica 默认只打印将要做的改动，--apply 才执行
AUTOTEAM_APPLY=${AUTOTEAM_APPLY:-0}
AUTOTEAM_WARNINGS=0
AUTOTEAM_ERRORS=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_DIM=$'\033[2m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_BOLD='' C_RESET=''
fi

section() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET"; }
info()    { printf '  %s\n' "$*"; }
ok()      { printf '  %s✅%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { AUTOTEAM_WARNINGS=$((AUTOTEAM_WARNINGS + 1)); printf '  %s⚠️ %s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail()    { AUTOTEAM_ERRORS=$((AUTOTEAM_ERRORS + 1)); printf '  %s❌%s %s\n' "$C_RED" "$C_RESET" "$*"; }
hint()    { printf '     %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
die()     { printf '%sautoteam：%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

# 预览模式下打印一条将要执行的改动；执行模式下打印“执行”
planned() {
  if [ "$AUTOTEAM_APPLY" = 1 ]; then
    printf '  %s→%s %s\n' "$C_BLUE" "$C_RESET" "$*"
  else
    printf '  %s[预览]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令 $1。${2:-}"
}

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 读文件全文（保留结尾换行）
read_file() {
  local content
  content=$(cat "$1"; printf x)
  printf '%s' "${content%x}"
}

# 临时目录。必须在主进程里先调用 autoteam_tmp_init（autoteam_main 开头会调）：
# 如果第一次是在 $(...) 子 shell 里创建，子 shell 退出时 trap 会把它删掉。
autoteam_tmp_init() {
  if [ -z "${AUTOTEAM_TMP:-}" ]; then
    AUTOTEAM_TMP=$(mktemp -d "${TMPDIR:-/tmp}/autoteam.XXXXXX")
    trap 'rm -rf "$AUTOTEAM_TMP"' EXIT
  fi
}

autoteam_tmpdir() {
  autoteam_tmp_init
  printf '%s' "$AUTOTEAM_TMP"
}

# 当前 git 仓库根目录，不在仓库里就退出
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "当前目录不是 git 仓库，请在项目根目录运行，或用 -C 指定"
}

# 从 git remote 推断 owner/name
detect_repo_from_remote() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  url=${url%.git}
  case $url in
    git@github.com:*) printf '%s' "${url#git@github.com:}" ;;
    https://github.com/*) printf '%s' "${url#https://github.com/}" ;;
    ssh://git@github.com/*) printf '%s' "${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
}

# 统计结尾打印
print_summary() {
  printf '\n'
  if [ "$AUTOTEAM_ERRORS" -gt 0 ]; then
    printf '%s%d 个错误，%d 个提醒%s\n' "$C_RED" "$AUTOTEAM_ERRORS" "$AUTOTEAM_WARNINGS" "$C_RESET"
  elif [ "$AUTOTEAM_WARNINGS" -gt 0 ]; then
    printf '%s没有错误，%d 个提醒%s\n' "$C_YELLOW" "$AUTOTEAM_WARNINGS" "$C_RESET"
  else
    printf '%s全部通过%s\n' "$C_GREEN" "$C_RESET"
  fi
}

preview_footer() {
  if [ "$AUTOTEAM_APPLY" != 1 ]; then
    printf '\n%s以上是预览，没有做任何改动。确认后加 --apply 执行。%s\n' "$C_BLUE" "$C_RESET"
  fi
}
