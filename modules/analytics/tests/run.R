#!/usr/bin/env Rscript
# make test-analytics — M6 게이트 (R).
# T1 버전 잠금  T2 골든 왕복  T3 결정론(재실행 바이트 동일, DoD 1)
# T4 이상치 재현율·거짓양성률 — 골든 구성 포함 여러 주입 밀도 (DoD 2)
# T5 캐시·무효화 (DoD 5)  T6 실제 SVG 색 기반 AA (DoD 4)
# T7 오류 계약·정밀도  T8 인자·인코딩 강건성
#
# 게이트 정직성 규율(적대 검증 blocker 수정): DoD 2 측정은 '유리한 한 구성'이
# 아니라 이 모듈이 실제로 산출하는 골든 구성과 여러 주입 밀도에서 모두 만족해야
# 한다. 임계(3.5)나 기준(0.95/0.05)을 통과용으로 조정하지 않는다.

suppressPackageStartupMessages(library(jsonlite))

self <- sub("^--file=", "", grep("^--file=",
  commandArgs(trailingOnly = FALSE), value = TRUE)[1])
mod_dir <- dirname(dirname(normalizePath(self)))   # modules/analytics
repo <- dirname(dirname(mod_dir))                  # 저장소 루트
fix <- file.path(repo, "fixtures", "analytics")
main <- file.path(mod_dir, "main.R")
tokens_css <- file.path(repo, "apps", "web", "client", "styles", "tokens.css")
source(file.path(mod_dir, "R", "tokens.R"))
source(file.path(mod_dir, "R", "anomaly.R"))

fails <- 0
check <- function(ok, name, detail = "") {
  if (isTRUE(ok)) {
    cat(sprintf("pass  %s\n", name))
  } else {
    cat(sprintf("FAIL  %s %s\n", name, detail))
    fails <<- fails + 1
  }
}

run_main <- function(in_file, out_dir, extra = character(0)) {
  out <- tempfile(fileext = ".jsonl")
  err <- tempfile()
  status <- system2("Rscript", c(main, "--out-dir", out_dir, extra),
                    stdin = in_file, stdout = out, stderr = err)
  list(status = status, stdout = out, stderr = err)
}
read_bytes <- function(path) readBin(path, "raw", file.size(path))
write_req <- function(txt) { p <- tempfile(); writeLines(txt, p); p }

req_file <- file.path(fix, "requests.jsonl")
expected_file <- file.path(fix, "expected.jsonl")
golden_svg_dir <- file.path(fix, "svg")

# ── T1: 패키지 버전 잠금 (드리프트 조기 검출 — 골든이 갈라지기 전에) ────────
lock <- fromJSON(file.path(mod_dir, "DEPENDS.lock"))
for (p in names(lock$packages)) {
  check(as.character(packageVersion(p)) == lock$packages[[p]],
        sprintf("version-lock: %s %s", p, lock$packages[[p]]),
        sprintf("(실제 %s)", packageVersion(p)))
}
check(paste(R.version$major, R.version$minor, sep = ".") == lock$r,
      sprintf("version-lock: R %s", lock$r))

# ── T2+T3: 골든 왕복 + 결정론 ───────────────────────────────────────────────
d1 <- file.path(tempdir(), "svg-run1"); d2 <- file.path(tempdir(), "svg-run2")
r1 <- run_main(req_file, d1)
r2 <- run_main(req_file, d2)
check(r1$status == 0 && r2$status == 0, "golden: main.R 정상 종료")
check(identical(read_bytes(r1$stdout), read_bytes(expected_file)),
      "golden: stdout == expected.jsonl (바이트)")
check(identical(read_bytes(r1$stdout), read_bytes(r2$stdout)),
      "determinism: 재실행 stdout 바이트 동일 (DoD 1)")
svg_names <- list.files(golden_svg_dir, pattern = "\\.svg$")
check(length(svg_names) == 2, "golden: SVG 2벌 존재")
for (f in svg_names) {
  check(identical(read_bytes(file.path(d1, f)), read_bytes(file.path(golden_svg_dir, f))),
        sprintf("golden: %s 바이트 동일", f))
  check(identical(read_bytes(file.path(d1, f)), read_bytes(file.path(d2, f))),
        sprintf("determinism: %s 재실행 동일 (DoD 1)", f))
}

