# 분석 골든 생성기 (M6). 결정론적 요청 픽스처를 만든다.
# 실행: Rscript fixtures/analytics/gen.R  →  requests.jsonl 재생성
# expected.jsonl 과 골든 SVG 는 main.R 을 돌려 생성·검토 후 커밋한다:
#   Rscript modules/analytics/main.R --out-dir fixtures/analytics/svg \
#     < fixtures/analytics/requests.jsonl > fixtures/analytics/expected.jsonl

suppressPackageStartupMessages(library(jsonlite))

here <- dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1])))

# ── 90일 일별 지출 시계열 — 주간 패턴 + 고정 시드 노이즈 + 스파이크 2개 ─────
# 사인 등 주기 노이즈는 STL 주기(7일)와 간섭해 잔차 MAD 를 왜곡하므로
# 비주기(정규) 노이즈를 고정 시드로 쓴다 — R RNG 는 시드 고정 시 결정론.
n <- 90
base <- rep(c(31000, 29000, 30500, 32000, 33500, 61000, 54000), length.out = n)
set.seed(31)
noise <- round(rnorm(n, 0, 2500))
x <- base + noise
x[38] <- x[38] + 250000 # 주입 스파이크 1 (명백한 이상치)
x[71] <- x[71] + 180000 # 주입 스파이크 2
dates <- format(seq(as.Date("2026-04-01"), by = "day", length.out = n))
series <- lapply(seq_len(n), function(i) {
  list(date = dates[i], amount_minor = as.character(x[i]))
})

requests <- list(
  # 1) 이상치 탐지 — 스파이크 2개가 검출되어야 함
  list(kind = "anomaly", series = series),
  # 2) 예산 초과 확률 — 고정 시드
  list(kind = "forecast",
       spent_so_far_minor = "820000",
       daily_history_minor = as.character(x[1:60]),
       days_remaining = 10L,
       limit_minor = "1200000",
       iterations = 10000L,
       seed = 20260722L),
  # 3) SVG 리포트 (라이트/다크 2벌)
  list(kind = "report", name = "daily-spend", series = series),
  # 4) 오류: 14일 미만
  list(kind = "anomaly", series = series[1:10]),
  # 5) 오류: seed 누락
  list(kind = "forecast", spent_so_far_minor = "0",
       daily_history_minor = as.character(x[1:14]),
       days_remaining = 5L, limit_minor = "100000", iterations = 1000L)
)

out <- vapply(requests, function(r) as.character(toJSON(r, auto_unbox = TRUE)),
              character(1))
writeLines(out, file.path(here, "requests.jsonl"))
cat(sprintf("requests.jsonl: %d건 (시리즈 %d일, 스파이크 idx 38·71)\n",
            length(out), n))
