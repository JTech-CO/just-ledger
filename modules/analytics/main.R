#!/usr/bin/env Rscript
# modules/analytics — R 분석 배치 (M6).
# JSONL stdin → JSONL stdout (라인 1:1), SVG 는 --out-dir 에 파일 산출.
#
# 요청 종류:
#   {"kind":"anomaly","series":[{"date":"...","amount_minor":"..."},...]}
#   {"kind":"forecast","spent_so_far_minor":"...","daily_history_minor":[...],
#    "days_remaining":N,"limit_minor":"...","iterations":10000,"seed":N}
#   {"kind":"report","name":"...","series":[...]}   ← anomaly 재사용 + SVG 2벌
#
# 결정론(M6 DoD 1): 시드는 요청 필드로만 받는다. 출력에 타임스탬프·절대경로
# 등 비결정 값을 넣지 않는다. 고정 시드 재실행은 stdout·SVG 바이트 동일.
#
# 캐시(M6 DoD 5): --cache-dir 지정 시 입력 전문 md5 를 키로 stdout·SVG 를
# 저장하고, 히트 시 재계산 없이 동일 바이트를 재생한다 (표시는 stderr 로만 —
# stdout 은 캐시 유무와 무관하게 바이트 동일해야 한다).

suppressPackageStartupMessages({
  library(jsonlite)
  library(ggplot2)
  library(svglite)
})

argv <- commandArgs(trailingOnly = FALSE)
self <- sub("^--file=", "", grep("^--file=", argv, value = TRUE)[1])
base_dir <- dirname(normalizePath(self))
source(file.path(base_dir, "R", "tokens.R"))
source(file.path(base_dir, "R", "anomaly.R"))
source(file.path(base_dir, "R", "forecast.R"))
source(file.path(base_dir, "R", "report.R"))

args <- commandArgs(trailingOnly = TRUE)
opt <- function(flag, default) {
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) args[i + 1] else default
}
out_dir <- opt("--out-dir", file.path(base_dir, "out"))
cache_dir <- opt("--cache-dir", NA)
tokens_css <- opt("--tokens", file.path(base_dir, "..", "..",
                                        "apps", "web", "client", "styles", "tokens.css"))

input_lines <- readLines(file("stdin"), warn = FALSE)
input_lines <- sub("\r$", "", input_lines)
input_lines <- input_lines[nzchar(input_lines)]

# ── 캐시 조회 ───────────────────────────────────────────────────────────────
cache_key <- NA
if (!is.na(cache_dir)) {
  tf <- tempfile()
  writeLines(input_lines, tf)
  cache_key <- unname(tools::md5sum(tf))
  unlink(tf)
  hit_out <- file.path(cache_dir, paste0(cache_key, ".out"))
  hit_svg <- file.path(cache_dir, cache_key)
  if (file.exists(hit_out)) {
    # stdout 재생 + SVG 복원 — 재계산 없음
    writeLines(readLines(hit_out, warn = FALSE))
    if (dir.exists(hit_svg)) {
      dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
      for (f in list.files(hit_svg)) {
        file.copy(file.path(hit_svg, f), file.path(out_dir, f), overwrite = TRUE)
      }
    }
    message(sprintf("cache hit %s", cache_key))
    quit(save = "no", status = 0)
  }
}

tokens <- tryCatch(load_tokens(normalizePath(tokens_css, mustWork = TRUE)),
                   error = function(e) e)

# 이번 실행이 산출한 SVG 만 캐시에 넣는다 (out_dir 의 이전 잔재 오염 방지)
RUN <- new.env()
RUN$svg <- character(0)

handle <- function(req) {
  kind <- req$kind
  if (is.null(kind)) stop("kind 필드가 없습니다")
  if (kind == "anomaly" || kind == "report") {
    s <- req$series
    if (is.null(s) || length(s$date) == 0) stop("series 가 비어 있습니다")
    a <- detect_anomalies(s$date, s$amount_minor)
    res <- list(
      ok = TRUE, kind = kind,
      anomalies = if (length(a$indices) == 0) list() else lapply(
        seq_along(a$indices),
        function(i) list(
          date = s$date[a$indices[i]],
          amount_minor = s$amount_minor[a$indices[i]],
          robust_z = a$robust_z[i]
        )
      ),
      n = length(s$date), threshold = a$threshold
    )
    if (kind == "report") {
      if (inherits(tokens, "error")) stop(conditionMessage(tokens))
      files <- render_report(req$name, s$date, s$amount_minor,
                             a$indices, tokens, out_dir)
      RUN$svg <- c(RUN$svg, files)
      res$files <- as.list(files)
    }
    return(res)
  }
  if (kind == "forecast") {
    f <- bootstrap_exceed(req$spent_so_far_minor, req$daily_history_minor,
                          req$days_remaining, req$limit_minor,
                          if (is.null(req$iterations)) 10000 else req$iterations,
                          req$seed)
    return(list(ok = TRUE, kind = "forecast",
                exceed_probability = f$exceed_probability,
                iterations = f$iterations))
  }
  stop(sprintf("알 수 없는 kind: %s", kind))
}

out_lines <- vapply(input_lines, function(ln) {
  res <- tryCatch({
    req <- fromJSON(ln, simplifyVector = TRUE)
    handle(req)
  }, error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  as.character(toJSON(res, auto_unbox = TRUE))
}, character(1), USE.NAMES = FALSE)

writeLines(out_lines)

# ── 캐시 저장 ───────────────────────────────────────────────────────────────
if (!is.na(cache_dir) && !is.na(cache_key)) {
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(out_lines, file.path(cache_dir, paste0(cache_key, ".out")))
  if (length(RUN$svg) > 0) {
    svg_out <- file.path(cache_dir, cache_key)
    dir.create(svg_out, showWarnings = FALSE, recursive = TRUE)
    for (f in unique(RUN$svg)) {
      file.copy(file.path(out_dir, f), file.path(svg_out, f), overwrite = TRUE)
    }
  }
}
