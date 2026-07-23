SHELL := /bin/bash
.DEFAULT_GOAL := help

# 언어 비율 게이트 임계값 (docs/TECH-WHITEPAPER.md §8)
MAIN_LANG   := JavaScript
MIN_PCT     := 5.0
MAX_MAIN_PCT := 35.0

.PHONY: help
help: ## 사용 가능한 타깃 출력
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# 환경
# ---------------------------------------------------------------------------

.PHONY: toolchain-check
toolchain-check: ## 11개 툴체인 설치 및 버전 확인 (M0 DoD 1)
	@fail=0; \
	check() { name=$$1; shift; printf "  %-16s " "$$name"; \
	  if command -v "$$1" >/dev/null 2>&1; then "$$@" 2>&1 | head -n1; \
	  else echo "MISSING"; fail=1; fi; }; \
	echo "== just-ledger toolchain =="; \
	check "JavaScript"  node --version; \
	check "Go"          go version; \
	check "Rust"        rustc --version; \
	check "wasm-pack"   wasm-pack --version; \
	check "Haskell"     ghc --version; \
	check "COBOL"       cobc --version; \
	check "Prolog"      swipl --version; \
	check "R"           Rscript --version; \
	check "Julia"       julia --version; \
	check "Elixir"      elixir --version; \
	check "Lua"         lua5.4 -v; \
	check "PostgreSQL"  psql --version; \
	check "linguist"    github-linguist --version; \
	echo; \
	if [ $$fail -ne 0 ]; then echo "FAIL: 누락된 툴체인이 있습니다."; exit 1; fi; \
	echo "OK: 전체 툴체인 사용 가능"

.PHONY: up down logs clean
up: ## 전체 스택 기동
	docker compose -f infra/compose.yaml up -d
down: ## 전체 스택 종료
	docker compose -f infra/compose.yaml down
logs: ## 스택 로그 추적
	docker compose -f infra/compose.yaml logs -f
clean: ## 빌드 산출물 정리
	rm -rf apps/web/dist modules/statement-wasm/pkg modules/statement-wasm/target \
	       modules/rules-dsl/dist-newstyle services/realtime/_build services/worker/bin

# ---------------------------------------------------------------------------
# 빌드
# ---------------------------------------------------------------------------

.PHONY: build build-web build-worker build-wasm build-dsl build-settlement build-realtime
build: build-wasm build-dsl build-settlement build-worker build-realtime build-web ## 전체 빌드

build-web: build-wasm ## JavaScript — Fastify + React (클라이언트가 wasm pkg 를 임포트)
	cd apps/web && pnpm install --frozen-lockfile && pnpm build

build-worker: ## Go — 워커 (Lua 샌드박스 포함)
	cd services/worker && go build -o bin/worker ./cmd/worker

build-wasm: ## Rust — 명세서 파싱 WASM
	cd modules/statement-wasm && wasm-pack build --target web --release

build-dsl: ## Haskell — 예산 규칙 DSL
	cd modules/rules-dsl && cabal build

build-settlement: ## COBOL — 마감 정산 배치 (settle + amort)
	bash modules/settlement/build.sh

build-realtime: ## Elixir — Phoenix 실시간
	cd services/realtime && mix deps.get && MIX_ENV=prod mix compile

# ---------------------------------------------------------------------------
# 테스트 (HARNESS.md 의 phase별 검증 명령)
# ---------------------------------------------------------------------------

.PHONY: test
test: test-db test-api test-ingest test-classify test-sandbox \
      test-settlement test-dsl test-analytics test-simulation test-realtime test-ui ## 전체 테스트

test-db: ## M1 — 스키마·불변식 (INV-1,2,3,5) + 롤업·RLS·NOTIFY
	bash db/tests/run.sh

test-api: ## M2 — API 왕복 + 계약 검증
	cd apps/web && pnpm test:api

test-ingest: ## M3 — 파싱·중복제거·암호화 (INV-6)
	cd modules/statement-wasm && cargo test
	cd services/worker && go test ./ingest/...

