# 本仓库的检查：make check = shellcheck + actionlint + 单元测试。
# 上线：make deploy 打包并在干净仓库里装一遍（CI 每次合并都跑，产物给 Planner 验收）。
# 发版：make publish 发到 npm，由人执行（对外、撤不回）。
# 本机没装 shellcheck / actionlint 时用 docker 镜像跑。docker 里的 shellcheck 是静态
# 二进制、没有 locale 数据，默认输出格式会回显源码行，遇到中文就崩在 commitBuffer；
# --format=gcc 不回显源码行，绕开这个问题（设 LANG / LC_ALL 没用，试过）。
SHELL := /bin/bash
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0
ACTIONLINT_IMAGE := rhysd/actionlint:1.7.12
SCRIPTS := skills/autoteam/bin/autoteam scripts/release.sh tests/dev-sandbox.sh $(wildcard skills/autoteam/lib/*.sh) \
  $(wildcard skills/autoteam/templates/autoteam/scripts/*.sh) \
  tests/run.sh tests/lib.sh tests/render-workflows.sh $(wildcard tests/test_*.sh) $(wildcard tests/stubs/*)

.PHONY: check test lint shellcheck actionlint dev deploy publish selfhost selfhost-check

check: lint test selfhost-check ## 全部检查

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

selfhost-check: ## 本仓库自己那份 ops/agents 有没有跟模板漂移
	@bash ./autoteam diff --check

selfhost: ## 模板改了之后，把本仓库这份副本重新渲染一遍（不动 AUTOTEAM_DIFF_IGNORE 里的）
	@bash ./autoteam init --force

dev: ## 起一个沙盒仓库，用桩把 init / doctor 跑一遍；可重复执行
	@bash tests/dev-sandbox.sh

deploy: ## 打包 + 装进干净仓库跑一遍，产物在 build/pkg/（合并后由 CI 执行）
	@bash scripts/release.sh

publish: ## 发布到 npm，由人执行；DRY_RUN=1 只演练
	@bash scripts/release.sh --publish
