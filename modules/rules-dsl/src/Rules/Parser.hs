-- | 렉서 + megaparsec 파서. 십진 리터럴은 부동소수점을 경유하지 않고
-- 자릿수 그대로 Rational 로 만든다 (INV-4). 파스 오류는 줄·열과 함께
-- 구조화되어 반환된다.
module Rules.Parser
  ( parseProgram
  , ParseErr (..)
  ) where

import Control.Monad (void, when)
import Data.Char (isAlphaNum, isDigit)
import Data.List.NonEmpty qualified as NE
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void)
import Text.Megaparsec hiding (Pos)
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer qualified as L

import Rules.Syntax

data ParseErr = ParseErr
  { peLine :: Int
  , peCol  :: Int
  , peMsg  :: Text
  }
  deriving (Show)

type P = Parsec Void Text

-- ── 렉서 계층 ───────────────────────────────────────────────────────────────

sc :: P ()
sc = L.space space1 (L.skipLineComment "--") empty

lexeme :: P a -> P a
lexeme = L.lexeme sc

symbol :: Text -> P Text
symbol = L.symbol sc

getPos :: P Pos
getPos = do
  sp <- getSourcePos
  pure (Pos (unPos (sourceLine sp)) (unPos (sourceColumn sp)))

keywords :: [Text]
keywords =
  [ "budget", "per", "day", "week", "month", "year", "where", "account"
  , "in", "alert", "when", "rule", "tag", "notify", "set", "matches"
  , "recurring", "and", "or", "not", "spent", "limit", "amount", "merchant"
  ]

keyword :: Text -> P ()
keyword k = lexeme . try $ do
  void (string k)
  notFollowedBy (satisfy (\c -> isAlphaNum c || c == '_'))

-- | 큰따옴표 문자열 (한 줄, 이스케이프 없음)
stringLit :: P (Text, Pos)
stringLit = lexeme $ do
  p <- getPos
  void (char '"')
  s <- takeWhileP (Just "문자열 내용") (\c -> c /= '"' && c /= '\n')
  void (char '"') <?> "닫는 큰따옴표"
  pure (s, p)

-- | 부호 없는 정수 리터럴
intLit :: P (Integer, Pos)
intLit = lexeme $ do
  p <- getPos
  ds <- takeWhile1P (Just "숫자") isDigit
  notFollowedBy (char '.') <?> "정수 (소수점 불가)"
  pure (read (T.unpack ds), p)

-- | 십진 리터럴 — float 미경유. 3.25 → 325 % 100
numLit :: P (Rational, Pos)
numLit = lexeme $ do
  p <- getPos
  ip <- takeWhile1P (Just "숫자") isDigit
  mfrac <- optional (char '.' *> takeWhile1P (Just "소수부") isDigit)
  let ipN = read (T.unpack ip) :: Integer
  pure $ case mfrac of
    Nothing -> (ipN % 1, p)
    Just fp ->
      let k = T.length fp
          fpN = read (T.unpack fp) :: Integer
       in ((ipN * 10 ^ k + fpN) % (10 ^ k), p)

-- | 통화 코드: 대문자 3자
currencyLit :: P (Text, Pos)
currencyLit = lexeme $ do
  p <- getPos
  cs <- takeWhile1P (Just "통화 코드(대문자)") (\c -> c >= 'A' && c <= 'Z')
  when (T.length cs /= 3) $
    fail ("통화 코드는 대문자 3자여야 합니다: " ++ T.unpack cs)
  pure (cs, p)

-- | 계정 코드: 숫자열 (문자열이 아니라 토큰)
accountCode :: P (Text, Pos)
accountCode = lexeme $ do
  p <- getPos
  ds <- takeWhile1P (Just "계정 코드") isDigit
  pure (ds, p)

