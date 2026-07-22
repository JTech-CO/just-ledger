# 월말 예산 초과 확률 — 잔여일 지출 분포 부트스트랩 (기술 백서 §4.3).
# seed 는 요청 필수 필드 — 시계에서 유도하지 않는다 (결정론, M6 DoD 1).

#' @param spent_so_far  현재까지 지출 (금액 문자열)
#' @param daily_history 과거 일별 지출 (금액 문자열 벡터, >= 7일)
#' @param days_remaining 잔여 일수 (1..366)
#' @param limit         예산 한도 (금액 문자열)
#' @param iterations    부트스트랩 횟수 (기본 10000, <= 100000)
#' @param seed          정수 시드 (필수)
#' @return list(exceed_probability(chr "%.4f"), iterations)
bootstrap_exceed <- function(spent_so_far, daily_history, days_remaining,
                             limit, iterations, seed) {
  if (is.null(seed)) stop("seed 는 필수입니다 (결정론)")
  if (length(daily_history) < 7) stop("daily_history 는 최소 7일 필요합니다")
  if (days_remaining < 1 || days_remaining > 366) stop("days_remaining 은 1..366")
  if (iterations < 100 || iterations > 100000) stop("iterations 는 100..100000")
  spent <- amounts_to_numeric(spent_so_far, "spent_so_far_minor")
  hist <- amounts_to_numeric(daily_history, "daily_history_minor")
  lim <- amounts_to_numeric(limit, "limit_minor")
  set.seed(as.integer(seed))
  draws <- matrix(
    sample(hist, days_remaining * iterations, replace = TRUE),
    nrow = iterations
  )
  totals <- spent + rowSums(draws)
  p <- mean(totals > lim)
  list(
    exceed_probability = sprintf("%.4f", p),
    iterations = as.integer(iterations)
  )
}
