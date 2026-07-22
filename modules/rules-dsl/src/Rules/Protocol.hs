-- | JSONL stdin/stdout 프로토콜. 금액은 API 경계에서 문자열이다
-- (JS BigInt 와의 계약 — CLAUDE.md 금액 취급 규칙).
--
--   {"op":"check","src":"...","accounts":[{"code":"5210","currency":"KRW"}]}
--   {"op":"eval","src":"...","accounts":[...],
--    "spent":{"식비":"320000"},
--    "txn":{"amount_minor":"12900","currency":"KRW",
--           "merchant":"...","recurring":true}}
--
-- txn.currency 는 필수다 — 통화 무시 금액 비교를 프로토콜 차원에서 막는다.
-- eval 응답에는 spent 미제공으로 alert 를 평가하지 못한 budget 이름이
-- "skipped_budgets" 배열로 드러난다 (침묵 스킵 금지).
module Rules.Protocol
  ( handleLine
  , requestLines
  , parseMoney
  ) where

import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

import Rules.Check
import Rules.Eval
import Rules.Parser
import Rules.Syntax (Program, Stmt (..))

data Account = Account { acCode :: Text, acCurrency :: Text }

instance FromJSON Account where
  parseJSON = withObject "account" $ \o ->
    Account <$> o .: "code" <*> o .: "currency"

data Request
  = ReqCheck Text [Account]
  | ReqEval Text [Account] (Map Text Text) (Maybe TxnJson)

data TxnJson = TxnJson
  { tjAmount    :: Text
  , tjCurrency  :: Text
  , tjMerchant  :: Text
  , tjRecurring :: Bool
  }

instance FromJSON TxnJson where
  parseJSON = withObject "txn" $ \o ->
    TxnJson <$> o .: "amount_minor" <*> o .: "currency" <*> o .: "merchant"
            <*> o .:? "recurring" .!= False

instance FromJSON Request where
  parseJSON = withObject "request" $ \o -> do
    op <- o .: "op" :: Parser Text
    src <- o .: "src"
    accounts <- o .:? "accounts" .!= []
    case op of
      "check" -> pure (ReqCheck src accounts)
      "eval" -> ReqEval src accounts
        <$> o .:? "spent" .!= Map.empty
        <*> o .:? "txn"
      other -> fail ("알 수 없는 op: " <> T.unpack other)

-- | stdin 전문 → 처리할 요청 줄 목록. CRLF 입력의 후행 \r 을 벗긴 뒤
-- 빈 줄(\r 만 있던 줄 포함)을 스킵한다.
requestLines :: BL.ByteString -> [BL.ByteString]
requestLines input =
  filter (not . BL8.null) (map stripCR (BL8.lines input))
  where
    stripCR l
      | not (BL8.null l) && BL8.last l == '\r' = BL8.init l
      | otherwise = l

-- | 한 줄 처리: JSON 파싱 → DSL 컴파일(parse+check) → 필요 시 평가
handleLine :: BL.ByteString -> BL.ByteString
handleLine raw = case eitherDecode raw of
  Left e -> encode (object ["ok" .= False, "errors" .=
    [object ["line" .= (0 :: Int), "col" .= (0 :: Int),
             "message" .= ("JSON 파싱 실패: " <> T.pack e)]]])
  Right req -> case req of
    ReqCheck src accounts -> case compile src accounts of
      Left errs -> errResponse errs
      Right prog -> encode (object
        [ "ok" .= True
        , "budgets" .= length [() | SBudget _ <- prog]
        , "rules" .= length [() | SRule _ <- prog]
        ])
    ReqEval src accounts spentStr mtxn -> case compile src accounts of
      Left errs -> errResponse errs
      Right prog ->
        case (traverse parseMoney spentStr, traverse txnFacts mtxn) of
          (Right spent, Right facts) ->
            let accMap = Map.fromList
                  [(acCode a, acCurrency a) | a <- accounts]
                out = evalProgram accMap spent facts prog
             in encode (object
                  [ "ok" .= True
                  , "alerts" .= eoAlerts out
                  , "skipped_budgets" .= eoSkipped out
                  , "tags" .= eoTags out
                  , "notifies" .= eoNotifies out
                  , "set_account" .= eoSetAccount out
                  ])
          (Left e, _) -> badMoney e
          (_, Left e) -> badMoney e
  where
    badMoney e = encode (object ["ok" .= False, "errors" .=
      [object ["line" .= (0 :: Int), "col" .= (0 :: Int), "message" .= e]]])

txnFacts :: TxnJson -> Either Text TxnFacts
txnFacts t = do
  amt <- parseMoney (tjAmount t)
  pure (TxnFacts amt (tjCurrency t) (tjMerchant t) (tjRecurring t))

-- | 금액 문자열 → Integer. contracts common.schema.json#/$defs/moneyMinor 의
-- 패턴 ^(0|-?[1-9][0-9]{0,17})$ 과 정확히 같은 수용 집합 (INV-4 경계 방어).
-- "+5"·선행 0("007")·"-0"·19자리 이상·공백·소수점·지수는 전부 거절.
parseMoney :: Text -> Either Text Integer
parseMoney s
  | s == "0" = Right 0
  | wellFormed = Right (if neg then negate mag else mag)
  | otherwise =
      Left ("금액이 moneyMinor 패턴(^(0|-?[1-9][0-9]{0,17})$)에 맞지 않음: " <> s)
  where
    (neg, ds) = case T.stripPrefix "-" s of
      Just rest -> (True, rest)
      Nothing -> (False, s)
    wellFormed =
      not (T.null ds)
        && T.length ds <= 18
        && T.head ds /= '0'
        && T.all (\c -> c >= '0' && c <= '9') ds
    mag = T.foldl' (\acc c -> acc * 10 + toInteger (fromEnum c - fromEnum '0')) 0 ds

-- | 컴파일 = 파스 + 검사. 실패는 (줄, 열, 메시지) 목록.
compile :: Text -> [Account] -> Either [(Int, Int, Text)] Program
compile src accounts = do
  prog <- case parseProgram src of
    Left es -> Left [(peLine e, peCol e, peMsg e) | e <- es]
    Right p -> Right p
  let env = Env (Map.fromList [(acCode a, acCurrency a) | a <- accounts])
  case checkProgram env prog of
    [] -> Right prog
    es -> Left [(ceLine e, ceCol e, ceMsg e) | e <- es]

errResponse :: [(Int, Int, Text)] -> BL.ByteString
errResponse errs = encode (object
  [ "ok" .= False
  , "errors" .=
      [ object ["line" .= l, "col" .= c, "message" .= m]
      | (l, c, m) <- errs
      ]
  ])
