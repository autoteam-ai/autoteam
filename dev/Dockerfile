# 开发镜像：make check / dev / deploy / publish 在本机、cloud runtime、CI 都进这个镜像执行
# （入口是 scripts/in-container.sh）。所有工具的版本只写在这个文件里；改了它，镜像 tag
# （按本文件内容算的 hash）跟着变，每台机器下次执行时自动重建。
# 要同时能在 amd64（GitHub runner）和 arm64（cloud runtime 的远端 daemon）上构建。
FROM node:22.23.3-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c

# 测试要用 openssl（造 App 私钥）、python3（查文档链接）、shasum（perl 自带）。
# jq 不用 apt 的：bookworm 的 jq 1.6 会把 50.0 输出成 50，下面装固定版本
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git make openssl perl python3 tar xz-utils \
  && rm -rf /var/lib/apt/lists/*

ARG SHELLCHECK_VERSION=v0.11.0
ARG SHELLCHECK_SHA256_AMD64=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
ARG SHELLCHECK_SHA256_ARM64=12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
ARG ACTIONLINT_VERSION=1.7.12
ARG ACTIONLINT_SHA256_AMD64=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ARG ACTIONLINT_SHA256_ARM64=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
ARG JQ_VERSION=1.7.1
ARG JQ_SHA256_AMD64=5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5
ARG JQ_SHA256_ARM64=4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5
ARG JSCPD_VERSION=5.3.2

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN arch=$(dpkg --print-architecture); \
  case $arch in \
    amd64) sc_arch=x86_64 sc_sum=$SHELLCHECK_SHA256_AMD64 al_sum=$ACTIONLINT_SHA256_AMD64 jq_sum=$JQ_SHA256_AMD64 ;; \
    arm64) sc_arch=aarch64 sc_sum=$SHELLCHECK_SHA256_ARM64 al_sum=$ACTIONLINT_SHA256_ARM64 jq_sum=$JQ_SHA256_ARM64 ;; \
    *) echo "不支持的架构：$arch" >&2; exit 1 ;; \
  esac; \
  tmp=$(mktemp -d); cd "$tmp"; \
  sc=shellcheck-$SHELLCHECK_VERSION.linux.$sc_arch.tar.xz; \
  curl -fsSLo "$sc" "https://github.com/koalaman/shellcheck/releases/download/$SHELLCHECK_VERSION/$sc"; \
  echo "$sc_sum  $sc" | sha256sum -c -; \
  tar -xJf "$sc" --strip-components=1 -C /usr/local/bin "shellcheck-$SHELLCHECK_VERSION/shellcheck"; \
  al=actionlint_${ACTIONLINT_VERSION}_linux_$arch.tar.gz; \
  curl -fsSLo "$al" "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/$al"; \
  echo "$al_sum  $al" | sha256sum -c -; \
  tar -xzf "$al" -C /usr/local/bin actionlint; \
  curl -fsSLo jq "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-linux-$arch"; \
  echo "$jq_sum  jq" | sha256sum -c -; \
  install -m 0755 jq /usr/local/bin/jq; \
  cd /; rm -rf "$tmp"; \
  npm install -g --no-fund --no-audit "jscpd@$JSCPD_VERSION"; \
  npm cache clean --force; \
  shellcheck --version; actionlint --version; jq --version; jscpd --version

# 容器里以宿主的 uid 执行，仓库目录的所有者可能对不上：让 git 信任任何目录
RUN git config --system --add safe.directory '*'
# docker cp 方式（远端 daemon）把仓库拷到这里；预先建好，否则 docker cp 以 root 建出来，
# 以宿主 uid 执行的命令没法在仓库根下新建 build/ 等目录
RUN mkdir -m 1777 /w

# 标记：已经在开发镜像里，make 直接执行，不再嵌套起容器
ENV AUTOTEAM_DEV_IMAGE=1
