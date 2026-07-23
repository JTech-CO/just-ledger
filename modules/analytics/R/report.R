# SVG 리포트 — ggplot 테마 토큰화, 라이트/다크 2벌 (디자인 백서 §4.3).
# 배경 투명, 격자선 --border, 텍스트 --text-muted, 15px 기준.
# 다크는 필터 반전이 아니라 다크 토큰으로 별도 산출한다.
# 폰트는 DejaVu Sans 고정 — 컨테이너·CI 양쪽에 존재, 텍스트 메트릭 결정론.

REPORT_FONT <- "DejaVu Sans"

#' 축 라벨용 정수 문자열 포맷 (천단위 구분). 2^53 까지 정확 — 32비트 절단 없음.
money_axis_labels <- function(v) {
  s <- sprintf("%.0f", v)
  neg <- substring(s, 1, 1) == "-"
  mag <- ifelse(neg, substring(s, 2), s)
  mag <- gsub("(?<=\\d)(?=(\\d{3})+$)", ",", mag, perl = TRUE)
  ifelse(neg, paste0("-", mag), mag)
}

#' ggplot 테마 — 디자인 토큰 1벌로부터
tokened_theme <- function(tok) {
  ggplot2::theme_minimal(base_size = 15, base_family = REPORT_FONT) +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.grid.major = ggplot2::element_line(colour = tok[["border"]], linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),
      text = ggplot2::element_text(colour = tok[["text-muted"]], family = REPORT_FONT),
      axis.text = ggplot2::element_text(colour = tok[["text-muted"]], size = 11),
      plot.title = ggplot2::element_text(colour = tok[["text"]], size = 15),
      legend.position = "none"
    )
}

#' 시계열 + 이상치 차트를 라이트/다크 2벌 SVG 로 산출.
#' @param name 파일 이름 줄기 ([A-Za-z0-9._-]+)
#' @param dates ISO 날짜 문자열, @param amounts 금액 문자열
#' @param anomaly_idx 이상치 인덱스 (1-기준)
#' @param tokens load_tokens() 결과, @param out_dir 산출 디렉터리
#' @return 산출 파일명 벡터 (out_dir 기준 상대 — 절대경로 비결정성 차단)
render_report <- function(name, dates, amounts, anomaly_idx, tokens, out_dir) {
  if (!grepl("^[A-Za-z0-9._-]+$", name)) {
    stop("report name 은 [A-Za-z0-9._-]+ 만 허용합니다")
  }
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  x <- amounts_to_numeric(amounts, "series.amount_minor")
  d <- data.frame(day = seq_along(x), value = x)
  files <- character(0)
  for (theme_name in c("light", "dark")) {
    tok <- tokens[[theme_name]]
    p <- ggplot2::ggplot(d, ggplot2::aes(x = day, y = value)) +
      ggplot2::geom_line(colour = tok[["accent"]], linewidth = 0.6)
    if (length(anomaly_idx) > 0) {
      p <- p + ggplot2::geom_point(
        data = d[anomaly_idx, , drop = FALSE],
        colour = tok[["negative"]], size = 2.2
      )
    }
    p <- p +
      ggplot2::scale_y_continuous(
        # 축 라벨은 문자열 연산으로 만든다(전역 규칙). formatC(format="d") 는
        # 내부에서 32비트 정수로 강제 변환해 |v| > 2^31-1 이면 전부 NA 를 찍는데,
        # 성공 응답·종료코드 0 과 함께 나가 침묵 실패가 된다(적대 검증 blocker).
        # sprintf("%.0f") + 정규식 천단위 삽입은 2^53 까지 정확하다.
        labels = money_axis_labels
      ) +
      ggplot2::labs(title = name, x = NULL, y = NULL) +
      tokened_theme(tok)
    fname <- sprintf("%s-%s.svg", name, theme_name)
    svglite::svglite(file.path(out_dir, fname), width = 8, height = 4.5,
                     bg = "transparent")
    print(p)
    grDevices::dev.off()
    files <- c(files, fname)
  }
  files
}

#' 주간 합계 막대 리포트 — 일별 시계열을 7일 버킷으로 합산해 막대로 그린다.
#' 시계열 라인(개별 값)과 달리 집계 흐름을 보여주는 별개의 리포트다.
#' 버킷 합계는 실제 금액이므로 정확 정수 문자열(int_string_sum)로 반환하고,
#' 막대 높이는 플롯 기하값이라 수치로 변환한다(render_report 의 라인과 동일 규율).
#' @param name 파일 이름 줄기 ([A-Za-z0-9._-]+)
#' @param amounts 금액 문자열 벡터 (최소 화폐 단위 정수, 일별 연속)
#' @param tokens load_tokens() 결과, @param out_dir 산출 디렉터리
#' @return list(files = 파일명 벡터, buckets = list(index,total_minor))
render_weekly_bars <- function(name, amounts, tokens, out_dir) {
  if (!grepl("^[A-Za-z0-9._-]+$", name)) {
    stop("report name 은 [A-Za-z0-9._-]+ 만 허용합니다")
  }
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  n <- length(amounts)
  bucket <- ((seq_len(n) - 1L) %/% 7L) + 1L
  nb <- max(bucket)
  totals <- character(nb)
  heights <- numeric(nb)
  for (b in seq_len(nb)) {
    grp <- amounts[bucket == b]
    totals[b] <- int_string_sum(grp)                        # 정확 합(정수 문자열)
    heights[b] <- amounts_to_numeric(totals[b], "bucket.total")  # 플롯용 수치
  }
  d <- data.frame(week = seq_len(nb), total = heights)
  files <- character(0)
  for (theme_name in c("light", "dark")) {
    tok <- tokens[[theme_name]]
    p <- ggplot2::ggplot(d, ggplot2::aes(x = week, y = total)) +
      ggplot2::geom_col(fill = tok[["accent"]], width = 0.7) +
      ggplot2::scale_y_continuous(labels = money_axis_labels) +
      ggplot2::scale_x_continuous(breaks = seq_len(nb)) +
      ggplot2::labs(title = name, x = NULL, y = NULL) +
      tokened_theme(tok)
    fname <- sprintf("%s-%s.svg", name, theme_name)
    svglite::svglite(file.path(out_dir, fname), width = 8, height = 4.5,
                     bg = "transparent")
    print(p)
    grDevices::dev.off()
    files <- c(files, fname)
  }
  list(
    files = files,
    buckets = lapply(seq_len(nb), function(b) {
      list(index = b, total_minor = totals[b])
    })
  )
}
