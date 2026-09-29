# 适配 make check / make dev / make deploy

三个目标是整套流程的地基：gate.yml 只调 `make check`，Implementer 开工先跑 `make dev`，deploy.yml 和 rollback.yml 只调 `make deploy`。`make check` 不够严，编排得再好也只是更快地把不合格的代码送进主干。

## 原则

- **一条命令跑完全部检查**，本地和 CI 跑的是同一条。能用类型系统、lint、依赖检查表达的约束，放进 `make check`，而不是写进 AGENTS.md 指望模型记住。
- 保留模板中的 `bash .autoteam/scripts/check-instruction-budget.sh`；`.autoteam/instruction-budget` 限制 eject 后的角色指令和 autopilot 行数，超限先删或合并旧规则。
- **失败就退出非 0**，不要 `|| true`，不要吞错误。
- **`make dev` 可以重复执行**：已经起来了就跳过或重启，不要报错；需要的依赖、数据库、迁移都在里面做完。项目有 docker compose 就优先用容器。
- **`make deploy` 在 GitHub Actions 里执行**，凭据从 secrets 来（deploy.yml 里给 `env:`），不要依赖本机状态。
- **`make deploy` 要等线上版本接口返回本次 `GITHUB_SHA` 再返回**（带超时，超时退出非 0）。deploy.yml 在它返回后就通知 Planner，只是触发平台部署就返回的话，Planner 验收时线上还是旧版本，会误判验收不通过。轮询示例见下文「等线上就绪」。
- 不知道项目怎么部署，就问用户，不要编一个。

## 识别技术栈

| 看到 | 大概率 |
|---|---|
| `package.json` 的 scripts | `lint` / `typecheck` / `test` / `build`；包管理器看 lock 文件（npm / pnpm / yarn / bun） |
| `Gemfile` + `config/application.rb` | Rails：rubocop、rspec 或 minitest；有 `compose.yml` 时测试多半在容器里跑 |
| `go.mod` | `go vet ./...`、`go test ./...`，常配 golangci-lint |
| `pyproject.toml` / `requirements*.txt` | ruff / flake8、mypy、pytest；看是 uv、poetry 还是 pip |
| `Cargo.toml` | `cargo clippy -- -D warnings`、`cargo test` |
| `compose.yml` / `docker-compose.yml` | `make dev` 用 `docker compose up -d` |
| `.github/workflows/*.yml` | 现有 CI 跑了什么，照搬到 `make check` |

## 例子

Node（pnpm）：

```make
check:
	pnpm install --frozen-lockfile
	pnpm lint
	pnpm typecheck
	pnpm test

dev:
	docker compose up -d db
	pnpm install
	pnpm db:migrate
	pnpm dev

deploy:
	pnpm build
	pnpm run deploy   # 例如 wrangler / vercel / fly，凭据来自 deploy.yml 的 secrets
```

Rails（测试在容器里跑）：

```make
check:
	docker compose run --rm web bin/rubocop
	docker compose run --rm web bin/rspec

dev:
	docker compose up -d db redis
	docker compose run --rm web bin/rails db:prepare
	docker compose up -d web

deploy:
	bin/kamal deploy
```

Go：

```make
check:
	go vet ./...
	golangci-lint run
	go test -race ./...
```

只有测试、没有其他检查的小项目，至少加上格式检查或静态检查中的一种。

## gate.yml 的运行时

`make check` 需要什么，就在 gate.yml 的 `pr-size` 之前加什么，例如：

```yaml
      - uses: actions/setup-node@v7
        with:
          node-version: 22
      - uses: pnpm/action-setup@v4
```

需要数据库的，用 `services:` 起 Postgres / Redis。deploy.yml 同理，另外把部署凭据从 secrets 传进 `make deploy` 的 `env:`。

## 等线上就绪

`make deploy` 触发部署后，轮询线上的版本接口（如 `/version`、`/healthz`，返回当前运行的 sha），等于 `GITHUB_SHA` 才返回。通用示例（bash 3.2 兼容，`VERSION_URL` 换成自己的地址）：

```bash
#!/usr/bin/env bash
# scripts/wait-for-sha.sh：等线上版本接口返回本次提交，超时退出 1
set -eu
url="${VERSION_URL:?}"; want="${GITHUB_SHA:?}"; timeout="${DEPLOY_WAIT_SECONDS:-600}"
start=$(date +%s)
while :; do
  got=$(curl -fsS --max-time 10 "$url" 2>/dev/null || true)
  case "$got" in *"$want"*) echo "线上已是 $want"; exit 0;; esac
  if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
    echo "超时：$url 返回 '$got'，期望 $want" >&2; exit 1
  fi
  sleep 10
done
```

Makefile 里：`deploy:` 先执行部署命令，再 `bash scripts/wait-for-sha.sh`。服务还没有返回 sha 的接口时，见 [repo.md](https://github.com/autoteam-ai/autoteam/blob/main/docs/setup/repo.md) 的 make deploy 一节。

## 验证

三个目标都实际跑一次：`make check` 全绿；`make dev` 连跑两次都成功；`make deploy` 至少确认命令和凭据来源正确（真正部署交给合并后的 deploy.yml）。把输出给用户看。
