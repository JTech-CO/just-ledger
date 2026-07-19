#!/usr/bin/env lua5.4
-- linguist-gate.lua 의 골든 테스트. 통과 1종 + 위반 4종의 종료코드를 검증한다.
-- 실행: lua5.4 scripts/tests/linguist-gate.test.lua  (레포 루트에서)

local self = arg[0] or ""
local base = self:match("^(.*)/tests/[^/]*$") or "scripts"
local GATE = base .. "/linguist-gate.lua"

-- {lang -> percent} 테이블을 github-linguist --json 형태 문자열로 만든다.
local function to_json(t)
  local parts = {}
  for lang, pct in pairs(t) do
    parts[#parts + 1] = string.format('%q:{"size":%d,"percentage":"%.2f"}',
      lang, math.floor(pct * 100 + 0.5), pct)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- gate 를 stdin 으로 실행하고 종료코드를 돌려준다.
local function run(dist)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write(to_json(dist))
  fh:close()
  local cmd = string.format(
    "lua5.4 %s --main JavaScript --min 5.0 --max-main 35.0 < %s > /dev/null 2>&1",
    GATE, tmp)
  local _, _, code = os.execute(cmd)
  os.remove(tmp)
  return code or -1
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
cases[#cases + 1] = { name = "JavaScript 40% > 35% 상한", dist = overmain, want = 1 }

-- 위반 4: 계측 대상 언어 누락
local missing = clone(PASS); missing.Julia = nil; missing.JavaScript = 34
cases[#cases + 1] = { name = "Julia 누락(0%)", dist = missing, want = 1 }

local fail = 0
for _, c in ipairs(cases) do
  local got = run(c.dist)
  local ok = (got == c.want)
  io.write(string.format("  [%s] %-28s want=%d got=%d\n",
    ok and "PASS" or "FAIL", c.name, c.want, got))
  if not ok then fail = 1 end
end

if fail ~= 0 then io.write("FAIL: linguist-gate 테스트 실패\n"); os.exit(1) end
io.write("OK: linguist-gate 테스트 통과\n")
os.exit(0)
