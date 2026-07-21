-- | M5 DoD 5 게이트: 유효 규칙 20종 파싱·검사 성공, 오류 규칙 20종이
-- 소스 위치(줄·열)와 함께 실패한다. 위치는 "오류가 난 토큰"을 정확히
-- 가리켜야 하며, 대부분 exact (줄, 열) 로 단언한다.
module Main (main) where

import Data.Aeson (Value (..), decode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Vector qualified as V
import System.Exit (exitFailure)

import Rules.Check
import Rules.Eval
import Rules.Parser
import Rules.Protocol (handleLine)
import Rules.Syntax

env :: Env
env = Env (Map.fromList [("5210", "KRW"), ("5211", "KRW"), ("6100", "USD")])

compile :: Text -> Either [(Int, Int, Text)] Program
compile src = do
  prog <- case parseProgram src of
    Left es -> Left [(peLine e, peCol e, peMsg e) | e <- es]
    Right p -> Right p
  case checkProgram env prog of
    [] -> Right prog
    es -> Left [(ceLine e, ceCol e, ceMsg e) | e <- es]

main :: IO ()
main = do
  failures <- newIORef (0 :: Int)
  let failWith msg = modifyIORef' failures (+ 1) >> putStrLn ("FAIL  " <> msg)
      ok msg = putStrLn ("pass  " <> msg)

      valid name src = case compile src of
        Right _ -> ok ("valid: " <> name)
        Left es -> failWith ("valid: " <> name <> " — 거절됨: " <> show (take 2 es))

      errAt name src (l, c) = case compile src of
        Right _ -> failWith ("error: " <> name <> " — 통과해버림")
        Left ((gl, gc, m) : _)
          | gl == l && gc == c -> ok ("error: " <> name)
          | otherwise ->
              failWith ("error: " <> name <> " — 위치 (" <> show gl <> ","
                <> show gc <> ") 기대 (" <> show l <> "," <> show c
                <> ") msg=" <> T.unpack m)
        Left [] -> failWith ("error: " <> name <> " — 빈 오류 목록")

      errLine name src l = case compile src of
        Right _ -> failWith ("error: " <> name <> " — 통과해버림")
        Left ((gl, gc, _) : _)
          | gl == l && gc > 0 -> ok ("error: " <> name)
          | otherwise ->
              failWith ("error: " <> name <> " — 줄 " <> show gl
                <> " 기대 " <> show l <> " (col " <> show gc <> ")")
        Left [] -> failWith ("error: " <> name <> " — 빈 오류 목록")

  -- ── 유효 20종 ─────────────────────────────────────────────────────────
  valid "V01 최소 budget" "budget \"기본\" per month <= 400000 KRW"
  valid "V02 where 1계정" "budget \"식비\" per month <= 400000 KRW where account in (5210)"
  valid "V03 where 2계정" "budget \"외식\" per month <= 300000 KRW where account in (5210, 5211)"
  valid "V04 per day" "budget \"일별\" per day <= 30000 KRW"
  valid "V05 per week" "budget \"주별\" per week <= 150000 KRW"
  valid "V06 per year" "budget \"연간\" per year <= 5000000 KRW"
  valid "V07 alert 기본" "budget \"a\" per month <= 400000 KRW alert when spent > limit"
  valid "V08 계수*한도" "budget \"a\" per month <= 400000 KRW alert when spent > 0.8 * limit"
  valid "V09 한도*계수" "budget \"a\" per month <= 400000 KRW alert when spent >= limit * 0.95"
  valid "V10 Money 뺄셈" "budget \"a\" per month <= 400000 KRW alert when spent > limit - 50000 KRW"
  valid "V11 괄호 덧셈" "budget \"a\" per month <= 400000 KRW alert when (spent + 10000 KRW) > limit"
  valid "V12 and 결합" "budget \"a\" per month <= 400000 KRW alert when spent > 0.5 * limit and spent > 100000 KRW"
  valid "V13 not/or" "budget \"a\" per month <= 400000 KRW alert when not (spent <= 0.8 * limit) or spent > 390000 KRW"
  valid "V14 rule matches" "rule tag \"구독\" when merchant matches /넷플릭스|스포티파이/"
  valid "V15 matches+recurring" "rule tag \"구독\" when merchant matches /넷플릭스/ and recurring"
  valid "V16 notify" "rule notify \"큰 지출\" when amount > 100000 KRW"
  valid "V17 set account" "rule set account 5211 when amount >= 500000 KRW"
  valid "V18 not recurring" "rule tag \"비정기\" when not recurring and merchant matches /택시/"
  valid "V19 다문장+USD"
    "budget \"국내\" per month <= 400000 KRW\nbudget \"해외\" per month <= 200 USD where account in (6100)\nrule tag \"구독\" when recurring"
  valid "V20 ==/or" "rule tag \"정확\" when amount == 12900 KRW or merchant matches /스포티파이/"

  -- ── 오류 20종 — 소스 위치와 함께 실패해야 한다 ────────────────────────
  errAt "E01 키워드 오타" "budgett \"x\" per month <= 1 KRW" (1, 1)
  errAt "E02 이름 따옴표 없음" "budget x per month <= 1 KRW" (1, 8)
  errLine "E03 문자열 미종결" "budget \"식비 per month <= 1 KRW" 1
  errAt "E04 잘못된 기간" "budget \"a\" per fortnight <= 1 KRW" (1, 16)
  errAt "E05 한도 소수" "budget \"a\" per month <= 1.5 KRW" (1, 26)
  errLine "E06 통화 누락" "budget \"a\" per month <= 400000" 1
  errAt "E07 소문자 통화" "budget \"a\" per month <= 1 krw" (1, 27)
  errLine "E08 regex 메타문자" "rule tag \"x\" when merchant matches /넷플.*릭스/" 1
  errLine "E09 빈 대안" "rule tag \"x\" when merchant matches /넷플릭스|/" 1
  errAt "E10 없는 계정" "budget \"a\" per month <= 1 KRW where account in (9999)" (1, 49)
  errAt "E11 계정 통화 불일치" "budget \"a\" per month <= 1 KRW where account in (6100)" (1, 49)
  errAt "E12 미지 통화" "budget \"a\" per month <= 1 JPY" (1, 27)
  errAt "E13 0 한도" "budget \"a\" per month <= 0 KRW" (1, 25)
  errAt "E14 중복 이름" "budget \"a\" per month <= 1 KRW\nbudget \"a\" per month <= 2 KRW" (2, 8)
  errAt "E15 rule 에서 spent" "rule tag \"x\" when spent > 1 KRW" (1, 19)
  errAt "E16 budget 에서 amount" "budget \"a\" per month <= 1 KRW alert when amount > 1 KRW" (1, 42)
  errAt "E17 Money vs Scalar" "budget \"a\" per month <= 1 KRW alert when spent > 0.8" (1, 42)
  errAt "E18 Money+Scalar" "budget \"a\" per month <= 1 KRW alert when spent + 5 > limit" (1, 48)
  errAt "E19 Money*Money" "budget \"a\" per month <= 1 KRW alert when spent * limit > limit" (1, 48)
  errAt "E20 소수 금액 리터럴" "budget \"a\" per month <= 1 KRW alert when spent > 0.5 KRW" (1, 50)

  -- ── 평가기 정합 (정확한 유리수 — float 없음) ──────────────────────────
  let v8src = "budget \"a\" per month <= 400000 KRW alert when spent > 0.8 * limit"
      evalWith spent = case compile v8src of
        Right prog ->
          eoAlerts (evalProgram (Map.fromList [("a", spent)]) Nothing prog)
        Left _ -> ["<컴파일 실패>"]
  case (evalWith 320000, evalWith 320001) of
    ([], ["a"]) -> ok "eval: 0.8*400000 경계 — 320000 미발화 / 320001 발화"
    other -> failWith ("eval: 경계 오동작 " <> show other)
  case compile "rule tag \"구독\" when merchant matches /넷플릭스|스포티파이/ and amount == 12900 KRW" of
    Right prog ->
      let out = evalProgram Map.empty
            (Just (TxnFacts 12900 "넷플릭스 월결제" False)) prog
       in if eoTags out == ["구독"]
            then ok "eval: matches 대안 + 금액 일치"
            else failWith ("eval: tags=" <> show (eoTags out))
    Left es -> failWith ("eval 컴파일 실패: " <> show es)
  case 0.8 * (400000 % 1) :: Rational of
    r | r == 320000 % 1 -> ok "eval: 0.8 은 정확한 4/5 (부동소수점 없음)"
      | otherwise -> failWith "Rational 리터럴 정합 실패"

  -- ── JSONL 프로토콜 왕복 (stdin/stdout 계약) ───────────────────────────
  let jsonRT name reqStr checks =
        case decode (handleLine (BL8.pack reqStr)) :: Maybe Value of
          Nothing -> failWith ("protocol: " <> name <> " — 응답이 JSON 이 아님")
          Just v
            | all (\(k, expectV) -> lookupKey k v == Just expectV) checks ->
                ok ("protocol: " <> name)
            | otherwise -> failWith ("protocol: " <> name <> " — " <> show v)
      lookupKey k (Object o) = KM.lookup (Key.fromString k) o
      lookupKey _ _ = Nothing
  jsonRT "check ok"
    "{\"op\":\"check\",\"src\":\"budget \\\"a\\\" per month <= 1 KRW\",\"accounts\":[{\"code\":\"5210\",\"currency\":\"KRW\"}]}"
    [("ok", Bool True), ("budgets", Number 1)]
  jsonRT "check 오류에 위치 포함"
    "{\"op\":\"check\",\"src\":\"budget \\\"a\\\" per month <= 0 KRW\",\"accounts\":[{\"code\":\"5210\",\"currency\":\"KRW\"}]}"
    [("ok", Bool False)]
  jsonRT "eval alert 발화"
    "{\"op\":\"eval\",\"src\":\"budget \\\"a\\\" per month <= 400000 KRW alert when spent > 0.8 * limit\",\"accounts\":[{\"code\":\"5210\",\"currency\":\"KRW\"}],\"spent\":{\"a\":\"320001\"}}"
    [("ok", Bool True), ("alerts", Array (V.fromList [String "a"]))]
  jsonRT "eval 금액 소수 거절"
    "{\"op\":\"eval\",\"src\":\"budget \\\"a\\\" per month <= 1 KRW\",\"accounts\":[{\"code\":\"5210\",\"currency\":\"KRW\"}],\"spent\":{\"a\":\"3.5\"}}"
    [("ok", Bool False)]

  n <- readIORef failures
  if n == 0
    then putStrLn "spec: 유효 20 / 오류 20 / 평가 3 — 전부 통과"
    else do
      putStrLn ("spec: " <> show n <> "건 실패")
      exitFailure
