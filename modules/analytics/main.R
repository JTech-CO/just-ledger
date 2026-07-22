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
# 캐시(M6 DoD 5): --cache-dir 지정 시 (stdin 바이트 + 디자인 토큰 + 모듈 코드)
# 해시를 키로 stdout·SVG 를 저장하고, 히트 시 재계산 없이 동일 바이트를 재생한다.
#   · 키에 토큰·코드를 넣는 이유: stdin 만으로 키를 만들면 tokens.css(색상 SSOT)나
#     렌더러가 바뀌어도 낡은 SVG 를 영구히 반환한다(적대 검증 blocker).
#   · 환경성 실패(토큰 로드 불가)는 응답으로 감싸 캐시하지 않고 프로세스를
#     비영점 종료시킨다 — 캐시된 실패가 복구 후에도 되살아나는 것을 막는다.
#   · 표시는 stderr 로만 — stdout 은 캐시 유무와 무관하게 바이트 동일해야 한다.

suppressPackageStartupMessages({
  library(jsonlite)
  library(ggplot2)
  library(svglite)
})

argv <- commandArgs(trailingOnly = FALSE)
self <- sub("^--file=", "", grep("^--file=", argv, value = TRUE)[1])
base_dir <- dirname(normalizePath(self))
R_FILES <- file.path(base_dir, "R", c("tokens.R", "anomaly.R", "forecast.R", "report.R"))
for (f in R_FILES) source(f)

# ── 인자 파싱 — 미지 인자·값 없는 플래그는 조용히 무시하지 않는다 ───────────
args <- commandArgs(trailingOnly = TRUE)
KNOWN <- c("--out-dir", "--cache-dir", "--tokens")
opts <- list()
i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (!(a %in% KNOWN)) {
    message(sprintf("analytics: 알 수 없는 인자 %s", a))
    message("사용법: main.R [--out-dir <dir>] [--cache-dir <dir>] [--tokens <css>]")
    quit(save = "no", status = 2)
  }
  if (i == length(args)) {
    message(sprintf("analytics: %s 에 값이 없습니다", a))
    quit(save = "no", status = 2)
  }
  opts[[a]] <- args[i + 1]
  i <- i + 2
}
out_dir <- if (is.null(opts[["--out-dir"]])) file.path(base_dir, "out") else opts[["--out-dir"]]
cache_dir <- opts[["--cache-dir"]]
tokens_css <- if (is.null(opts[["--tokens"]])) {
  file.path(base_dir, "..", "..", "apps", "web", "client", "styles", "tokens.css")
} else opts[["--tokens"]]

# ── stdin 을 바이트로 읽는다 (캐시 키 대상이자 인코딩 안전) ──────────────────
MAX_INPUT <- 128L * 1024L * 1024L
con <- file("stdin", "rb")
raw_input <- readBin(con, "raw", n = MAX_INPUT)
close(con)

md5_of_raw <- function(bytes) {
  tf <- tempfile()
  writeBin(bytes, tf)
  k <- unname(tools::md5sum(tf))
  unlink(tf)
  k
}

# 줄 분리는 바이트 수준에서 한다. 문자열 정규식(strsplit perl=TRUE)은 입력에
# 비UTF-8 바이트가 하나라도 있으면 분리 자체를 실패해 배치 전체가 죽는다.
split_raw_lines <- function(bytes) {
  if (length(bytes) == 0) return(character(0))
  nl <- which(bytes == as.raw(0x0a))
  starts <- c(1L, nl + 1L)
  ends <- c(nl - 1L, length(bytes))
  out <- character(length(starts))
  for (i in seq_along(starts)) {
    if (starts[i] > ends[i]) { out[i] <- ""; next }
    seg <- bytes[starts[i]:ends[i]]
    if (seg[length(seg)] == as.raw(0x0d)) seg <- seg[-length(seg)]   # 후행 CR
    s <- rawToChar(seg)
    Encoding(s) <- "UTF-8"
    out[i] <- s
  }
  out
}
input_lines <- split_raw_lines(raw_input)
input_lines <- input_lines[nzchar(input_lines)]

# ── 캐시 키: stdin + 토큰 + 모듈 코드 ───────────────────────────────────────
cache_key <- NULL
if (!is.null(cache_dir)) {
  tokens_md5 <- if (file.exists(tokens_css)) unname(tools::md5sum(tokens_css)) else "no-tokens"
  code_md5 <- paste(unname(tools::md5sum(c(R_FILES, self))), collapse = "")
  cache_key <- md5_of_raw(charToRaw(paste(md5_of_raw(raw_input), tokens_md5,
                                          code_md5, sep = "|")))
  hit_out <- file.path(cache_dir, paste0(cache_key, ".out"))
  hit_svg <- file.path(cache_dir, cache_key)
  if (file.exists(hit_out)) {
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

# 이번 실행이 산출한 SVG·리포트 이름만 추적 (out_dir 잔재 오염·이름 충돌 방지)
RUN <- new.env()
RUN$svg <- character(0)
RUN$names <- character(0)

handle <- function(req) {
  kind <- req$kind
  if (is.null(kind) || length(kind) != 1) stop("kind 필드가 없습니다")
  if (kind == "anomaly" || kind == "report") {
    s <- req$series
    if (is.null(s) || is.null(s$date) || length(s$date) == 0) stop("series 가 비어 있습니다")
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
      if (inherits(tokens, "error")) {
        # 환경성 실패 — 요청 잘못이 아니므로 응답으로 감싸 캐시하지 않는다
        message(sprintf("analytics: 디자인 토큰 로드 실패 — %s", conditionMessage(tokens)))
        quit(save = "no", status = 3)
      }
      nm <- req$name
      if (is.null(nm) || length(nm) != 1) stop("report 요청에 name 이 필요합니다")
      if (nm %in% RUN$names) {
        stop(sprintf("report name 중복: %s (같은 배치에서 SVG 를 덮어씁니다)", nm))
      }
      RUN$names <- c(RUN$names, nm)
      files <- render_report(nm, s$date, s$amount_minor, a$indices, tokens, out_dir)
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
    # 비UTF-8 바이트는 그 줄만 오류로 격리한다 (배치 전체를 죽이지 않는다)
    if (!validUTF8(ln)) stop("UTF-8 이 아닌 바이트가 있습니다")
    req <- fromJSON(ln, simplifyVector = TRUE)
    handle(req)
  }, error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  as.character(toJSON(res, auto_unbox = TRUE))
}, character(1), USE.NAMES = FALSE)

writeLines(out_lines)

# ── 캐시 저장 ───────────────────────────────────────────────────────────────
if (!is.null(cache_dir) && !is.null(cache_key)) {
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