# 골든 응답 내용: 주입 스파이크와 검출 집합이 **정확히 일치**해야 한다
resp <- lapply(readLines(expected_file, warn = FALSE), fromJSON)
a1 <- resp[[1]]
check(isTRUE(a1$ok) && nrow(a1$anomalies) == 2 &&
        identical(sort(a1$anomalies$date), c("2026-05-08", "2026-06-10")),
      "anomaly: 검출 집합 == 주입 집합 (정확 일치, 거짓양성 0)")
check(isTRUE(resp[[2]]$ok) && grepl("^[01]\\.[0-9]{4}$", resp[[2]]$exceed_probability),
      "forecast: 확률 고정 자릿수 문자열")
check(isTRUE(resp[[3]]$ok) && length(resp[[3]]$files) == 2,
      "report: 라이트·다크 2벌 산출")
check(identical(resp[[4]]$ok, FALSE) && identical(resp[[5]]$ok, FALSE),
      "오류 계약: 길이 미달·seed 누락 → ok=false")

# ── T4: 재현율·FPR — 골든 구성 + 여러 주입 밀도 (DoD 2) ─────────────────────
# 한 구성만 측정하면 그 구성에서만 통과하는 체리피킹이 된다. 골든 생성기와
# 동일한 구성을 반드시 포함하고, 희소(2건)부터 조밀(20건)까지 함께 본다.
eval_detect <- function(x, inj, label) {
  n <- length(x)
  res <- detect_anomalies(format(seq(as.Date("2026-01-01"), by = "day", length.out = n)),
                          as.character(x))
  recall <- length(intersect(res$indices, inj)) / length(inj)
  fpr <- length(setdiff(res$indices, inj)) / (n - length(inj))
  check(recall >= 0.95, sprintf("%s recall %.3f >= 0.95 (DoD 2)", label, recall))
  check(fpr <= 0.05, sprintf("%s FPR %.4f <= 0.05 (DoD 2)", label, fpr))
}
# (a) 골든 생성기와 동일한 구성 (fixtures/analytics/gen.R)
{
  n <- 90
  base <- rep(c(31000, 29000, 30500, 32000, 33500, 61000, 54000), length.out = n)
  set.seed(31); x <- base + round(rnorm(n, 0, 2500))
  x[38] <- x[38] + 250000; x[71] <- x[71] + 180000
  eval_detect(x, c(38, 71), "detect[골든 n=90 주입2]")
}
# (b) 주입 밀도별 — 희소일수록 스미어링 거짓양성이 드러난다
for (k in c(2, 3, 5, 20)) {
  set.seed(20260722)
  n <- 210
  base <- rep(c(31000, 29000, 30500, 32000, 33500, 61000, 54000), 30)
  x <- base + round(rnorm(n, 0, 2500))
  inj <- round(seq(10, 200, length.out = k))
  x[inj] <- x[inj] + 200000
  eval_detect(x, inj, sprintf("detect[n=210 주입%d]", k))
}
# (c) 이상치가 없는 계열에서는 아무것도 보고하지 않아야 한다
{
  set.seed(5)
  n <- 120
  x <- rep(c(31000, 29000, 30500, 32000, 33500, 61000, 54000), length.out = n) +
    round(rnorm(n, 0, 2500))
  res <- detect_anomalies(format(seq(as.Date("2026-01-01"), by = "day", length.out = n)),
                          as.character(x))
  check(length(res$indices) / n <= 0.05,
        sprintf("detect[주입0] FPR %.4f <= 0.05", length(res$indices) / n))
}
# (d) 상수 계열 — loess 부동소수점 잡음이 이상치로 새지 않아야 한다
{
  res <- detect_anomalies(format(seq(as.Date("2026-01-01"), by = "day", length.out = 60)),
                          as.character(rep(30000, 60)))
  check(length(res$indices) == 0, "detect[상수 계열] 이상치 0건",
        sprintf("(검출 %d)", length(res$indices)))
}

