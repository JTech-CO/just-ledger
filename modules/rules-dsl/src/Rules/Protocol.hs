-- | JSONL stdin/stdout 프로토콜. 금액은 API 경계에서 문자열이다
-- (JS BigInt 와의 계약 — CLAUDE.md 금액 취급 규칙).
--
--   {"op":"check","src":"...","accounts":[{"code":"5210","currency":"KRW"}]}
--   {"op":"eval","src":"...","accounts":[...],
--    "spent":{"식비":"320000"},
--    "txn":{"amount_minor":"12900","merchant":"...","recurring":true}}
module Rules.Protocol
  ( handleLine
  ) where

import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read qualified as TR

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

data TxnJson = TxnJson { tjAmount :: Text, tjMerchant :: Text, tjRecurring :: Bool }

instance FromJSON TxnJson where
  parseJSON = withObject "txn" $ \o ->
    TxnJson <$> o .: "amount_minor" <*> o .: "merchant"
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
            let out = evalProgram spent facts prog
             in encode (object
                  [ "ok" .= True
                  , "alerts" .= eoAlerts out
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
  pure (TxnFacts amt (tjMerchant t) (tjRecurring t))

-- | 금액 문자열 → Integer. 소수점·지수·공백은 거절 (INV-4 경계 방어).
parseMoney :: Text -> Either Text Integer
parseMoney s = case TR.signed TR.decimal s of
  Right (v, rest) | T.null rest -> Right v
  _ -> Left ("금액이 정수 문자열이 아님: " <> s)

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
