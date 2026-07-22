# 디자인 토큰 로더 — apps/web/client/styles/tokens.css 가 색상의 단일 진실원천.
# 이 파일 밖 하드코딩 hex 금지(전역 CLAUDE.md) → R 은 CSS 를 파싱해서 쓴다.
# 라이트 = 첫 :root 블록, 다크 = @media (prefers-color-scheme: dark) 내 :root.

#' @param css_path tokens.css 경로
#' @return list(light = named chr, dark = named chr) — 이름은 --접두 제거
load_tokens <- function(css_path) {
  if (!file.exists(css_path)) {
    stop(sprintf("디자인 토큰 파일이 없습니다: %s", css_path))
  }
  lines <- readLines(css_path, warn = FALSE, encoding = "UTF-8")
  light <- character(0)
  dark <- character(0)
  mode <- "none" # none | light | dark-media | dark-root
  depth <- 0L
  for (ln in lines) {
    if (grepl("prefers-color-scheme:\\s*dark", ln)) {
      mode <- "dark-media"
    } else if (mode == "dark-media" && grepl(":root", ln)) {
      mode <- "dark-root"
    } else if (mode == "none" && grepl("^:root\\s*\\{", ln)) {
      mode <- "light"
    }
    m <- regmatches(ln, regexec("--([a-z0-9-]+)\\s*:\\s*([^;]+);", ln))[[1]]
    if (length(m) == 3) {
      val <- trimws(m[3])
      if (mode == "light" && !(m[2] %in% names(light))) light[[m[2]]] <- val
      if (mode == "dark-root") dark[[m[2]]] <- val
    }
    if (grepl("\\}", ln)) {
      if (mode == "light") mode <- "none"
      if (mode == "dark-root") mode <- "dark-done"
      if (mode == "dark-media") mode <- "none"
    }
  }
  need <- c("bg", "surface", "border", "text", "text-muted",
            "accent", "positive", "negative", "warning")
  for (k in need) {
    if (is.na(light[k]) || is.na(dark[k])) {
      stop(sprintf("토큰 누락: --%s (light=%s dark=%s)", k, light[k], dark[k]))
    }
  }
  list(light = light[need], dark = dark[need])
}

#' WCAG 2.1 상대 휘도
relative_luminance <- function(hex) {
  rgb <- strtoi(c(substr(hex, 2, 3), substr(hex, 4, 5), substr(hex, 6, 7)), 16L) / 255
  lin <- ifelse(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055)^2.4)
  sum(c(0.2126, 0.7152, 0.0722) * lin)
}

#' WCAG 대비비 (항상 >= 1)
contrast_ratio <- function(hex_a, hex_b) {
  la <- relative_luminance(hex_a)
  lb <- relative_luminance(hex_b)
  (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}
