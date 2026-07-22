# 월말 예산 초과 확률 — 잔여일 지출 분포 부트스트랩 (기술 백서 §4.3).
# seed 는 요청 필수 필드 — 시계에서 유도하지 않는다 (결정론, M6 DoD 1).
#
# 필수 필드는 전부 명시 검증한다(적대 검증 수정): 누락 시 R 내부 영문 오류가
# 프로토콜 경계로 새거나, 더 나쁘게는 ok:true 와 함께 "NaN" 확률이 나갔다.

#' 요청 필드 필수 검증 — 길이 0/NULL 을 조기 거절
require_field <- function(v, name) {
  if (is.null(v) || length(v) == 0) stop(sprintf("%s 는 필수입니다", name))
  v
}

#' @param spent_so_far  현재까지 지출 (금액 문자열)
#' @param daily_history 과거 일별 지출 (금액 문자열 벡터, >= 7일)
#' @param days_remaining 잔여 일수 (1..366)
#' @param limit         예산 한도 (금액 문자열)
#' @param iterations    부트스트랩 횟수 (기본 10000, <= 100000)
#' @param seed          정수 시드 (필수)
#' @return list(exceed_probability(chr "%.4f"), iterations)
bootstrap_exceed <- function(spent_so_far, daily_history, days_remaining,
                             limit, iterations, seed) {
  seed <- require_field(seed, "seed")
  spent_so_far <- require_field(spent_so_far, "spent_so_far_minor")
  daily_history <- require_field(daily_history, "daily_history_minor")
  days_remaining <- require_field(days_remaining, "days_remaining")
  limit <- require_field(limit, "limit_minor")
  iterations <- require_field(iterations, "iterations")

  if (length(daily_history) < 7) stop("daily_history 는 최소 7일 필요합니다")
  if (!is.numeric(days_remaining) || days_remaining != as.integer(days_remaining) ||
      days_remaining < 1 || days_remaining > 366) {
    stop("days_remaining 은 1..366 정수여야 합니다")
  }
  if (!is.numeric(iterations) || iterations != as.integer(iterations) ||
      iterations < 100 || iterations > 100000) {
    stop("iterations 는 100..100000 정수여야 합니다")
  }
  if (!is.numeric(seed) || seed != as.integer(seed)) stop("seed 는 정수여야 합니다")

  spent <- amounts_to_numeric(spent_so_far, "spent_so_far_minor")
  hist <- amounts_to_numeric(daily_history, "daily_history_minor")
  lim <- amounts_to_numeric(limit, "limit_minor")
  if (length(spent) != 1) stop("spent_so_far_minor 는 단일 값이어야 합니다")
  if (length(lim) != 1) stop("limit_minor 는 단일 값이어야 합니다")

  # RNG 종류를 명시 고정 — R 3.6 에서 sample() 알고리즘이 바뀐 전례가 있어
  # 기본값에 기대면 판본 간 골든이 갈라진다 (DoD 1).
  suppressWarnings(set.seed(as.integer(seed), kind = "Mersenne-Twister",
                            sample.kind = "Rejection"))
  draws <- matrix(
    sample(hist, days_remaining * iterations, replace = TRUE),
    nrow = iterations
  )
  totals <- spent + rowSums(draws)
  p <- mean(totals > lim)
  if (!is.finite(p)) stop("초과 확률 계산이 유한하지 않습니다")
  list(
    exceed_probability = sprintf("%.4f", p),
    iterations = as.integer(iterations)
  )
}
