# apps/web — JavaScript (메인)

Fastify 서버 + React 18/Vite 클라이언트. **TypeScript 미도입**, ESM + JSDoc `@typedef`.

## 소유 범위
`apps/web/` 만. 다른 모듈 파일을 수정하지 않는다. 어댑터(`server/adapters/`)는 worker/prolog/realtime 호출 인터페이스만 정의하고, 구현 언어 모듈은 계약으로만 붙는다.

## 명령
```
cd apps/web && pnpm install --frozen-lockfile && pnpm build   # make build-web
cd apps/web && pnpm lint          # ESLint
cd apps/web && pnpm format        # 포매터
cd apps/web && pnpm test:api      # make test-api — 왕복 + 계약 검증
cd apps/web && pnpm test:ui       # make test-ui — 컴포넌트 + 가상 스크롤
cd apps/web && pnpm test:a11y     # make a11y
make check-no-float               # INV-4 정적 검사
```

## 규율
- **금액은 `BigInt` 또는 문자열만.** `Number`·`parseFloat`·`toFixed`·`Math.round` 를 금액에 쓰지 않는다 (INV-4). API 경계는 문자열(`BigInt` 는 `JSON.stringify` 불가).
- 계약 타입은 `contracts/*.schema.json` → JSDoc `@typedef` 로 확보한다. 타입을 손으로 재정의하지 않는다.
- 검증은 `ajv` (`strict: true`) + `contracts/` 로 클라이언트·서버 동일 파일을 쓴다. 스키마 위반 요청은 400.
- 실시간 이벤트는 `store/ledgerStore.js` 의 `applyRealtime` 단일 진입점에서만 병합한다. 컴포넌트가 채널을 직접 구독하지 않는다.
- subprocess/외부 호출 인자에 사용자 입력(파일명·메모)을 직접 넣지 않는다.

## 참조
기술 백서 §2.2, §3.1, §4.1 / 디자인 백서 전체 / 담당 phase: M2, M8.
