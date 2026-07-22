# STL 분해 + MAD 이상치 탐지 (기술 백서 §4.3).
# 일별 지출 시계열 → stl(s.window="periodic", robust=TRUE) → 잔차 →
# robust z = 0.6745·(r - median)/MAD, |z| > 3.5 를 이상치로 판정.
#
# robust=TRUE 인 이유(적대 검증 blocker 수정): 비강건 loess 추세는 큰 스파이크를
# 흡수해(smearing) 스파이크 이웃 날짜의 잔차까지 튀게 만든다. 그 결과 주입 2건
# 데이터셋에서 거짓양성 7건 → FPR 0.0795 로 M6 DoD 2(≤0.05)를 위반했다.
# robustness weight 를 켜면 같은 데이터에서 FPR 0.0000 (재현율 1.000 유지).
# inner/outer 반복 수를 명시 고정해 결정론(DoD 1)을 판본에 묶는다.
#
# 금액 문자열 → double 변환은 통계 내부 한정이며, 2^53 을 넘는 값은
# 정밀도 손실 전에 거절한다 (INV-4 정신 — 침묵 손실 금지).

PERIOD <- 7            # 일별 계열의 주간 계절성
Z_THRESHOLD <- 3.5     # 백서 §4.3 — 이 값을 통과용으로 조정하지 않는다
MAX_EXACT_DOUBLE <- "9007199254740992" # 2^53 (문자열 비교용)

#' 금액 문자열 벡터를 통계용 double 로 — 정밀도 밖이면 오류.
#' 2^53 = 9007199254740992 (16자리). 15자리 이하는 항상 안전, 16자리는
#' 같은 길이의 문자열 사전순 비교(숫자열에서 수치 비교와 동치), 17자리+ 거절.
amounts_to_numeric <- function(strs, field) {
  if (length(strs) == 0 || !all(grepl("^-?[0-9]+$", strs))) {
    stop(sprintf("%s: 정수 문자열이 아닌 금액이 있습니다", field))
  }
  mags <- sub("^-", "", strs)
  nd <- nchar(mags)
  over <- nd > 16 | (nd == 16 & mags > MAX_EXACT_DOUBLE)
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
  # stl 은 2주기 '초과'를 요구한다 — 하한을 그 실제 요구와 일치시킨다.
  # (n = 2*PERIOD 이면 R 내부 영문 오류가 프로토콜 경계로 새어 나갔다)
  if (n <= 2 * PERIOD) {
    stop(sprintf("이상치 탐지에는 최소 %d일(주기 %d일 × 2 초과) 시계열이 필요합니다",
                 2 * PERIOD + 1, PERIOD))
  }
  if (length(dates) != n) stop("dates 와 amounts 길이가 다릅니다")
  x <- amounts_to_numeric(amounts, "series.amount_minor")
  fit <- stats::stl(stats::ts(x, frequency = PERIOD), s.window = "periodic",
                    robust = TRUE, inner = 1, outer = 15)
  r <- as.numeric(fit$time.series[, "remainder"])
  med <- stats::median(r)
  mad0 <- stats::median(abs(r - med))
  # 금액은 최소 화폐 단위 정수다. MAD 가 0.5 미만이면 사실상 변동이 없는 계열이며,
  # 이때 z 로 나누면 loess 의 부동소수점 잡음(1e-12 수준)이 그대로 증폭되어
  # 정상값이 이상치로 보고된다. 정확 일치(mad0 == 0) 검사로는 이 경로를 막지 못한다.
  if (mad0 < 0.5) {
    idx <- which(abs(r - med) > 0.5)
    z_str <- rep("Inf", length(idx))
    z_str[r[idx] < med] <- "-Inf"
  } else {
    rz <- 0.6745 * (r - med) / mad0
    idx <- which(abs(rz) > Z_THRESHOLD)
    z_str <- sprintf("%.2f", rz[idx])
    z_str[z_str == "-0.00"] <- "0.00"
  }
  list(indices = idx, robust_z = z_str, threshold = sprintf("%.1f", Z_THRESHOLD))
}
