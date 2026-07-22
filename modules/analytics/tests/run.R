#!/usr/bin/env Rscript
# make test-analytics — M6 게이트 (R).
# T1 버전 잠금  T2 골든 왕복  T3 결정론(재실행 바이트 동일, DoD 1)
# T4 이상치 재현율·거짓양성률 (DoD 2)  T5 캐시 (DoD 5)
# T6 SVG 대비비 AA (DoD 4)  T7 오류 계약

suppressPackageStartupMessages(library(jsonlite))

self <- sub("^--file=", "", grep("^--file=",
  commandArgs(trailingOnly = FALSE), value = TRUE)[1])
mod_dir <- dirname(dirname(normalizePath(self)))   # modules/analytics
repo <- dirname(dirname(mod_dir))                  # 저장소 루트
fix <- file.path(repo, "fixtures", "analytics")
main <- file.path(mod_dir, "main.R")
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

req_file <- file.path(fix, "requests.jsonl")
expected_file <- file.path(fix, "expected.jsonl")
golden_svg_dir <- file.path(fix, "svg")

# ── T1: 패키지 버전 잠금 (드리프트 조기 검출 — 골든이 갈라지기 전에) ────────
lock <- fromJSON(file.path(mod_dir, "DEPENDS.lock"))
for (p in names(lock$packages)) {
  check(as.character(packageVersion(p)) == lock$packages[[p]],
        sprintf("version-lock: %s %s", p, lock$packages[[p]]),
        sprintf("(실제 %s — DEPENDS.lock 과 불일치)", packageVersion(p)))
}
check(paste(R.version$major, R.version$minor, sep = ".") == lock$r,
      sprintf("version-lock: R %s", lock$r))

# ── T2+T3: 골든 왕복 + 결정론 — 2회 실행 모두 골든과 바이트 동일 ────────────
d1 <- file.path(tempdir(), "svg-run1"); d2 <- file.path(tempdir(), "svg-run2")
r1 <- run_main(req_file, d1)
r2 <- run_main(req_file, d2)
check(r1$status == 0 && r2$status == 0, "golden: main.R 정상 종료")
check(identical(read_bytes(r1$stdout), read_bytes(expected_file)),
      "golden: stdout == expected.jsonl (바이트)")
check(identical(read_bytes(r1$stdout), read_bytes(r2$stdout)),
      "determinism: 재실행 stdout 바이트 동일 (DoD 1)")
for (f in list.files(golden_svg_dir, pattern = "\\.svg$")) {
  check(identical(read_bytes(file.path(d1, f)), read_bytes(file.path(golden_svg_dir, f))),
        sprintf("golden: %s 바이트 동일", f))
  check(identical(read_bytes(file.path(d1, f)), read_bytes(file.path(d2, f))),
        sprintf("determinism: %s 재실행 동일 (DoD 1)", f))
}

# 골든 응답 내용 확인: 주입 스파이크(38·71) 검출
resp <- lapply(readLines(expected_file, warn = FALSE), fromJSON)
a1 <- resp[[1]]
check(isTRUE(a1$ok) && nrow(a1$anomalies) >= 2 &&
        all(c("2026-05-08", "2026-06-10") %in% a1$anomalies$date),
      "anomaly: 주입 스파이크 2건(idx 38·71) 검출")
check(isTRUE(resp[[2]]$ok) && grepl("^0\\.[0-9]{4}$|^1\\.0000$", resp[[2]]$exceed_probability),
      "forecast: 확률 고정 자릿수 문자열")
check(isTRUE(resp[[3]]$ok) && length(resp[[3]]$files) == 2,
      "report: 라이트·다크 2벌 산출")
check(identical(resp[[4]]$ok, FALSE) && identical(resp[[5]]$ok, FALSE),
      "오류 계약: 14일 미만·seed 누락 → ok=false")

# ── T4: 재현율 ≥ 0.95, 거짓양성률 ≤ 0.05 (DoD 2) ────────────────────────────
set.seed(20260722)
n <- 210
base <- rep(c(31000, 29000, 30500, 32000, 33500, 61000, 54000), 30)
x <- base + round(rnorm(n, 0, 2500))
inj <- seq(10, 200, by = 10) # 주입 이상치 20개
x[inj] <- x[inj] + 200000
res <- detect_anomalies(format(seq(as.Date("2026-01-01"), by = "day", length.out = n)),
                        as.character(x))