-- | /대안1|대안2/ — 리터럴 대안만 지원하는 regex 서브셋.
--   지원 밖 메타문자는 검사 단계가 아니라 여기서 즉시 위치와 함께 거절한다.
regexLit :: P ([Text], Pos)
regexLit = lexeme $ do
  p <- getPos
  void (char '/')
  body <- takeWhileP (Just "패턴") (\c -> c /= '/' && c /= '\n')
  void (char '/') <?> "닫는 슬래시"
  let metas = "\\.*+?[](){}^$" :: String
      bad = T.filter (`elem` metas) body
  when (not (T.null bad)) $
    fail ("지원하지 않는 패턴 메타문자: " ++ T.unpack bad ++ " (리터럴 대안 | 만 지원)")
  let alts = T.splitOn "|" body
  when (any T.null alts) $ fail "빈 대안이 있습니다"
  pure (alts, p)

-- ── 파서 ────────────────────────────────────────────────────────────────────

parseProgram :: Text -> Either [ParseErr] Program
parseProgram src =
  case parse (sc *> some stmt <* eof) "<dsl>" src of
    Right p -> Right p
    Left bundle -> Left (toErrs bundle)

toErrs :: ParseErrorBundle Text Void -> [ParseErr]
toErrs bundle =
  [ ParseErr (unPos (sourceLine sp)) (unPos (sourceColumn sp))
             (T.pack (parseErrorTextPretty e))
  | (e, sp) <- NE.toList . fst $
      attachSourcePos errorOffset (bundleErrors bundle) (bundlePosState bundle)
  ]

stmt :: P Stmt
stmt = (SBudget <$> budget) <|> (SRule <$> rule)

budget :: P Budget
budget = do
  keyword "budget"
  name <- stringLit
  keyword "per"
  period <- periodP
  void (symbol "<=")
  limit <- intLit
  cur <- currencyLit
  accounts <- option [] $ do
    keyword "where"
    keyword "account"
    keyword "in"
    between (symbol "(") (symbol ")") (accountCode `sepBy1` symbol ",")
  malert <- optional $ do
    keyword "alert"
    keyword "when"
    cond
  pure (Budget name period limit cur accounts malert)

periodP :: P (Period, Pos)
periodP = do
  p <- getPos
  per <- choice
    [ PerDay <$ keyword "day"
    , PerWeek <$ keyword "week"
    , PerMonth <$ keyword "month"
    , PerYear <$ keyword "year"
    ] <?> "기간 단위 (day|week|month|year)"
  pure (per, p)

rule :: P Rule
rule = do
  keyword "rule"
  act <- action
  keyword "when"
  Rule act <$> cond

action :: P Action
action = choice
  [ ATag <$> (keyword "tag" *> stringLit)
  , ANotify <$> (keyword "notify" *> stringLit)
  , ASetAccount <$> (keyword "set" *> keyword "account" *> accountCode)
  ] <?> "동작 (tag|notify|set account)"

-- 조건 문법은 '(' 시작에서만 중의적이다(괄호 조건 vs 괄호 식으로 시작하는
-- 비교). 비교식 좌변 피연산자를 파싱한 뒤에는 커밋한다 — try 로 조건 시작
-- 위치까지 되감지 않으므로 조건식 내부 오류가 실제 문제 토큰의 줄·열로
-- 보고된다 (M5 DoD 5).
cond :: P Cond
cond = andExpr >>= orRest

orRest :: Cond -> P Cond
orRest x = (do keyword "or"; y <- andExpr; orRest (COr x y)) <|> pure x

andExpr :: P Cond
andExpr = notExpr >>= andRest

andRest :: Cond -> P Cond
andRest x = (do keyword "and"; y <- notExpr; andRest (CAnd x y)) <|> pure x

notExpr :: P Cond
notExpr = (CNot <$> (keyword "not" *> notExpr)) <|> atom

-- | 첫 원자가 이미 파싱된 뒤의 and/or 연속 (우선순위: and > or)
condCont :: Cond -> P Cond
condCont c = andRest c >>= orRest

atom :: P Cond
atom = choice
  [ recurringAtom
  , matchesAtom
  , parenAtom
  , comparison
  ] <?> "조건"

recurringAtom :: P Cond
recurringAtom = do
  p <- getPos
  keyword "recurring"
  pure (CRecurring p)

matchesAtom :: P Cond
matchesAtom = do
  p <- getPos
  keyword "merchant"
  keyword "matches"
  (alts, _) <- regexLit
  pure (CMatches p alts)