test-classify: ## M4 — 분류 정확도 + 이체 매칭 거짓양성 0 (INV-8)
	swipl -g run_tests -t halt services/prolog/tests/suite.prolog

test-sandbox: ## M4 — Lua 샌드박스 탈출 차단 + 타임아웃
	cd services/worker && go test ./sandbox/...

test-settlement: ## M5 — COBOL 마감 골든 + 고정폭 생성기 폭 초과 거절 (DoD 4)
	cd modules/settlement && ./tests/run.sh
	cd services/worker && go test ./settlement/...

test-dsl: ## M5 — 규칙 DSL 파싱·타입검사
	cd modules/rules-dsl && cabal test

test-analytics: ## M6 — R 결정론 + 이상치 탐지
	Rscript modules/analytics/tests/run.R

test-simulation: ## M6 — Julia 결정론 + 발산 없음
	julia --project=modules/simulation modules/simulation/test/runtests.jl

test-realtime: ## M7 — 채널 지연·유실·복구 (DATABASE_URL 있으면 통합까지)
	bash services/realtime/test-with-db.sh

test-ui: ## M8 — 컴포넌트 + 가상 스크롤
	cd apps/web && pnpm test:ui

# ---------------------------------------------------------------------------
# 불변식 게이트
# ---------------------------------------------------------------------------

.PHONY: parity-settlement check-no-float a11y bench-wasm
parity-settlement: build-settlement ## INV-7 — COBOL vs JS 참조 구현, 차이 0원
	node scripts/parity/settlement.mjs --fixtures fixtures/settlement --strict

check-no-float: ## INV-4 — 금액이 Number/float 경유하는 경로 0개
	node scripts/check-no-float.mjs apps/web services/worker scripts/parity fixtures/settlement

bench-wasm: ## M3 DoD 3 — 50MB CSV 파싱 3초 이내 (wasm-pack 빌드 선행 필요)
	node scripts/bench-wasm.mjs

a11y: ## M8 — 접근성 검사 (대비 AA·색각·reduced-motion) + 하드코딩 색상 0
	node scripts/check-hardcoded-color.mjs
	cd apps/web && pnpm test:a11y

# ---------------------------------------------------------------------------
# 모듈 단독 실행 (stdin/stdout 계약 확인)
# ---------------------------------------------------------------------------

.PHONY: run-settlement run-dsl run-analytics run-simulation
run-settlement: ## 고정폭 입력으로 COBOL 배치 단독 실행
	./modules/settlement/bin/settle
run-dsl: ## JSONL 입력으로 DSL 평가기 단독 실행
	cd modules/rules-dsl && cabal run rules-dsl
run-analytics: ## JSONL 입력으로 R 분석 단독 실행
	Rscript modules/analytics/main.R
run-simulation: ## JSONL 입력으로 Julia 시뮬레이션 단독 실행
	julia --project=modules/simulation modules/simulation/main.jl

# ---------------------------------------------------------------------------
# 언어 구성 (M9)
# ---------------------------------------------------------------------------

.PHONY: linguist linguist-gate
linguist: ## 언어 구성 비율 출력 (커밋된 파일 기준)
	@github-linguist --breakdown

linguist-gate: ## M9 게이트 — CI와 동일한 판정
	@github-linguist --json | lua5.4 scripts/linguist-gate.lua \
	  --main "$(MAIN_LANG)" --min "$(MIN_PCT)" --max-main "$(MAX_MAIN_PCT)"

# ---------------------------------------------------------------------------
# 품질
# ---------------------------------------------------------------------------

.PHONY: fmt lint
fmt: ## 언어별 포매터 일괄 적용
	cd apps/web && pnpm format
	cd services/worker && gofmt -w .
	cd modules/statement-wasm && cargo fmt
	cd services/realtime && mix format

lint: ## 언어별 린터 일괄 적용
	cd apps/web && pnpm lint
	cd services/worker && go vet ./...
	cd modules/statement-wasm && cargo clippy -- -D warnings
	cd services/realtime && mix credo