recall <- length(intersect(res$indices, inj)) / length(inj)
fpr <- length(setdiff(res$indices, inj)) / (n - length(inj))
check(recall >= 0.95, sprintf("recall %.3f >= 0.95 (DoD 2)", recall))
check(fpr <= 0.05, sprintf("FPR %.3f <= 0.05 (DoD 2)", fpr))

# ── T5: 캐시 — 2회째는 재계산 없이 동일 바이트 (DoD 5) ──────────────────────
cache <- file.path(tempdir(), "an-cache")
dc1 <- file.path(tempdir(), "svg-c1"); dc2 <- file.path(tempdir(), "svg-c2")
c1 <- run_main(req_file, dc1, c("--cache-dir", cache))
c2 <- run_main(req_file, dc2, c("--cache-dir", cache))
check(identical(read_bytes(c1$stdout), read_bytes(c2$stdout)),
      "cache: stdout 바이트 동일 (DoD 5)")
check(any(grepl("cache hit", readLines(c2$stderr, warn = FALSE))),
      "cache: 2회째 stderr 에 cache hit")
check(!any(grepl("cache hit", readLines(c1$stderr, warn = FALSE))),
      "cache: 1회째는 miss")
svg1 <- list.files(dc1, pattern = "\\.svg$")
check(length(svg1) == 2 &&
        all(vapply(svg1, function(f) identical(read_bytes(file.path(dc1, f)),
                                               read_bytes(file.path(dc2, f))), logical(1))),
      "cache: SVG 도 동일 복원")

# ── T6: 대비비 AA (DoD 4) — SVG 에 실제 쓰인 토큰 쌍 검증 ───────────────────
tokens <- load_tokens(file.path(repo, "apps", "web", "client", "styles", "tokens.css"))
for (theme in c("light", "dark")) {
  tok <- tokens[[theme]]
  # 텍스트(제목·축)는 투명 배경 위 → 페이지 배경(--bg)·표면(--surface) 양쪽에서 AA
  for (bgk in c("bg", "surface")) {
    check(contrast_ratio(tok[["text"]], tok[[bgk]]) >= 4.5,
          sprintf("AA %s: text/%s >= 4.5", theme, bgk))
    check(contrast_ratio(tok[["text-muted"]], tok[[bgk]]) >= 4.5,
          sprintf("AA %s: text-muted/%s >= 4.5", theme, bgk))
    # 그래픽 요소(선·이상치 마커)는 WCAG 1.4.11 비텍스트 3:1
    check(contrast_ratio(tok[["accent"]], tok[[bgk]]) >= 3,
          sprintf("AA %s: accent/%s >= 3 (비텍스트)", theme, bgk))
    check(contrast_ratio(tok[["negative"]], tok[[bgk]]) >= 3,
          sprintf("AA %s: negative/%s >= 3 (비텍스트)", theme, bgk))
  }
  # SVG 가 실제로 이 토큰 hex 를 포함하는지 (토큰화가 형식적이지 않음을 확인)
  svg_path <- file.path(golden_svg_dir, sprintf("daily-spend-%s.svg", theme))
  svg_txt <- paste(readLines(svg_path, warn = FALSE), collapse = "")
  check(grepl(tok[["accent"]], svg_txt, ignore.case = TRUE) &&
          grepl(tok[["negative"]], svg_txt, ignore.case = TRUE),
        sprintf("token: %s SVG 가 accent·negative 토큰 사용", theme))
}

# ── T7: 추가 오류 계약 — 2^53 정밀도 경계 ──────────────────────────────────
big <- tryCatch(amounts_to_numeric("9007199254740993", "t"), error = function(e) e)
check(inherits(big, "error"), "정밀도: 2^53+1 거절")
neg <- tryCatch(amounts_to_numeric("-9007199254740993", "t"), error = function(e) e)
check(inherits(neg, "error"), "정밀도: -(2^53+1) 거절")
edge <- tryCatch(amounts_to_numeric("9007199254740992", "t"), error = function(e) e)
check(!inherits(edge, "error"), "정밀도: 2^53 정확값 수용")
ok15 <- tryCatch(amounts_to_numeric("999999999999999", "t"), error = function(e) e)
check(!inherits(ok15, "error"), "정밀도: 15자리 수용")

if (fails > 0) {
  cat(sprintf("\ntest-analytics: %d건 실패\n", fails))
  quit(save = "no", status = 1)
}
cat("\ntest-analytics: 전부 통과\n")
