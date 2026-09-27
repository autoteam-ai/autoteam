# 本仓库的检查：make check = shellcheck + actionlint + 重复代码 + 单元测试。
# 上线：make deploy 打包并在干净仓库里装一遍（CI 每次合并都跑，产物给 Planner 验收）。
# 发版：make publish 发到 npm，由人执行（对外、撤不回）。
# 这些目标在本机、cloud runtime、CI 都进同一个开发镜像（dev/Dockerfile）执行，入口是
# scripts/in-container.sh；工具版本只写在 Dockerfile 里。镜像里设了 AUTOTEAM_DEV_IMAGE=1，
# 在镜像里（含 devcontainer）直接执行，不嵌套。
SHELL := /bin/bash
SCRIPTS := skills/autoteam/bin/autoteam scripts/release.sh scripts/in-container.sh tests/dev-sandbox.sh \
  $(wildcard skills/autoteam/lib/*.sh) $(wildcard skills/autoteam/templates/autoteam/scripts/*.sh) \
  tests/run.sh tests/lib.sh tests/render-workflows.sh $(wildcard tests/test_*.sh) $(wildcard tests/stubs/*)

.PHONY: check test lint shellcheck actionlint duplication dev deploy publish

ifneq ($(AUTOTEAM_DEV_IMAGE),1)

check test lint shellcheck actionlint duplication dev deploy: ## 进开发镜像执行同名目标
	@bash scripts/in-container.sh make $@

publish: ## 宿主机的 npm 配置只读挂进容器；远端 docker daemon 上挂载不了，直接报错
	@bash scripts/in-container.sh --npmrc make publish

else

check: lint duplication test ## 全部检查

test: ## 单元测试
	bash tests/run.sh

lint: shellcheck actionlint

shellcheck:
	shellcheck -x $(SCRIPTS)

actionlint: ## 检查本仓库的 CI 和渲染后的工作流模板
	@rm -rf tests/.work/actionlint && bash tests/render-workflows.sh tests/.work/actionlint >/dev/null
	actionlint .github/workflows/*.yml tests/.work/actionlint/.github/workflows/*.yml
	@echo "actionlint 通过"

duplication: ## 重复代码占比上限在 .jscpd.json 的 threshold：老项目按现状定值，只降不升
	jscpd --config .jscpd.json .

dev: ## 起一个沙盒仓库，用桩把 init / doctor 跑一遍；可重复执行
	@bash tests/dev-sandbox.sh

deploy: ## 打包 + 装进干净仓库跑一遍，产物在 build/pkg/（合并后由 CI 执行）
	@bash scripts/release.sh

publish: ## 发布到 npm，由人执行；DRY_RUN=1 只演练
	@bash scripts/release.sh --publish

endif
