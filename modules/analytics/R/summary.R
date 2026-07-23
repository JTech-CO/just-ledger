# 기간 요약 통계 — 정확 총액(정수 문자열) + 분산 지표(통계 내부 double).
#
# 총액은 '표시용 통계'가 아니라 실제 금액 총합이므로 정밀도 손실 없이 더해야
# 한다(INV-4 정신). 개별 금액은 2^53 미만이라도 여러 건을 double 로 더하면
# 합이 2^53 을 넘어 침묵 반올림이 생긴다. gmp 등 신규 의존성(DEPENDS.lock 고정)
# 없이 십진 문자열 학교식 산술로 정확 합을 계산한다.
#
# 분산 지표(mean·sd·분위수)는 순수 파생 통계이므로 double 로 계산하고 고정
# 자릿수 문자열로 낸다 — forecast.R 의 exceed_probability, anomaly.R 의
# robust_z 와 동일한 규율("부동소수점은 통계 내부 한정", 전역 CLAUDE.md).

#' 선행 0 제거 ("007"->"7", ""->"0")
mag_norm <- function(a) {
  a <- sub("^0+", "", a)
  if (nchar(a) == 0) "0" else a
}

#' 비음수 십진 문자열 크기 비교 → -1/0/1 (자릿수 우선, 동수면 사전순=수치순)
mag_cmp <- function(a, b) {
  a <- mag_norm(a); b <- mag_norm(b)
  if (nchar(a) != nchar(b)) return(if (nchar(a) < nchar(b)) -1L else 1L)
  if (a == b) 0L else if (a < b) -1L else 1L
}

#' 비음수 십진 문자열 덧셈 (자리올림)
mag_add <- function(a, b) {
  da <- rev(as.integer(strsplit(mag_norm(a), "")[[1]]))
  db <- rev(as.integer(strsplit(mag_norm(b), "")[[1]]))
  n <- max(length(da), length(db))
  length(da) <- n; length(db) <- n
  da[is.na(da)] <- 0L; db[is.na(db)] <- 0L
  out <- integer(n + 1L)
  carry <- 0L
  for (i in seq_len(n)) {
    s <- da[i] + db[i] + carry
    out[i] <- s %% 10L
    carry <- s %/% 10L
  }
  out[n + 1L] <- carry
  mag_norm(paste(rev(out), collapse = ""))
}

#' 비음수 십진 문자열 뺄셈 (a >= b 전제, 자리내림)
mag_sub <- function(a, b) {
  da <- rev(as.integer(strsplit(mag_norm(a), "")[[1]]))
  db <- rev(as.integer(strsplit(mag_norm(b), "")[[1]]))
  length(db) <- length(da); db[is.na(db)] <- 0L
  out <- integer(length(da))
  borrow <- 0L
  for (i in seq_along(da)) {
    d <- da[i] - db[i] - borrow
    if (d < 0L) { d <- d + 10L; borrow <- 1L } else borrow <- 0L
    out[i] <- d
  }
  mag_norm(paste(rev(out), collapse = ""))
}

#' 부호 있는 두 정수 문자열의 합 (문자열)
int_add <- function(a, b) {
  na <- substring(a, 1, 1) == "-"
  nb <- substring(b, 1, 1) == "-"
  ma <- if (na) substring(a, 2) else a
  mb <- if (nb) substring(b, 2) else b
  if (na == nb) {                 # 같은 부호: 크기를 더하고 부호 유지
    s <- mag_add(ma, mb)
    if (na && s != "0") paste0("-", s) else s
  } else {                        # 다른 부호: 큰 크기에서 작은 크기를 뺀다
    cmp <- mag_cmp(ma, mb)
    if (cmp == 0L) return("0")
    if (cmp > 0L) { s <- mag_sub(ma, mb); if (na) paste0("-", s) else s }
    else          { s <- mag_sub(mb, ma); if (nb) paste0("-", s) else s }
  }
}

#' 정수 문자열 벡터의 정확 합 (문자열) — double 2^53 한계를 우회한다.
int_string_sum <- function(strs) {
  if (length(strs) == 0) return("0")
  if (!all(grepl("^-?[0-9]+$", strs))) {
    stop("정수 문자열이 아닌 금액이 있습니다")
  }
  Reduce(int_add, strs, "0")
}

#' 통계 지표 고정 자릿수 포맷 — 음의 0 을 정규화한다(재실행 바이트 안정).
fmt2 <- function(v) {
  s <- sprintf("%.2f", v)
  s[s == "-0.00"] <- "0.00"
  s
}

#' 기간 요약 — 대시보드 '기간 합계' 카드용.
#' 총액·최소·최대는 정확한 금액이므로 정수 문자열(원 데이터 값)로 반환하고,
#' 평균·표준편차·분위수는 파생 분산 지표이므로 double→고정 자릿수 문자열로 낸다.
#' @param amounts 금액 문자열 벡터 (최소 화폐 단위 정수)
#' @return named list: count,total_minor,min_minor,max_minor,
#'                     mean,median,sd,p25,p75,p90,iqr
period_summary <- function(amounts) {
  if (length(amounts) == 0) stop("summary: series 가 비어 있습니다")
  x <- amounts_to_numeric(amounts, "series.amount_minor")
  n <- length(x)
  # 분위수는 R 기본(type 7)로 고정 — 판본 간 결정론을 위해 명시한다.
  q <- stats::quantile(x, c(0.25, 0.5, 0.75, 0.9), type = 7, names = FALSE)
  sdv <- if (n < 2) 0 else stats::sd(x)
  list(
    count       = n,
    total_minor = int_string_sum(amounts),  # 정확 — double 반올림 없음
    min_minor   = amounts[which.min(x)],     # 원 데이터 값(정확)
    max_minor   = amounts[which.max(x)],
    mean        = fmt2(mean(x)),
    median      = fmt2(q[2]),
    sd          = fmt2(sdv),
    p25         = fmt2(q[1]),
    p75         = fmt2(q[3]),
    p90         = fmt2(q[4]),
    iqr         = fmt2(q[3] - q[1])
  )
}
