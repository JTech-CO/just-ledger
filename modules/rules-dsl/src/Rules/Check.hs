-- | 타입·의미 검사 — 계정 존재, 통화 일치, 스코프, 타입 정합.
-- 모든 오류는 소스 위치(줄·열)와 함께 반환된다 (M5 DoD 5).
--
-- 타입 체계:
--   Money  — 최소 화폐 단위 금액 (spent, limit, amount, 통화 접미 리터럴)
--   Scalar — 무차원 계수 (맨 숫자 리터럴)
--   Scalar × Money → Money / 비교·덧뺄셈은 같은 타입끼리만 / Money × Money 오류
module Rules.Check
  ( CheckErr (..)
  , Env (..)
  , checkProgram
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Ratio (denominator)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T

import Rules.Syntax

data CheckErr = CheckErr
  { ceLine :: Int
  , ceCol  :: Int
  , ceMsg  :: Text
  }
  deriving (Show)

-- | 검사 환경 — 계정 코드 → 통화
newtype Env = Env { envAccounts :: Map Text Text }

-- | 검사 문맥: 스코프(budget alert / rule 조건) + 알려진 통화 집합
data Ctx = Ctx { ctxScope :: Scope, ctxCurrencies :: Set Text }

data Scope = InBudget Text | InRule

data Ty = TMoney | TScalar
  deriving (Eq)

tyName :: Ty -> Text
tyName TMoney = "Money"
tyName TScalar = "Scalar"

err :: Pos -> Text -> [CheckErr]
err (Pos l c) m = [CheckErr l c m]

-- | 프로그램 전체 검사. 오류 0건이면 통과.
checkProgram :: Env -> Program -> [CheckErr]
checkProgram env prog =
  concatMap (checkStmt env curs) prog ++ dupBudgetNames prog
  where
    curs = Set.fromList (Map.elems (envAccounts env))

dupBudgetNames :: Program -> [CheckErr]
dupBudgetNames prog = go Map.empty [b | SBudget b <- prog]
  where
    go _ [] = []
    go seen (b : rest) =
      let (name, p) = bName b
       in case Map.lookup name seen of
            Just () -> err p ("중복된 budget 이름: \"" <> name <> "\"")
                         ++ go seen rest
            Nothing -> go (Map.insert name () seen) rest

checkStmt :: Env -> Set Text -> Stmt -> [CheckErr]
checkStmt env curs (SBudget b) = checkBudget env curs b
checkStmt env curs (SRule r) = checkRule env curs r

checkBudget :: Env -> Set Text -> Budget -> [CheckErr]
checkBudget env curs b =
  limitPositive
    ++ currencyKnown
    ++ concatMap accountExists (bAccounts b)
    ++ currencyAgrees
    ++ maybe [] (checkCond (Ctx (InBudget cur) curs)) (bAlert b)
  where
    (limitV, limitP) = bLimit b
    (cur, curP) = bCurrency b
    limitPositive
      | limitV <= 0 = err limitP "한도는 양의 정수여야 합니다 (최소 화폐 단위)"
      | otherwise = []
    currencyKnown
      | Set.member cur curs = []
      | otherwise = err curP ("통화 " <> cur <> " 인 계정이 없습니다")
    accountExists (code, p)
      | Map.member code (envAccounts env) = []
      | otherwise = err p ("존재하지 않는 계정: " <> code)
    -- 통화 일치: where 절의 각 계정 통화가 budget 통화와 같아야 한다.
    currencyAgrees =
      concat
        [ err p ("계정 " <> code <> " 통화(" <> acur <> ")가 budget 통화("
                   <> cur <> ")와 다릅니다")
        | (code, p) <- bAccounts b
        , Just acur <- [Map.lookup code (envAccounts env)]
        , acur /= cur
        ]

checkRule :: Env -> Set Text -> Rule -> [CheckErr]
checkRule env curs r =
  actionOk ++ checkCond (Ctx InRule curs) (rCond r) ++ mixedCur ++ setAccCur
  where
    actionOk = case rAction r of
      ASetAccount (code, p)
        | not (Map.member code (envAccounts env)) ->
            err p ("존재하지 않는 계정: " <> code)
        | otherwise -> []
      ATag (t, p)
        | T.null t -> err p "빈 태그 이름"
        | otherwise -> []
      ANotify (t, p)
        | T.null t -> err p "빈 알림 메시지"
        | otherwise -> []
    moneys = condMoneys (rCond r)
    -- 한 rule 조건식의 Money 리터럴 통화는 1종이어야 한다. 2종째가 등장한
    -- 리터럴 위치에서 오류 — 통화 간 산술·비교는 정의되지 않는다 (환산 금지).
    mixedCur = case moneys of
      (c0, _) : rest -> case [(c, p) | (c, p) <- rest, c /= c0] of
        (c, p) : _ ->
          err p ("혼합 통화: 한 rule 조건식에서 " <> c0 <> " 와 " <> c
                   <> " 를 함께 쓸 수 없습니다")
        [] -> []
      [] -> []
    -- 조건식 통화 (단일 통화일 때만 확정)
    condCur = case moneys of
      (c0, _) : _ | all ((== c0) . fst) moneys -> Just c0
      _ -> Nothing
    -- set account 대상 계정 통화는 조건식 Money 리터럴 통화와 일치해야 한다.
    setAccCur = case (rAction r, condCur) of
      (ASetAccount (code, p), Just c)
        | Just acur <- Map.lookup code (envAccounts env)
        , acur /= c ->
            err p ("계정 " <> code <> " 통화(" <> acur <> ")가 조건식 통화("
                     <> c <> ")와 다릅니다")
      _ -> []

checkCond :: Ctx -> Cond -> [CheckErr]
checkCond ctx c = case c of
  COr a b -> checkCond ctx a ++ checkCond ctx b
  CAnd a b -> checkCond ctx a ++ checkCond ctx b
  CNot a -> checkCond ctx a
  CRecurring p -> case ctxScope ctx of
    InBudget _ -> err p "recurring 은 rule 조건에서만 쓸 수 있습니다"
    InRule -> []
  CMatches p _ -> case ctxScope ctx of
    InBudget _ -> err p "merchant matches 는 rule 조건에서만 쓸 수 있습니다"
    InRule -> []
  CCmp p _ a b ->
    let (ea, ta) = typeOf ctx a
        (eb, tb) = typeOf ctx b
     in ea ++ eb ++ case (ta, tb) of
          (Just x, Just y)
            | x /= y ->
                err p ("비교 양변 타입이 다릅니다: " <> tyName x <> " vs "
                         <> tyName y)
          _ -> []

-- | 식의 타입 추론. 스코프·통화·정수성 위반을 위치와 함께 수집한다.
typeOf :: Ctx -> Expr -> ([CheckErr], Maybe Ty)
typeOf ctx e = case e of
  ENum _ _ -> ([], Just TScalar)
  EMoney p r cur ->
    let intErr
          | denominator r /= 1 =
              err p "금액은 최소 화폐 단위 정수여야 합니다 (소수 불가)"
          | otherwise = []
        curErr
          | not (Set.member cur (ctxCurrencies ctx)) =
              err p ("통화 " <> cur <> " 인 계정이 없습니다")
          | otherwise = case ctxScope ctx of
              InBudget bcur
                | cur /= bcur ->
                    err p ("통화 불일치: budget 은 " <> bcur
                             <> ", 리터럴은 " <> cur)
              _ -> []
     in (intErr ++ curErr, Just TMoney)
  EVar p v -> case (ctxScope ctx, v) of
    (InBudget _, VSpent) -> ([], Just TMoney)
    (InBudget _, VLimit) -> ([], Just TMoney)
    (InBudget _, VAmount) ->
      (err p "amount 는 rule 조건에서만 쓸 수 있습니다", Nothing)
    (InRule, VAmount) -> ([], Just TMoney)
    (InRule, VSpent) ->
      (err p "spent 는 budget alert 에서만 쓸 수 있습니다", Nothing)
    (InRule, VLimit) ->
      (err p "limit 는 budget alert 에서만 쓸 수 있습니다", Nothing)
  EAdd p a b -> additive p "+" a b
  ESub p a b -> additive p "-" a b
  EMul p a b ->
    let (ea, ta) = typeOf ctx a
        (eb, tb) = typeOf ctx b
     in case (ta, tb) of
          (Just TScalar, Just TScalar) -> (ea ++ eb, Just TScalar)
          (Just TScalar, Just TMoney) -> (ea ++ eb, Just TMoney)
          (Just TMoney, Just TScalar) -> (ea ++ eb, Just TMoney)
          (Just TMoney, Just TMoney) ->
            (ea ++ eb ++ err p "Money × Money 는 정의되지 않습니다", Nothing)
          _ -> (ea ++ eb, Nothing)
  where
    additive p opName a b =
      let (ea, ta) = typeOf ctx a
          (eb, tb) = typeOf ctx b
       in case (ta, tb) of
            (Just x, Just y)
              | x == y -> (ea ++ eb, Just x)
              | otherwise ->
                  ( ea ++ eb ++ err p (tyName x <> " " <> opName <> " "
                      <> tyName y <> " 는 정의되지 않습니다")
                  , Nothing )
            _ -> (ea ++ eb, Nothing)
