#!/usr/bin/env lua5.4
-- 언어 구성 게이트 (M9 DoD, 기술 백서 §8.3)
--
-- `github-linguist --json` 출력을 stdin 으로 받아 세 가지를 검사한다.
--   1. 메인(JavaScript) 제외 계측 대상 언어가 전부 min% 이상
--   2. 계측 대상 11개 외의 언어가 통계에 등장하지 않음
--   3. 메인이 max-main% 를 초과하지 않음
-- 하나라도 위반하면 사유를 출력하고 종료코드 1 로 빌드를 실패시킨다.
--
-- 이 스크립트는 매 푸시마다 실제 실행되는 코드이며, 비율을 맞추기 위한
-- 패딩이 아니라 게이트 자체다. 비율 조정은 기능·골든 테스트 추가로만 한다.
--
-- CLI 사용:
--   github-linguist --json | lua5.4 linguist-gate.lua \
--       --main JavaScript --min 5.0 --max-main 35.0
--
-- 테스트에서는 require("linguist-gate") 로 순수 함수(evaluate)를 직접 검증한다
-- (서브프로세스 없음 — 컨테이너 seccomp 환경에서 os.execute 가 ENOSYS 로 막힘).

local M = {}

-- 계측 대상 11개 언어. github-linguist 가 출력하는 정식 명칭과 일치해야 한다.
M.MEASURED = {
  ["JavaScript"] = true, ["Go"] = true, ["Rust"] = true, ["Elixir"] = true,
  ["Haskell"] = true, ["COBOL"] = true, ["PLpgSQL"] = true, ["R"] = true,
  ["Prolog"] = true, ["Julia"] = true, ["Lua"] = true,
}

-- github-linguist --json 은 { "Lang": {size=, percentage="x.xx"}, ... } 형태.
-- 방어적으로 숫자/문자열 백분율을 모두 허용한다.
function M.pct(v)
  if type(v) == "number" then return v end
  if type(v) == "table" then
    local p = v.percentage or v.percent
    if type(p) == "number" then return p end
    if type(p) == "string" then return tonumber(p) end
  end
  return nil
end

-- 핵심 판정. data = {lang -> linguist 항목}, opt = {main, min, max_main}.
-- 반환: failures(위반 사유 배열), seen({lang -> percent})
function M.evaluate(data, opt)
  local failures = {}
  local seen = {}

  for lang, v in pairs(data) do
    local p = M.pct(v)
    seen[lang] = p
    -- 검사 2: 허용 목록 밖 언어 등장
    if not M.MEASURED[lang] then
      failures[#failures + 1] = string.format(
        "미허용 언어가 통계에 등장: %s (%.2f%%). .gitattributes 로 제외하거나 계측 대상에 추가하세요.",
        lang, p or 0)
    end
  end

  for lang in pairs(M.MEASURED) do
    local p = seen[lang]
    if not p then
      failures[#failures + 1] = string.format(
        "계측 대상 언어 누락: %s (0%%). 실제 코드/골든 테스트를 추가하세요.", lang)
    elseif lang == opt.main then
      -- 검사 3: 메인 상한
      if p > opt.max_main then
        failures[#failures + 1] = string.format("메인 %s %.2f%% > 상한 %.2f%%", lang, p, opt.max_main)
      end
    else
      -- 검사 1: 비메인 하한
      if p < opt.min then
        failures[#failures + 1] = string.format("%s %.2f%% < 하한 %.2f%%", lang, p, opt.min)
      end
    end
  end

  return failures, seen
end

-- 사람이 읽는 리포트를 out(기본 io.write)으로 출력한다.
function M.report(seen, failures, opt, out)
  out = out or io.write
  local order = {}
  for lang in pairs(seen) do order[#order + 1] = lang end
  table.sort(order, function(a, b) return (seen[a] or 0) > (seen[b] or 0) end)

  out("== 언어 구성 (메인=" .. opt.main ..
    string.format(", 하한=%.1f%%, 상한=%.1f%%) ==\n", opt.min, opt.max_main))
  for _, lang in ipairs(order) do
    local mark = M.MEASURED[lang] and " " or "!"
    out(string.format("  %s %-12s %6.2f%%\n", mark, lang, seen[lang] or 0))
  end

  if #failures > 0 then
    out("\nFAIL: 언어 구성 게이트 위반 " .. #failures .. "건\n")
    for _, m in ipairs(failures) do out("  - " .. m .. "\n") end
  else
    out("\nOK: 언어 구성 게이트 통과\n")
  end
end

-- ── CLI 진입점 ───────────────────────────────────────────────────────────
local function main()
  local json = require("dkjson")

  local opt = { main = "JavaScript", min = 5.0, max_main = 35.0 }
  local i = 1
  while i <= #arg do
    local k = arg[i]
    if k == "--main" then opt.main = arg[i + 1]; i = i + 2
    elseif k == "--min" then opt.min = tonumber(arg[i + 1]); i = i + 2
    elseif k == "--max-main" then opt.max_main = tonumber(arg[i + 1]); i = i + 2
    else io.stderr:write("unknown arg: " .. tostring(k) .. "\n"); os.exit(2) end
  end
  if not opt.min or not opt.max_main then
    io.stderr:write("FATAL: --min / --max-main 는 숫자여야 합니다\n"); os.exit(2)
  end

  local raw = io.read("*a")
  if not raw or raw == "" then
    io.stderr:write("FATAL: stdin 이 비어 있습니다 (github-linguist --json 을 파이프하세요)\n")
    os.exit(2)
  end
  local data, _, derr = json.decode(raw)
  if not data then
    io.stderr:write("FATAL: JSON 파싱 실패: " .. tostring(derr) .. "\n"); os.exit(2)
  end

  local failures, seen = M.evaluate(data, opt)
  M.report(seen, failures, opt)
  os.exit(#failures > 0 and 1 or 0)
end

-- require 로 로드되면 모듈 테이블을 반환하고, 직접 실행되면 CLI 로 동작한다.
local modname = ...
if type(modname) == "string" and modname:find("linguist%-gate") then
  return M
end
main()
