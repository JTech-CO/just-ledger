# modules/analytics — R

STL 계절성 분해, MAD 이상치 탐지, 부트스트랩 초과 확률, ggplot 테마 토큰화 → SVG(라이트/다크 2벌). JSONL stdin + SVG 파일.

## 소유 범위
`modules/analytics/`. 산출 SVG 는 `report_artifact` 로 캐시.

## 명령
```
Rscript modules/analytics/tests/run.R        # make test-analytics
Rscript modules/analytics/main.R < fixtures/...   # make run-analytics (단독)
```

## 규율
- **고정 시드에서 재실행 시 산출물 바이트 단위 동일**(결정론, M6 DoD 1).
- 알려진 이상치 주입 데이터셋에서 재현율 ≥ 0.95, 거짓양성률 ≤ 0.05.
- 생성 SVG 는 라이트·다크 두 벌 모두 산출, 대비비 AA 충족. 색상은 디자인 토큰만 사용(하드코딩 hex 금지).
- 입력 해시가 동일하면 재실행 없이 캐시 반환.
- 금액은 정수(최소 화폐 단위)로 취급. 표시 포맷은 문자열 연산.

## 참조
기술 백서 §4.3(이상치 탐지), 디자인 백서 §4.3(`ReportChart`) / 담당 phase: M6.
