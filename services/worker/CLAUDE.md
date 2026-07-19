# services/worker — Go

잡 큐, 스케줄러, 환율 폴링, subprocess 오케스트레이션. 상시 프로세스. Unix socket + JSON 으로 web 과 통신.

## 소유 범위
`services/worker/` (`queue/`, `schedule/`, `runner/`, `sandbox/`). Lua 샌드박스는 `sandbox/` 하위 — 별도 `CLAUDE.md` 참조.

## 명령
```
cd services/worker && go build -o bin/worker ./cmd/worker   # make build-worker
cd services/worker && go vet ./...                          # make lint (일부)
cd services/worker && gofmt -w .                            # make fmt (일부)
cd services/worker && go test ./ingest/...                  # make test-ingest (Go 측)
cd services/worker && go test ./sandbox/...                 # make test-sandbox
```

## 규율
- subprocess 는 셸을 경유하지 않고 **argv 배열**로 직접 실행한다. 파일명·메모가 인자로 들어가는 경로를 만들지 않는다.
- COBOL 고정폭 입력은 **레코드 길이·수치 범위를 Go 측에서 검증한 뒤** 전달한다. 길이 초과는 조용히 잘리므로 실행 전 차단 (M5 DoD 4).
- 배치 프로세스(COBOL/Haskell/R/Julia)는 요청마다 띄우지 않는다. 상주 또는 워커 기동 시 예열(Julia/Prolog JIT·로드 지연).
- 워커 강제 종료 후 재시작 시 미완료 배치를 자동 재개한다 (M3 DoD 5).
- 금액 관련 값은 `int64`(최소 화폐 단위). 부동소수점 경유 금지.

## 참조
기술 백서 §3.3, §4.2, §7 / 담당 phase: M3(큐·스케줄러·인제스트), M4(Lua 임베드), M5(고정폭 생성기).