# ── T5: 캐시 — 히트·무효화 (DoD 5) ──────────────────────────────────────────
cache <- file.path(tempdir(), "an-cache")
dc1 <- file.path(tempdir(), "svg-c1"); dc2 <- file.path(tempdir(), "svg-c2")
c1 <- run_main(req_file, dc1, c("--cache-dir", cache))
c2 <- run_main(req_file, dc2, c("--cache-dir", cache))
check(identical(read_bytes(c1$stdout), read_bytes(c2$stdout)),
      "cache: stdout 바이트 동일 (DoD 5)")
check(!any(grepl("cache hit", readLines(c1$stderr, warn = FALSE))), "cache: 1회째 miss")
check(any(grepl("cache hit", readLines(c2$stderr, warn = FALSE))), "cache: 2회째 hit")
svg1 <- list.files(dc1, pattern = "\\.svg$")
check(length(svg1) == 2 &&
        all(vapply(svg1, function(f) identical(read_bytes(file.path(dc1, f)),
                                               read_bytes(file.path(dc2, f))), logical(1))),
      "cache: SVG 도 동일 복원")
# 무효화: 디자인 토큰(SSOT)이 바뀌면 캐시가 낡은 색을 반환하면 안 된다
{
  alt_css <- tempfile(fileext = ".css")
  css <- readLines(tokens_css, warn = FALSE)
  writeLines(sub("--accent: #14506B;", "--accent: #145070;", css, fixed = TRUE), alt_css)
  dc3 <- file.path(tempdir(), "svg-c3")
  c3 <- run_main(req_file, dc3, c("--cache-dir", cache, "--tokens", alt_css))
  check(!any(grepl("cache hit", readLines(c3$stderr, warn = FALSE))),
        "cache: 토큰 변경 시 miss (SSOT 무효화)")
  txt <- paste(readLines(file.path(dc3, "daily-spend-light.svg"), warn = FALSE), collapse = "")
  check(grepl("#145070", txt, ignore.case = TRUE), "cache: 새 토큰 색이 SVG 에 반영")
}

# ── T6: 실제 SVG 색 기반 AA (DoD 4) ─────────────────────────────────────────
# 토큰 쌍 대비비만 계산하면 SVG 가 반대 테마 색을 써도 통과한다. 인라인 style
# 속성에서 실제 사용 색을 뽑아 (1) 반대 테마 색 오염 0, (2) 역할별 AA 를 본다.
tokens <- load_tokens(tokens_css)
svg_inline_colors <- function(path) {
  txt <- paste(readLines(path, warn = FALSE), collapse = "")
  attrs <- regmatches(txt, gregexpr("style='[^']*'", txt))[[1]]
  unique(toupper(unlist(regmatches(attrs, gregexpr("#[0-9A-Fa-f]{6}", attrs)))))
}
for (theme in c("light", "dark")) {
  tok <- toupper(tokens[[theme]])
  other <- toupper(tokens[[if (theme == "light") "dark" else "light"]])
  used <- svg_inline_colors(file.path(golden_svg_dir, sprintf("daily-spend-%s.svg", theme)))
  # (1) 반대 테마 전용 색이 섞이면 실패 — report.R 의 테마 오배선 회귀를 잡는다
  cross <- intersect(used, setdiff(other, tok))
  check(length(cross) == 0, sprintf("AA %s: 반대 테마 색 오염 0", theme),
        sprintf("(발견 %s)", paste(cross, collapse = ",")))
  # (2) 사용된 색은 전부 이 테마의 토큰이어야 한다 (하드코딩 색 0)
  check(all(used %in% tok), sprintf("token %s: 사용 색이 전부 토큰", theme),
        sprintf("(비토큰 %s)", paste(setdiff(used, tok), collapse = ",")))
  # (3) 역할별 대비 — 텍스트 4.5:1, 그래픽 개체 3:1.
  #     격자선(--border)은 순수 장식이라 WCAG 1.4.11 대상이 아니므로 제외.
  bg <- tok[["bg"]]
  for (role in c("text", "text-muted")) {
    if (tok[[role]] %in% used) {
      check(contrast_ratio(tok[[role]], bg) >= 4.5,
            sprintf("AA %s: %s/bg >= 4.5 (실사용)", theme, role))
    }
  }
  for (role in c("accent", "negative")) {
    if (tok[[role]] %in% used) {
      check(contrast_ratio(tok[[role]], bg) >= 3,
            sprintf("AA %s: %s/bg >= 3 (실사용 그래픽)", theme, role))
    }
  }
  # (4) 텍스트·강조 토큰이 실제로 쓰였는지 — 검사가 공허해지지 않게
  check(tok[["text-muted"]] %in% used && tok[["accent"]] %in% used,
        sprintf("token %s: text-muted·accent 실사용 확인", theme))
}

