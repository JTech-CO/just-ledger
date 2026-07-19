# modules/simulation — Julia

몬테카를로 현금흐름, 상환 순서 DP 최적화. JSONL stdin/stdout 배치.

## 소유 범위
`modules/simulation/`. `Project.toml` 커밋, `Manifest.toml` 은 `.gitignore`.

## 명령
```
julia --project=modules/simulation modules/simulation/test/runtests.jl   # make test-simulation
julia --project=modules/simulation modules/simulation/main.jl < fixtures/...   # make run-simulation (단독)
```

## 규율
- **고정 시드에서 재실행 시 산출물 바이트 단위 동일**(결정론, M6 DoD 1).
- 몬테카를로 10,000 경로에서 `NaN`·발산 0건, 95% 신뢰구간 폭 기준 이하.
- **첫 호출 JIT 지연이 크다.** 워커 기동 시 더미 호출로 예열하고, 벤치마크는 예열 이후 측정.
- 입력 해시 동일 시 캐시 반환.
- 금액은 정수(최소 화폐 단위). 부동소수점은 통계 계산 내부에 한정하고, 금액 산출은 정수로 환원.

## 참조
기술 백서 §4.3(현금흐름 시뮬레이션), §7 / 담당 phase: M6.
