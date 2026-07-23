#!/usr/bin/env bash
# M9 DoD 5 — 전체 스택 스모크.
#   클린 기동(db + 마이그레이션 + worker/web/prolog/realtime) → 헬스 → web E2E → 정리.
#
# compose 만으로는 스택이 완주하지 못하는 3개 격차를 이 스크립트가 메운다:
#   1. worker 실행 바이너리(bin/, gitignore)를 선빌드한다.
#   2. compose 에 마이그레이션 스텝이 없다 — psql 로 0001 을 선적용한다(\ir 상대경로 때문에 /workspace cwd).
#   3. realtime(prod)은 SECRET_KEY_BASE 가 필수 — 여기서 생성해 web·realtime 에 주입한다.
#
# 사용: bash infra/smoke.sh   (또는 make smoke). 호스트: Windows/Docker Desktop 또는 Linux.
set -uo pipefail
export MSYS_NO_PATHCONV=1                 # Git Bash 가 /workspace 를 윈도우 경로로 바꾸지 않게
cd "$(dirname "$0")/.."                    # 레포 루트
ROOT="$(pwd)"
COMPOSE="docker compose -f infra/compose.yaml"
IMAGE="just-ledger-dev:local"

FAIL=0
step() { echo; echo "── $* ──"; }
ok()   { echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; FAIL=1; }

cleanup() {
  step "정리 (compose down -v)"
  $COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── 0. 비밀·환경 ──────────────────────────────────────────────────────────
# SECRET_KEY_BASE: web(서명)·realtime(검증)이 공유. 리포에 굽지 않고 런타임 생성.
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 64 2>/dev/null \
  || head -c 48 /dev/urandom | base64 | tr -d '\n')}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-ledger}"

# ── 1. 선행 빌드 (compose 밖 산출물) ──────────────────────────────────────
step "선행 빌드: worker 바이너리 + realtime prod 빌드"
docker run --rm -v "$ROOT:/workspace" -v just-ledger-gomod:/go/pkg/mod \
  -w /workspace/services/worker "$IMAGE" go build -o bin/worker ./cmd/worker \
  && ok "worker 바이너리 빌드" || { bad "worker 빌드 실패"; exit 1; }
# realtime(prod): deps 를 prod 로 강제 재컴파일해 _build/prod 를 채운다.
#  · deps.compile 을 빠뜨리면 db_connection 이 prod 에 없어 기동 시 크래시한다.
#  · --force 없이는 stale _build/prod(구버전 dep 로 컴파일된 빔)를 그대로 두어
#    신버전 dep 의 신규 모듈(DBConnection.App 등)이 누락된 채 크래시한다.
docker run --rm -v "$ROOT:/workspace" -v jl-mix-cache:/root/.mix -v jl-hex-cache:/root/.hex \
  -w /workspace/services/realtime "$IMAGE" sh -lc '
    export MIX_ENV=prod
    mix local.hex --force --if-missing >/dev/null 2>&1
    mix local.rebar --force --if-missing >/dev/null 2>&1
    mix deps.get >/dev/null 2>&1 \
      && mix deps.compile --force >/dev/null 2>&1 \
      && mix compile >/dev/null 2>&1' \
  && ok "realtime prod 빌드(_build/prod)" || { bad "realtime prod 빌드 실패"; exit 1; }

# ── 2. db 기동 + healthy 대기 ─────────────────────────────────────────────
step "db 기동"
$COMPOSE up -d db >/dev/null 2>&1
DBID="$($COMPOSE ps -q db)"
for _ in $(seq 1 30); do
  h="$(docker inspect -f '{{.State.Health.Status}}' "$DBID" 2>/dev/null)"
  [ "$h" = "healthy" ] && break
  sleep 2
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$DBID" 2>/dev/null)" = "healthy" ] \
  && ok "db healthy" || { bad "db healthy 대기 실패"; exit 1; }

# ── 3. 마이그레이션 0001 적용 (psql, /workspace cwd) ──────────────────────
step "마이그레이션 0001 적용"
$COMPOSE run --rm --no-deps -w /workspace web \
  sh -lc 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/0001_init.up.pgsql >/dev/null && echo applied' \
  | grep -q applied \
  && ok "스키마·역할·트리거 적용" || { bad "마이그레이션 실패"; exit 1; }

# ── 4. 앱 서비스 기동 ─────────────────────────────────────────────────────
step "앱 서비스 기동 (web worker prolog realtime)"
$COMPOSE up -d web worker prolog realtime >/dev/null 2>&1 \
  && ok "compose up 요청" || { bad "compose up 실패"; exit 1; }

# ── 5. worker 레디니스 (HTTP 없음 — 컨테이너 running + 기동 로그) ─────────
step "worker 레디니스"
sleep 3
WID="$($COMPOSE ps -q worker)"
if [ -n "$WID" ] && [ "$(docker inspect -f '{{.State.Running}}' "$WID" 2>/dev/null)" = "true" ]; then
  for _ in $(seq 1 10); do
    $COMPOSE logs worker 2>&1 | grep -q "worker 기동" && break
    sleep 2
  done
  $COMPOSE logs worker 2>&1 | grep -q "worker 기동" \
    && ok "worker 기동(running + 로그)" || bad "worker 기동 로그 없음"
else
  bad "worker 컨테이너 미기동"
  $COMPOSE logs worker 2>&1 | tail -5
fi

# ── 6. HTTP 헬스 + web E2E (compose 네트워크 안에서 서비스 DNS 로) ────────
# 컨테이너 안에서 실행 → 호스트 포트 매핑에 의존하지 않고, Windows node 의
# undici keep-alive 종료 버그(libuv assertion)도 회피한다.
step "HTTP 헬스 + web 원장 E2E"
if $COMPOSE run --rm --no-deps \
     -e SMOKE_WEB=http://web:3000 \
     -e SMOKE_PROLOG=http://prolog:7070 \
     -e SMOKE_REALTIME=http://realtime:4000 \
     -w /workspace web node infra/smoke-e2e.mjs; then
  ok "E2E 스크립트 통과"
else
  bad "E2E 스크립트 실패"
fi

# ── 결과 ──────────────────────────────────────────────────────────────────
step "스모크 결과"
if [ "$FAIL" -eq 0 ]; then
  echo "  ✔ SMOKE 전부 통과 — 전체 스택 클린 기동 + 원장 E2E 검증 완료"
else
  echo "  ✘ SMOKE 실패 — 위 FAIL 항목 참조"
fi
exit "$FAIL"