# ── T7: 오류 계약·정밀도 ────────────────────────────────────────────────────
big <- tryCatch(amounts_to_numeric("9007199254740993", "t"), error = function(e) e)
check(inherits(big, "error"), "정밀도: 2^53+1 거절")
neg <- tryCatch(amounts_to_numeric("-9007199254740993", "t"), error = function(e) e)
check(inherits(neg, "error"), "정밀도: -(2^53+1) 거절")
edge <- tryCatch(amounts_to_numeric("9007199254740992", "t"), error = function(e) e)
check(!inherits(edge, "error"), "정밀도: 2^53 정확값 수용")
# stl 최소 길이 경계: 14 거절 / 15 통과 (R 내부 영문 오류가 새면 안 된다)
d14 <- format(seq(as.Date("2026-01-01"), by = "day", length.out = 14))
e14 <- tryCatch(detect_anomalies(d14, as.character(rep(c(1000, 2000), 7))),
                error = function(e) conditionMessage(e))
check(is.character(e14) && grepl("최소 15일", e14), "경계: n=14 는 계약 메시지로 거절",
      sprintf("(%s)", e14))
d15 <- format(seq(as.Date("2026-01-01"), by = "day", length.out = 15))
e15 <- tryCatch({ detect_anomalies(d15, as.character(c(rep(c(1000, 2000), 7), 1500))); TRUE },
                error = function(e) conditionMessage(e))
check(isTRUE(e15), "경계: n=15 는 통과", sprintf("(%s)", e15))
# forecast 필수 필드 누락 → NaN 확률이 아니라 오류
{
  p <- write_req('{"kind":"forecast","daily_history_minor":["1","2","3","4","5","6","7"],"days_remaining":5,"limit_minor":"100","iterations":1000,"seed":1}')
  r <- run_main(p, file.path(tempdir(), "svg-e1"))
  out <- fromJSON(readLines(r$stdout, warn = FALSE)[1])
  check(identical(out$ok, FALSE), "forecast: spent_so_far 누락 → ok=false (NaN 금지)")
}

