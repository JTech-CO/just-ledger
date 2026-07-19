# modules/settlement — COBOL (`.cbl` / `.cpy`)

월말 마감 정산, 이자, 상각, 은행가 반올림, 고정폭 리포트. 고정폭 stdin/stdout 배치.

> **copybook(`*.cpy`) 은 `contracts/` 와 함께 언어 간 단일 진실원천이다.** 레코드 레이아웃을 각 언어에서 손으로 재정의하지 않는다.

## 소유 범위
`modules/settlement/`. 산출 바이너리 `bin/` 는 `.gitignore`(binary 지정).

## 명령
```
cd modules/settlement && cobc -x -std=cobol2014 -O2 -o bin/settle settle.cbl   # make build-settlement
cd modules/settlement && ./tests/run.sh          # make test-settlement (골든)
make parity-settlement                            # INV-7 — COBOL ↔ JS 참조 구현 차이 0원
./modules/settlement/bin/settle < fixtures/...    # make run-settlement (단독)
```

## 규율 (INV-7 — 프로젝트 최중요 게이트)
- **10,000 txn 마감 결과가 JS 참조 구현(`decimal.js`)과 전 항목 일치, 차이 0원.** 불일치 1건이라도 있으면 마감을 커밋하지 않는다.
- **반올림 규칙·허용 오차를 조정해 통과시키지 않는다.** 반올림은 `ROUNDED MODE IS NEAREST-EVEN` 만 정본. 0.5 경계 전수 테스트 준수.
- copybook 레코드 길이 초과 입력은 **COBOL 실행 전에**(Go 측) 거절한다. 길이 초과는 조용히 절삭됨.
- `COMP-3` 부호 니블 표현은 플랫폼·컴파일 옵션 의존 → **컨테이너 이미지와 `cobc` 플래그 고정**, 골든 픽스처로 바이트 단위 회귀.
- 상각 스케줄 마지막 회차 종료 잔액 = 정확히 0. 마감 10,000 txn 2초 이내.

## 참조
기술 백서 §4.3(은행가 반올림·정합성 대조), §7 / 담당 phase: M5.
