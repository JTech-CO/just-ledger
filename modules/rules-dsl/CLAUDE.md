# modules/rules-dsl — Haskell

예산 규칙 DSL: 렉서 · 파서(megaparsec) · 타입검사 · 평가기. JSONL stdin/stdout 배치.

## 소유 범위
`modules/rules-dsl/`. 산출물 `dist-newstyle/` 는 `.gitignore`. `budget.dsl_src` 원문을 평가한다.

## 명령
```
cd modules/rules-dsl && cabal build      # make build-dsl
cd modules/rules-dsl && cabal test       # make test-dsl
cd modules/rules-dsl && cabal run rules-dsl < fixtures/...   # make run-dsl (단독 실행)
```

## 규율
- 유효 규칙 20종 파싱 성공, **오류 규칙 20종은 소스 위치 정보(줄·열)와 함께 실패**한다 (M5 DoD 5).
- 금액·임계는 정수(최소 화폐 단위). 부동소수점 경유 금지.
- 모듈 단독 실행 가능해야 한다(`make run-dsl < fixtures/...`). 다른 모듈을 직접 import 하지 않는다.

## 참조
기술 백서 §3.2(megaparsec), §4.3(규칙 DSL) / 담당 phase: M5.