# ── T8: 인자·인코딩·이름 강건성 ─────────────────────────────────────────────
{
  p <- write_req('{"kind":"warmup"}')
  r <- run_main(p, file.path(tempdir(), "svg-e2"), c("--bogus", "x"))
  check(r$status == 2, "인자: 미지 인자는 조용히 무시하지 않고 종료 2",
        sprintf("(status %d)", r$status))
}
{
  # 비UTF-8 바이트가 섞인 줄은 그 줄만 오류로 격리되고 나머지는 계속 처리
  p <- tempfile()
  con <- file(p, "wb")
  writeBin(c(charToRaw('{"kind":"anomaly","series":{"date":["x"],"amount_minor":["1"]}}'),
             as.raw(0x0a), as.raw(0xff), as.raw(0xfe), as.raw(0x0a),
             charToRaw('{"kind":"warmup"}'), as.raw(0x0a)), con)
  close(con)
  r <- run_main(p, file.path(tempdir(), "svg-e3"))
  lines <- readLines(r$stdout, warn = FALSE)
  check(r$status == 0 && length(lines) == 3,
        "인코딩: 비UTF-8 줄만 격리, 라인 1:1 유지",
        sprintf("(status %d, %d줄)", r$status, length(lines)))
}
{
  # 같은 name 의 report 2건은 서로의 SVG 를 덮어쓰므로 거절
  s <- paste0('{"kind":"report","name":"dup","series":{"date":[',
              paste(sprintf('"2026-01-%02d"', 1:20), collapse = ","),
              '],"amount_minor":[', paste(sprintf('"%d"', 30000 + (1:20) * 100), collapse = ","),
              ']}}')
  p <- write_req(c(s, s))
  r <- run_main(p, file.path(tempdir(), "svg-e4"))
  outs <- lapply(readLines(r$stdout, warn = FALSE), fromJSON)
  check(identical(outs[[1]]$ok, TRUE) && identical(outs[[2]]$ok, FALSE),
        "report: 같은 배치 내 name 중복 거절")
}
{
  # y축 라벨이 2^31 을 넘는 금액에서 NA 로 깨지지 않는다
  n <- 20
  vals <- format(3000000000 + (1:n) * 1000000, scientific = FALSE)
  s <- paste0('{"kind":"report","name":"big","series":{"date":[',
              paste(sprintf('"2026-02-%02d"', 1:n), collapse = ","),
              '],"amount_minor":[', paste(sprintf('"%s"', trimws(vals)), collapse = ","), ']}}')
  d <- file.path(tempdir(), "svg-big")
  r <- run_main(write_req(s), d)
  out <- fromJSON(readLines(r$stdout, warn = FALSE)[1])
  txt <- paste(readLines(file.path(d, "big-light.svg"), warn = FALSE), collapse = "")
  check(identical(out$ok, TRUE) && !grepl(">NA<", txt),
        "report: 2^31 초과 금액 y축 라벨 정상 (NA 없음)")
}

# ── T9: 요약 통계·Hampel 국소 이상치·주간 막대 리포트 (M9 추가 기능) ──────────
# 결정론·수치 정확성·SVG 토큰 색을 골든으로 고정한다. 총액은 실제 금액이므로
# double(2^53) 을 경유하지 않는 정확 정수 문자열 합을 단언한다(INV-4 정신).
source(file.path(mod_dir, "R", "summary.R"))

# (1) int_string_sum — double 2^53 한계를 넘는 정확 정수 합
check(identical(int_string_sum(c("100", "200", "300", "400", "500")), "1500"),
      "int_string_sum: 기본 합")
check(identical(int_string_sum(c("9007199254740992", "1")), "9007199254740993"),
      "int_string_sum: 2^53 초과 정확(double 이면 침묵 반올림)")
check(identical(int_string_sum(rep("9999999999999999", 3)), "29999999999999997"),
      "int_string_sum: 자리올림 연쇄")
check(identical(int_string_sum(c("-5", "3")), "-2") &&
        identical(int_string_sum(c("5", "-5")), "0") &&
        identical(int_string_sum(c("-100", "-200")), "-300"),
      "int_string_sum: 부호 혼합·상쇄·음수")
check(identical(int_string_sum(character(0)), "0"), "int_string_sum: 빈 벡터 → 0")

# (2) period_summary — 정확 총액·최소·최대(정수 문자열) + 파생 지표(고정 자릿수)
sm <- period_summary(as.character(c(100, 200, 300, 400, 500)))
check(sm$count == 5 && identical(sm$total_minor, "1500") &&
        identical(sm$min_minor, "100") && identical(sm$max_minor, "500"),
      "period_summary: count·총액·최소·최대 정확")
check(identical(sm$mean, "300.00") && identical(sm$median, "300.00") &&
        identical(sm$sd, "158.11") && identical(sm$p25, "200.00") &&
        identical(sm$p75, "400.00") && identical(sm$p90, "460.00") &&
        identical(sm$iqr, "200.00"),
      "period_summary: 평균·중앙값·표준편차·분위수·IQR 고정 자릿수")

# (3) hampel_anomalies — 국소 스파이크만, 구조적 계열에 거짓양성 0
base28 <- rep(c(30000, 31000, 30500, 29500, 30800, 30200, 30600), 4)
check(length(hampel_anomalies(as.character(base28))$indices) == 0,
      "hampel: 구조적 무주입 계열 거짓양성 0")
