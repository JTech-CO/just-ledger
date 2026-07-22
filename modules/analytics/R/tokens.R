# 디자인 토큰 로더 — apps/web/client/styles/tokens.css 가 색상의 단일 진실원천.
# 이 파일 밖 하드코딩 hex 금지(전역 CLAUDE.md) → R 은 CSS 를 파싱해서 쓴다.
#
# 파싱 규율(적대 검증 blocker 수정): 주석을 먼저 제거하고 블록 단위로 읽는다.
# 주석 안의 선언을 채택하면 SSOT 게이트가 통째로 무력화되므로(주석 처리된 옛
# 색이 SVG 에 들어가도 아무도 못 잡는다) 정규식 한 줄 스캔을 쓰지 않는다.
# 값은 #RRGGBB 만 허용한다 — 대비비 계산이 이 형식을 전제하기 때문이다.

TOKEN_KEYS <- c("bg", "surface", "border", "text", "text-muted",
                "accent", "positive", "negative", "warning")
HEX6 <- "^#[0-9A-Fa-f]{6}$"

#' CSS 주석(/* … */, 여러 줄 포함) 제거
strip_comments <- function(txt) {
  gsub("(?s)/\\*.*?\\*/", "", txt, perl = TRUE)
}

#' 셀렉터 정규식 뒤의 첫 { … } 블록 본문을 반환 (:root 블록은 중첩이 없다)
block_after <- function(txt, selector_regex) {
  p <- regexpr(selector_regex, txt, perl = TRUE)
  if (p < 0) return(NULL)
  rest <- substring(txt, p + attr(p, "match.length"))
  ob <- regexpr("\\{", rest, fixed = FALSE)
  if (ob < 0) return(NULL)
  body <- substring(rest, ob + 1)
  cb <- regexpr("\\}", body, fixed = FALSE)
  if (cb < 0) return(NULL)
  substring(body, 1, cb - 1)
}

#' 블록 본문에서 `--name: value` 선언을 모두 뽑는다
parse_decls <- function(block) {
  out <- character(0)
  if (is.null(block)) return(out)
  for (piece in strsplit(block, ";", fixed = TRUE)[[1]]) {
    m <- regmatches(piece, regexec("--([a-z0-9-]+)\\s*:\\s*(.+)$", piece))[[1]]
    if (length(m) == 3) out[[trimws(m[2])]] <- trimws(m[3])
  }
  out
}

#' @param css_path tokens.css 경로
#' @return list(light = named chr, dark = named chr) — 이름은 -- 접두 제거
load_tokens <- function(css_path) {
  if (!file.exists(css_path)) {
    stop(sprintf("디자인 토큰 파일이 없습니다: %s", css_path))
  }
  txt <- strip_comments(paste(readLines(css_path, warn = FALSE, encoding = "UTF-8"),
                              collapse = "\n"))

  # 수동 토글 블록이 있으면 그것을 정본으로 삼는다(CSS 자체의 우선순위와 일치).
  # 없으면 라이트는 첫 :root, 다크는 prefers-color-scheme: dark 안의 :root.
  light <- parse_decls(block_after(txt, ":root\\[data-theme\\s*=\\s*['\"]light['\"]\\]"))
  if (length(light) == 0) {
    light <- parse_decls(block_after(txt, "(?m)^\\s*:root(?![\\[a-zA-Z])"))
  }
  dark <- parse_decls(block_after(txt, ":root\\[data-theme\\s*=\\s*['\"]dark['\"]\\]"))
  if (length(dark) == 0) {
    dark <- parse_decls(block_after(txt, "prefers-color-scheme\\s*:\\s*dark[^{]*\\{[^:]*:root"))
  }

  for (k in TOKEN_KEYS) {
    for (nm in c("light", "dark")) {
      v <- get(nm)[k]
      if (is.na(v)) stop(sprintf("토큰 누락: --%s (%s)", k, nm))
      if (!grepl(HEX6, v)) {
        stop(sprintf("토큰 --%s (%s) 가 #RRGGBB 형식이 아닙니다: %s", k, nm, v))
      }
    }
  }
  list(light = light[TOKEN_KEYS], dark = dark[TOKEN_KEYS])
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
