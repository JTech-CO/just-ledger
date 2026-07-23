package sandbox

import _ "embed"

// preludeSource 는 규칙 작성 표준 라이브러리(money/text/date/rule)다.
// 샌드박스는 모든 규칙 실행 직전 이 청크를 DoString 으로 로드해 전역으로 노출한다.
// 순수 Lua 이며 금액은 문자열 정수로만 다룬다 (INV-4). 소스·단위 테스트는 prelude.lua
// / prelude_test.lua 참조.
//
//go:embed prelude.lua
var preludeSource string