-- | 키워드로 시작이 확정되는 조건 원자 — 괄호 내부 판별용
condKwAtom :: P Cond
condKwAtom = choice
  [ recurringAtom
  , matchesAtom
  , CNot <$> (keyword "not" *> notExpr)
  ]

-- | '(' 시작 원자: 괄호 조건이거나, 괄호 식을 좌변으로 하는 비교.
-- '(' 소비 후에는 group 이 내부를 판별하며 백트래킹하지 않는다.
parenAtom :: P Cond
parenAtom = do
  pOpen <- getPos
  void (symbol "(")
  g <- group
  case g of
    Left c -> pure c
    Right e -> do
      lhs <- termRest e >>= exprRest
      finishCmp pOpen lhs

-- | '(' 를 이미 소비한 상태에서 짝이 되는 ')' 까지 파싱.
-- Left = 내부가 조건(괄호 전체가 조건 원자), Right = 내부가 식(비교 좌변 factor).
group :: P (Either Cond Expr)
group = choice
  [ do c <- condKwAtom          -- recurring / merchant matches / not — 조건 확정
       c2 <- condCont c
       void (symbol ")")
       pure (Left c2)
  , do pInner <- getPos          -- 중첩 '(' — 재귀 판별
       void (symbol "(")
       g <- group
       case g of
         Left c -> do            -- '(' 조건 ')' 은 조건 원자 — and/or 연속 가능
           c2 <- condCont c
           void (symbol ")")
           pure (Left c2)
         Right e -> do           -- '(' 식 ')' 은 factor — 산술 연속 후 판별
           e2 <- termRest e >>= exprRest
           exprGroupEnd pInner e2
  , do pE <- getPos              -- 숫자 / spent / limit / amount — 식 시작, 커밋
       e <- expr
       exprGroupEnd pE e
  ]

-- | 괄호 내부 식이 완성된 뒤: ')' 면 괄호 식, 비교 연산자면 괄호 조건
exprGroupEnd :: Pos -> Expr -> P (Either Cond Expr)
exprGroupEnd pStart e = choice
  [ Right e <$ symbol ")"
  , do c <- finishCmp pStart e
       c2 <- condCont c
       void (symbol ")")
       pure (Left c2)
  ]

-- | 비교식 — 좌변 소비 즉시 커밋 (try 없음)
comparison :: P Cond
comparison = do
  p <- getPos
  lhs <- expr
  finishCmp p lhs

finishCmp :: Pos -> Expr -> P Cond
finishCmp p lhs = do
  op <- choice
    [ OpGe <$ symbol ">=", OpLe <$ symbol "<="
    , OpGt <$ symbol ">", OpLt <$ symbol "<"
    , OpEq <$ symbol "==", OpNe <$ symbol "!="
    ] <?> "비교 연산자"
  CCmp p op lhs <$> expr

expr :: P Expr
expr = term >>= exprRest

exprRest :: Expr -> P Expr
exprRest x = choice
  [ do p <- getPos; void (symbol "+"); y <- term; exprRest (EAdd p x y)
  , do p <- getPos; void (symbol "-"); y <- term; exprRest (ESub p x y)
  , pure x
  ]

term :: P Expr
term = factor >>= termRest

termRest :: Expr -> P Expr
termRest x = choice
  [ do p <- getPos; void (symbol "*"); y <- factor; termRest (EMul p x y)
  , pure x
  ]

factor :: P Expr
factor = choice
  [ do (r, p) <- numLit
       mcur <- optional (try currencyLit)
       pure $ case mcur of
         Nothing -> ENum p r
         Just (c, _) -> EMoney p r c
  , do p <- getPos; keyword "spent"; pure (EVar p VSpent)
  , do p <- getPos; keyword "limit"; pure (EVar p VLimit)
  , do p <- getPos; keyword "amount"; pure (EVar p VAmount)
  , between (symbol "(") (symbol ")") expr
  ] <?> "피연산자"

-- 예약어 충돌 방지 참고: 식별자 자유 변수는 문법에 없으므로 keywords 목록은
-- 문서화 용도다. 사용하지 않는 바인딩 경고를 피하기 위해 참조만 남긴다.
_keywordsDoc :: [Text]
_keywordsDoc = keywords
