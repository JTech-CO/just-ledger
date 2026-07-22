-- | AST — 모든 노드가 소스 위치(줄·열)를 지닌다. 오류는 반드시 위치와 함께
-- 보고된다 (M5 DoD 5). 금액은 Integer(최소 화폐 단위), 스칼라 계수는
-- Rational(정수 쌍) — 부동소수점 타입은 이 모듈 어디에도 없다 (INV-4).
module Rules.Syntax
  ( Pos (..)
  , Program
  , Stmt (..)
  , Budget (..)
  , Rule (..)
  , Action (..)
  , Period (..)
  , Cond (..)
  , CmpOp (..)
  , Expr (..)
  , Var (..)
  , exprPos
  , condMoneys
  , exprMoneys
  ) where

import Data.Text (Text)

-- | 1-기준 줄·열
data Pos = Pos { pLine :: Int, pCol :: Int }
  deriving (Eq, Ord, Show)

type Program = [Stmt]

data Stmt = SBudget Budget | SRule Rule
  deriving (Show)

data Budget = Budget
  { bName     :: (Text, Pos)
  , bPeriod   :: (Period, Pos)
  , bLimit    :: (Integer, Pos)   -- ^ 최소 화폐 단위 양의 정수
  , bCurrency :: (Text, Pos)
  , bAccounts :: [(Text, Pos)]    -- ^ where account in (...) — 비면 전 계정
  , bAlert    :: Maybe Cond
  }
  deriving (Show)

data Rule = Rule
  { rAction :: Action
  , rCond   :: Cond
  }
  deriving (Show)

data Action
  = ATag (Text, Pos)
  | ANotify (Text, Pos)
  | ASetAccount (Text, Pos)
  deriving (Show)

data Period = PerDay | PerWeek | PerMonth | PerYear
  deriving (Eq, Show)

data Cond
  = COr Cond Cond
  | CAnd Cond Cond
  | CNot Cond
  | CCmp Pos CmpOp Expr Expr
  | CRecurring Pos
  | CMatches Pos [Text]           -- ^ 리터럴 대안 목록 (regex 서브셋)
  deriving (Show)

data CmpOp = OpGt | OpGe | OpLt | OpLe | OpEq | OpNe
  deriving (Eq, Show)

data Expr
  = ENum Pos Rational             -- ^ 십진 리터럴 (무차원 Scalar)
  | EMoney Pos Rational Text      -- ^ 통화 접미 리터럴 (Money) — 예: 50000 KRW
  | EVar Pos Var
  | EAdd Pos Expr Expr
  | ESub Pos Expr Expr
  | EMul Pos Expr Expr
  deriving (Show)

data Var = VSpent | VLimit | VAmount
  deriving (Eq, Show)

exprPos :: Expr -> Pos
exprPos e = case e of
  ENum p _     -> p
  EMoney p _ _ -> p
  EVar p _     -> p
  EAdd p _ _   -> p
  ESub p _ _   -> p
  EMul p _ _   -> p

-- | 조건식 안의 Money 리터럴 (통화, 위치) 를 소스 등장 순서로 수집한다.
-- 검사 단계(rule 스코프 단일 통화 강제)와 평가 단계(txn 통화 가드)가 공유.
condMoneys :: Cond -> [(Text, Pos)]
condMoneys c = case c of
  COr a b      -> condMoneys a ++ condMoneys b
  CAnd a b     -> condMoneys a ++ condMoneys b
  CNot a       -> condMoneys a
  CCmp _ _ a b -> exprMoneys a ++ exprMoneys b
  CRecurring _ -> []
  CMatches _ _ -> []

exprMoneys :: Expr -> [(Text, Pos)]
exprMoneys e = case e of
  EMoney p _ cur -> [(cur, p)]
  EAdd _ a b     -> exprMoneys a ++ exprMoneys b
  ESub _ a b     -> exprMoneys a ++ exprMoneys b
  EMul _ a b     -> exprMoneys a ++ exprMoneys b
  ENum _ _       -> []
  EVar _ _       -> []
