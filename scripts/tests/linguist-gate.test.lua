#!/usr/bin/env lua5.4
-- linguist-gate.lua 골든 테스트. 통과 1종 + 위반 4종 + 파싱 2종.
-- 서브프로세스를 띄우지 않고 require 로 판정 함수를 직접 검증한다
-- (컨테이너 seccomp 환경에서 os.execute 가 ENOSYS 로 차단되는 문제 회피).
-- 실행: lua5.4 scripts/tests/linguist-gate.test.lua  (레포 루트에서)

local self = arg[0] or ""
local base = self:match("^(.*)/tests/[^/]*$") or "scripts"
package.path = base .. "/?.lua;" .. package.path
local gate = require("linguist-gate")

local OPT = { main = "JavaScript", min = 5.0, max_main = 35.0 }

-- github-linguist --json 항목 형태({size, percentage="x.xx"})로 만든다.
local function dist(t)
  local d = {}
  for lang, pct in pairs(t) do
    d[lang] = { size = math.floor(pct * 100 + 0.5), percentage = string.format("%.2f", pct) }
  end
  return d
end

-- 목표 비율에 부합하는 통과 분포 (합 = 100).
local PASS = {
  JavaScript = 28, Go = 9, Rust = 9, Elixir = 8, Haskell = 8, COBOL = 8,
  PLpgSQL = 7, R = 6, Prolog = 6, Julia = 6, Lua = 5,
}

local function clone(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

local cases = {}
cases[#cases + 1] = { name = "통과 분포", dist = PASS, want = 0 }

-- 위반 1: 비메인 언어가 하한 미만
local below = clone(PASS); below.Lua = 4; below.JavaScript = 29
cases[#cases + 1] = { name = "Lua 4% < 5% 하한", dist = below, want = 1 }

-- 위반 2: 허용 목록 밖 언어 등장
local intruder = clone(PASS); intruder.Perl = 6; intruder.JavaScript = 22
cases[#cases + 1] = { name = "미허용 언어 Perl 등장", dist = intruder, want = 1 }

-- 위반 3: 메인이 상한 초과
local overmain = clone(PASS); overmain.JavaScript = 40; overmain.Go = 3
-- JavaScript>35 와 Go<5 두 건이 잡혀야 한다
cases[#cases + 1] = { name = "JS 40%>35% + Go 3%<5%", dist = overmain, want = 2 }

-- 위반 4: 계측 대상 언어 누락
local missing = clone(PASS); missing.Julia = nil; missing.JavaScript = 34
cases[#cases + 1] = { name = "Julia 누락(0%)", dist = missing, want = 1 }

local fail = 0
for _, c in ipairs(cases) do
  local failures = gate.evaluate(dist(c.dist), OPT)
  local ok = (#failures == c.want)
  io.write(string.format("  [%s] %-26s want=%d건 got=%d건\n",
    ok and "PASS" or "FAIL", c.name, c.want, #failures))
  if not ok then
    for _, m in ipairs(failures) do io.write("        · " .. m .. "\n") end
    fail = 1
  end
end

-- 파싱: linguist 의 문자열 백분율("7.35")과 숫자 둘 다 허용
local p1 = gate.pct({ size = 100, percentage = "7.35" })
local p2 = gate.pct(12.5)
local pok = (p1 == 7.35 and p2 == 12.5)
io.write(string.format("  [%s] %-26s (\"7.35\"→%s, 12.5→%s)\n",
  pok and "PASS" or "FAIL", "백분율 파싱", tostring(p1), tostring(p2)))
if not pok then fail = 1 end

-- 리포트가 위반 사유를 포함하는지 (문자열 수집)
local failures, seen = gate.evaluate(dist(below), OPT)
local buf = {}
gate.report(seen, failures, OPT, function(s) buf[#buf + 1] = s end)
local rep = table.concat(buf)
local rok = rep:find("FAIL") and rep:find("Lua") and rep:find("하한")
io.write(string.format("  [%s] %-26s\n", rok and "PASS" or "FAIL", "리포트에 위반 사유 표기"))
if not rok then fail = 1 end

if fail ~= 0 then io.write("FAIL: linguist-gate 테스트 실패\n"); os.exit(1) end
io.write("OK: linguist-gate 테스트 통과\n")
os.exit(0)
