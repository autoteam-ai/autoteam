# 本仓库的检查：make check = shellcheck + actionlint + 单元测试。
# 发布：make deploy 把包发到 npm（先 make deploy DRY_RUN=1 演练）。
# 本机没装 shellcheck / actionlint 时用 docker 镜像跑。docker 里的 shellcheck 是静态
# 二进制、没有 locale 数据，默认输出格式会回显源码行，遇到中文就崩在 commitBuffer；
# --format=gcc 不回显源码行，绕开这个问题（设 LANG / LC_ALL 没用，试过）。
SHELL := /bin/bash
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0
ACTIONLINT_IMAGE := rhysd/actionlint:1.7.12
SCRIPTS := bin/autoteam scripts/release.sh skills/autoteam/scripts/autoteam $(wildcard skills/autoteam/scripts/lib/*.sh) \
  $(wildcard skills/autoteam/assets/templates/ops/agents/scripts/*.sh) \
  tests/run.sh tests/lib.sh tests/render-workflows.sh $(wildcard tests/test_*.sh) $(wildcard tests/stubs/*)

.PHONY: check test lint shellcheck actionlint deploy

check: lint test ## 全部检查

test: ## 单元测试（兼容 macOS 自带的 bash 3.2）
	bash tests/run.sh

lint: shellcheck actionlint

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -x $(SCRIPTS); \
	else docker run --rm -v "$(CURDIR):/mnt" -w /mnt $(SHELLCHECK_IMAGE) --format=gcc -x $(SCRIPTS); fi

actionlint: ## 检查本仓库的 CI 和渲染后的工作流模板
	@rm -rf tests/.work/actionlint && bash tests/render-workflows.sh tests/.work/actionlint >/dev/null
	@if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/*.yml tests/.work/actionlint/.github/workflows/*.yml; \
	else docker run --rm -v "$(CURDIR):/repo" -w /repo $(ACTIONLINT_IMAGE) .github/workflows/*.yml tests/.work/actionlint/.github/workflows/*.yml; fi
	@echo "actionlint 通过"

deploy: ## 发布到 npm；DRY_RUN=1 只检查和打包，版本已发过则跳过
	@bash scripts/release.sh
