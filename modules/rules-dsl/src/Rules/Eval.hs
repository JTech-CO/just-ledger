-- | 평가기 — 검사를 통과한 프로그램을 사실(facts)에 적용한다.
-- 모든 산술은 Integer/Rational (정수 쌍) — 부동소수점 없음 (INV-4).
-- 비교는 Rational 의 정확한 교차곱 비교를 그대로 쓴다.
module Rules.Eval
  ( TxnFacts (..)
  , EvalOut (..)
  , evalProgram
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T

import Rules.Syntax

-- | 한 txn 에 대한 사실 (rule 평가용)
data TxnFacts = TxnFacts
  { tfAmountMinor :: Integer
  , tfMerchant    :: Text
  , tfRecurring   :: Bool
  }

data EvalOut = EvalOut
  { eoAlerts     :: [Text]        -- ^ 발화한 budget 이름
  , eoTags       :: [Text]
  , eoNotifies   :: [Text]
  , eoSetAccount :: Maybe Text
  }
  deriving (Show)

-- | spentByBudget: budget 이름 → 기간 내 지출(최소 화폐 단위).
-- 값이 없는 budget 의 alert 는 평가하지 않는다 (지출 0 으로 가정하지 않음 —
-- 호출 측이 명시적으로 0 을 넣어야 한다).
evalProgram :: Map Text Integer -> Maybe TxnFacts -> Program -> EvalOut
evalProgram spentByBudget mtxn prog = EvalOut
  { eoAlerts = mapMaybe fireBudget [b | SBudget b <- prog]
  , eoTags = [t | Just (ATag (t, _)) <- fired]
  , eoNotifies = [t | Just (ANotify (t, _)) <- fired]
  , eoSetAccount = case [c | Just (ASetAccount (c, _)) <- fired] of
      (c : _) -> Just c
      [] -> Nothing
  }
  where
    fired = case mtxn of
      Nothing -> []
      Just txn ->
        [ if evalCond (RuleEnv txn) (rCond r) then Just (rAction r) else Nothing
        | SRule r <- prog
        ]
    fireBudget b = do
      alertCond <- bAlert b
      spent <- Map.lookup (fst (bName b)) spentByBudget
      let envB = BudgetEnv spent (fst (bLimit b))
      if evalCond envB alertCond then Just (fst (bName b)) else Nothing

data VarEnv
  = BudgetEnv Integer Integer     -- ^ spent, limit
  | RuleEnv TxnFacts

evalCond :: VarEnv -> Cond -> Bool
evalCond env c = case c of
  COr a b -> evalCond env a || evalCond env b
  CAnd a b -> evalCond env a && evalCond env b
  CNot a -> not (evalCond env a)
  CRecurring _ -> case env of
    RuleEnv txn -> tfRecurring txn
    BudgetEnv {} -> False         -- 검사 단계에서 이미 배제됨
  CMatches _ alts -> case env of
    RuleEnv txn -> any (`T.isInfixOf` tfMerchant txn) alts
    BudgetEnv {} -> False
  CCmp _ op a b ->
    let va = evalExpr env a
        vb = evalExpr env b
     in case op of
          OpGt -> va > vb
          OpGe -> va >= vb
          OpLt -> va < vb
          OpLe -> va <= vb
          OpEq -> va == vb
          OpNe -> va /= vb

-- | 식 값은 Rational — 0.8 * limit 도 정확한 유리수로 남는다.
evalExpr :: VarEnv -> Expr -> Rational
evalExpr env e = case e of
  ENum _ r -> r
  EMoney _ r _ -> r               -- 통화 정합성은 검사 단계에서 보장됨
  EVar _ v -> case (env, v) of
    (BudgetEnv spent _, VSpent) -> spent % 1
    (BudgetEnv _ lim, VLimit) -> lim % 1
    (RuleEnv txn, VAmount) -> tfAmountMinor txn % 1
    _ -> 0                        -- 검사 단계에서 이미 배제됨
  EAdd _ a b -> evalExpr env a + evalExpr env b
  ESub _ a b -> evalExpr env a - evalExpr env b
  EMul _ a b -> evalExpr env a * evalExpr env b
