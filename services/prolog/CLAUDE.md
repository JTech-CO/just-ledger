# services/prolog — Prolog (`.prolog`)

카테고리 추론, 이체 페어 매칭, 정기결제 탐지. 상시 HTTP 서비스(`library(http/thread_httpd)`), JSON.

> 확장자는 반드시 `.prolog` (`.pl` 은 Perl 로 오탐). `.gitattributes` 에 `linguist-language=Prolog` 명시됨.

## 소유 범위
`services/prolog/`. 사실 적재 인터페이스 → 규칙 → HTTP 서비스화.

## 명령
```
swipl -g run_tests -t halt services/prolog/tests/suite.prolog   # make test-classify
```

## 규율 (INV-8)
- **이체 페어 매칭 거짓양성 0건.** 1건이라도 발생 시 통과 금지.
- 정확도를 올리려고 **금액 근사 매칭을 도입하지 않는다.** 금액은 정확 일치.
- 분류 결과에 **근거 규칙명을 함께 반환**한다 (Inspector 표시용, M4 DoD 6).
- 분류 정확도 ≥ 0.90 (라벨링 골든 500건), 1,000건 분류 1초 이내.
- 상주 프로세스는 장시간 구동 시 메모리 누적 → 일 1회 재기동, 쿼리 후 명시적 정리.

## 참조
기술 백서 §3.2, §4.3(이체 페어 매칭·정기결제) / 담당 phase: M4.