h1 <- base28; h1[15] <- h1[15] + 200000
check(identical(hampel_anomalies(as.character(h1))$indices, 15L),
      "hampel: 단일 스파이크 정확 검출(이웃 오검출 0)")
h2 <- base28; h2[c(10, 22)] <- h2[c(10, 22)] + 200000
check(all(c(10L, 22L) %in% hampel_anomalies(as.character(h2))$indices),
      "hampel: 다중 스파이크 재현")
check(length(hampel_anomalies(as.character(rep(30000, 20)))$indices) == 0,
      "hampel: 상수 계열 이상치 0(무변동 창 가드)")
he <- tryCatch(hampel_anomalies(as.character(rep(30000, 6))),
               error = function(e) conditionMessage(e))
check(is.character(he) && grepl("최소 7개", he), "hampel: 창 미달(n<2K+1) 계약 거절")

# (4) 단독 실행(stdin/stdout) — summary·hampel·weekly + 결정론(재실행 바이트 동일)
sj <- function(dates, amounts) paste0(
  '{"date":[', paste(sprintf('"%s"', dates), collapse = ","),
  '],"amount_minor":[', paste(sprintf('"%s"', amounts), collapse = ","), ']}')
wk_amt <- (1:21) * 1000
reqs9 <- c(
  paste0('{"kind":"summary","series":',
         sj(sprintf("2026-01-%02d", 1:5), c(100, 200, 300, 400, 500)), '}'),
  paste0('{"kind":"hampel","series":', sj(sprintf("d%d", seq_along(h1)), h1), '}'),
  paste0('{"kind":"weekly","name":"wk","series":',
         sj(sprintf("2026-02-%02d", 1:21), wk_amt), '}')
)
p9 <- write_req(reqs9)
d9a <- file.path(tempdir(), "svg-t9a"); d9b <- file.path(tempdir(), "svg-t9b")
r9a <- run_main(p9, d9a); r9b <- run_main(p9, d9b)
check(r9a$status == 0, "T9 단독 실행 정상 종료")
check(identical(read_bytes(r9a$stdout), read_bytes(r9b$stdout)),
      "T9 결정론: 재실행 stdout 바이트 동일")
o9 <- lapply(readLines(r9a$stdout, warn = FALSE), fromJSON)
check(identical(o9[[1]]$total_minor, "1500") && identical(o9[[1]]$p90, "460.00"),
      "summary(stdin): 총액·p90 계약 일치")
check(identical(o9[[2]]$kind, "hampel") && nrow(o9[[2]]$anomalies) == 1 &&
        identical(o9[[2]]$anomalies$amount_minor, as.character(h1[15])),
      "hampel(stdin): 스파이크 1건 정확")
check(identical(o9[[3]]$kind, "weekly") && length(o9[[3]]$files) == 2 &&
        identical(o9[[3]]$buckets$total_minor, c("28000", "77000", "126000")),
      "weekly(stdin): 버킷 합계 정확·SVG 2벌")

# (5) 주간 막대 SVG — 재실행 바이트 동일 + 인라인 색이 전부 디자인 토큰(하드코딩 0)
for (theme in c("light", "dark")) {
  f <- sprintf("wk-%s.svg", theme)
  check(identical(read_bytes(file.path(d9a, f)), read_bytes(file.path(d9b, f))),
        sprintf("weekly SVG %s: 재실행 바이트 동일(결정론)", theme))
  tok <- toupper(tokens[[theme]])
  used <- svg_inline_colors(file.path(d9a, f))
  check(all(used %in% tok), sprintf("weekly SVG %s: 사용 색 전부 토큰", theme),
        sprintf("(비토큰 %s)", paste(setdiff(used, tok), collapse = ",")))
  check(tok[["accent"]] %in% used,
        sprintf("weekly SVG %s: 막대에 accent 토큰 실사용", theme))
}

if (fails > 0) {
  cat(sprintf("\ntest-analytics: %d건 실패\n", fails))
  quit(save = "no", status = 1)
}
cat("\ntest-analytics: 전부 통과\n")
