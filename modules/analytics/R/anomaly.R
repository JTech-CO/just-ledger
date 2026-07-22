# STL 분해 + MAD 이상치 탐지 (기술 백서 §4.3).
# 일별 지출 시계열 → stl(s.window="periodic", frequency=7) → 잔차 →
# robust z = 0.6745·(r - median)/MAD, |z| > 3.5 를 이상치로 판정.
#
# 금액 문자열 → double 변환은 통계 내부 한정이며, 2^53 을 넘는 값은
# 정밀도 손실 전에 거절한다 (INV-4 정신 — 침묵 손실 금지).

MAX_EXACT_DOUBLE <- 9007199254740992 # 2^53

#' 금액 문자열 벡터를 통계용 double 로 — 정밀도 밖이면 오류.
#' 2^53 = 9007199254740992 (16자리). 15자리 이하는 항상 안전, 16자리는
#' 같은 길이의 문자열 사전순 비교(숫자열에서 수치 비교와 동치), 17자리+ 거절.
amounts_to_numeric <- function(strs, field) {
  if (!all(grepl("^-?[0-9]+$", strs))) {
    stop(sprintf("%s: 정수 문자열이 아닌 금액이 있습니다", field))
  }
  mags <- sub("^-", "", strs)
  nd <- nchar(mags)
  over <- nd > 16 | (nd == 16 & mags > "9007199254740992")
  if (any(over)) {
    stop(sprintf("%s: 2^53 초과 금액은 통계 경로에서 다룰 수 없습니다", field))
  }
  as.numeric(strs)
}

#' STL+MAD 이상치 탐지
#' @param dates  ISO 날짜 문자열 벡터 (연속 일별)
#' @param amounts 금액 문자열 벡터 (최소 화폐 단위 정수)
#' @return list(indices, robust_z(chr), threshold) — indices 는 1-기준
detect_anomalies <- function(dates, amounts) {
  n <- length(amounts)
  if (n < 14) stop("이상치 탐지에는 최소 14일(주기 2회분) 시계열이 필요합니다")
  if (length(dates) != n) stop("dates 와 amounts 길이가 다릅니다")
  x <- amounts_to_numeric(amounts, "series.amount_minor")
  fit <- stats::stl(stats::ts(x, frequency = 7), s.window = "periodic")
  r <- as.numeric(fit$time.series[, "remainder"])
  med <- stats::median(r)
  mad0 <- stats::median(abs(r - med))
  if (mad0 == 0) {
    # 잔차가 사실상 상수 — 중앙값과 다른 점만 이상치로 (0 나눗셈 회피)
    rz <- ifelse(r == med, 0, sign(r - med) * Inf)
  } else {
    rz <- 0.6745 * (r - med) / mad0
  }
  idx <- which(abs(rz) > 3.5)
  z_str <- sprintf("%.2f", rz[idx])
  z_str[z_str == "-0.00"] <- "0.00"
  z_str[rz[idx] == Inf] <- "Inf"
  z_str[rz[idx] == -Inf] <- "-Inf"
  list(indices = idx, robust_z = z_str, threshold = "3.5")
}
