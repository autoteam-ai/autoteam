# 本仓库的检查：make check = shellcheck + actionlint + 单元测试。
# 本机没装 shellcheck / actionlint 时用 docker 镜像跑。
SHELL := /bin/bash
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0
ACTIONLINT_IMAGE := rhysd/actionlint:1.7.12
SCRIPTS := bin/aiwf skills/ai-workflow/scripts/aiwf $(wildcard skills/ai-workflow/scripts/lib/*.sh) \
  $(wildcard skills/ai-workflow/assets/templates/ops/agents/scripts/*.sh) \
  tests/run.sh tests/lib.sh tests/render-workflows.sh $(wildcard tests/test_*.sh) $(wildcard tests/stubs/*)

.PHONY: check test lint shellcheck actionlint

check: lint test ## 全部检查

test: ## 单元测试（兼容 macOS 自带的 bash 3.2）
	bash tests/run.sh

lint: shellcheck actionlint

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck -x $(SCRIPTS); \
	else docker run --rm -e LANG=C.UTF-8 -v "$(CURDIR):/mnt" -w /mnt $(SHELLCHECK_IMAGE) -x $(SCRIPTS); fi

actionlint: ## 检查本仓库的 CI 和渲染后的工作流模板
	@rm -rf tests/.work/actionlint && bash tests/render-workflows.sh tests/.work/actionlint >/dev/null
	@if command -v actionlint >/dev/null 2>&1; then actionlint .github/workflows/*.yml tests/.work/actionlint/.github/workflows/*.yml; \
	else docker run --rm -v "$(CURDIR):/repo" -w /repo $(ACTIONLINT_IMAGE) .github/workflows/*.yml tests/.work/actionlint/.github/workflows/*.yml; fi
	@echo "actionlint 通过"
