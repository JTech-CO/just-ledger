# SVG 리포트 — ggplot 테마 토큰화, 라이트/다크 2벌 (디자인 백서 §4.3).
# 배경 투명, 격자선 --border, 텍스트 --text-muted, 15px 기준.
# 다크는 필터 반전이 아니라 다크 토큰으로 별도 산출한다.
# 폰트는 DejaVu Sans 고정 — 컨테이너·CI 양쪽에 존재, 텍스트 메트릭 결정론.

REPORT_FONT <- "DejaVu Sans"

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
        # 축 라벨은 정수 문자열 포맷 (천단위 구분) — double 값은 최소단위
        # 정수 범위(< 2^53 검증됨)라 formatC(format="d") 가 정확하다
        labels = function(v) formatC(v, format = "d", big.mark = ",")
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
