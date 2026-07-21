//! 지문 정규화 (백서 §4.3): NFKC → 공백 축약 → 카드사 접두어 제거 → 대소문자 폴딩.
//! 날짜·시각도 여기서 표준형으로 만든다.
//!
//! 성능(DoD 3): 대부분의 실데이터(완성형 한글·ASCII)는 이미 NFKC 형이고 여분 공백도
//! 없다 — 빠른 판별로 전체 워크를 건너뛴다. 결과 문자열은 동일하다 (골든 불변).

use crate::error::ParseError;
use unicode_normalization::{is_nfkc_quick, IsNormalized, UnicodeNormalization};

/// 상점명 앞에 붙는 결제 수단 접두어 — 동일 상점의 지문이 결제 수단에 따라
/// 갈라지지 않게 제거한다. 과잉 제거를 피하기 위해 "접두어 + 공백" 형태만 벗긴다.
const CARD_PREFIXES: &[&str] = &["체크카드 ", "신용카드 ", "카드 "];

/// 여분 공백(선두·말미·연속·비스페이스 공백) 존재 여부
fn has_extra_whitespace(s: &str) -> bool {
    let b = s.as_bytes();
    if b.first() == Some(&b' ') || b.last() == Some(&b' ') {
        return true;
    }
    let mut prev_space = false;
    for c in s.chars() {
        if c.is_whitespace() {
            if c != ' ' || prev_space {
                return true;
            }
            prev_space = true;
        } else {
            prev_space = false;
        }
    }
    false
}

/// NFKC 불변이 확실한 흔한 문자만인가 — ASCII(제어 제외)·완성형 한글 음절·한글 자모
/// 호환 범위 밖의 문자다. 이 범위는 유니코드 속성 테이블 조회 없이 판별된다 (DoD 3).
fn is_common_nfkc_stable(s: &str) -> bool {
    s.chars().all(|c| {
        matches!(c,
            ' '..='~'                    // 출력 가능한 ASCII
            | '\u{AC00}'..='\u{D7A3}'    // 완성형 한글 음절 (NFKC 불변)
        )
    })
}

/// 표시·지문 공용 텍스트 정규화 (NFKC + 공백 축약)
pub fn normalize_text(raw: &str) -> String {
    // 1단 빠른 경로: 흔한 문자 범위(속성 조회 불필요) → NFKC 워크 생략
    let already_nfkc =
        is_common_nfkc_stable(raw) || matches!(is_nfkc_quick(raw.chars()), IsNormalized::Yes);
    if already_nfkc && !has_extra_whitespace(raw) {
        return raw.to_owned();
    }
    let nfkc: String = if already_nfkc {
        raw.to_owned()
    } else {
        raw.nfkc().collect()
    };
    // NFKC 가 전각 공백(U+3000)을 U+0020 으로 접어 주므로 일반 공백 축약만 하면 된다
    nfkc.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// 지문용 상점명 정규화 (표시용과 달리 접두어 제거 + 소문자 폴딩까지)
pub fn normalize_merchant(raw: &str) -> String {
    let mut s = normalize_text(raw);
    for p in CARD_PREFIXES {
        if let Some(rest) = s.strip_prefix(p) {
            s = rest.to_owned();
            break;
        }
    }
    s.to_lowercase()
}

/// "2026.06.02 09:14:33" | "2026/06/03" | "2026-06-01 08:12:45"
/// → (YYYY-MM-DD, Option<HH:MM:SS>)
pub fn normalize_datetime(raw: &str, row: usize) -> Result<(String, Option<String>), ParseError> {
    let s = raw.trim();
    let (date_part, time_part) = match s.split_once(' ') {
        Some((d, t)) => (d, Some(t.trim())),
        None => (s, None),
    };

    let sep = if date_part.contains('.') {
        '.'
    } else if date_part.contains('/') {
        '/'
    } else {
        '-'
    };
    let parts: Vec<&str> = date_part.split(sep).collect();
    if parts.len() != 3 {
        return Err(ParseError::Row(row, "날짜 형식 인식 불가".into()));
    }
    let y: u32 = parts[0]
        .parse()
        .map_err(|_| ParseError::Row(row, "연도 파싱 실패".into()))?;
    let m: u32 = parts[1]
        .parse()
        .map_err(|_| ParseError::Row(row, "월 파싱 실패".into()))?;
    let d: u32 = parts[2]
        .parse()
        .map_err(|_| ParseError::Row(row, "일 파싱 실패".into()))?;
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) || !(1900..=9999).contains(&y) {
        return Err(ParseError::Row(row, "날짜 범위 밖".into()));
    }
    let date = format!("{y:04}-{m:02}-{d:02}");

    let time = match time_part {
        None | Some("") => None,
        Some(t) => {
            let hms: Vec<&str> = t.split(':').collect();
            if hms.len() != 3 {
                return Err(ParseError::Row(row, "시각 형식 인식 불가".into()));
            }
            let h: u32 = hms[0]
                .parse()
                .map_err(|_| ParseError::Row(row, "시 파싱 실패".into()))?;
            let mi: u32 = hms[1]
                .parse()
                .map_err(|_| ParseError::Row(row, "분 파싱 실패".into()))?;
            let se: u32 = hms[2]
                .parse()
                .map_err(|_| ParseError::Row(row, "초 파싱 실패".into()))?;
            if h > 23 || mi > 59 || se > 59 {
                return Err(ParseError::Row(row, "시각 범위 밖".into()));
            }
            Some(format!("{h:02}:{mi:02}:{se:02}"))
        }
    };
    Ok((date, time))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nfkc_fullwidth_folds() {
        // 전각 영문·전각 공백·호환 괄호가 표준형으로
        assert_eq!(normalize_text("ＣＵ　서울역점"), "CU 서울역점");
        assert_eq!(normalize_text("（주）테크컴퍼니"), "(주)테크컴퍼니");
        assert_eq!(normalize_text("  스타벅스   강남점  "), "스타벅스 강남점");
        // 빠른 경로: 이미 정규형이면 그대로
        assert_eq!(normalize_text("스타벅스 강남점"), "스타벅스 강남점");
    }

    #[test]
    fn merchant_prefix_and_casefold() {
        assert_eq!(normalize_merchant("체크카드 스타벅스"), "스타벅스");
        assert_eq!(normalize_merchant("ＧＳ２５"), "gs25");
        // 접두어가 단어 중간이면 제거하지 않는다
        assert_eq!(normalize_merchant("우리카드 대금"), "우리카드 대금");
    }

    #[test]
    fn datetime_formats() {
        assert_eq!(
            normalize_datetime("2026.06.02 09:14:33", 1).unwrap(),
            ("2026-06-02".into(), Some("09:14:33".into()))
        );
        assert_eq!(
            normalize_datetime("2026/06/03", 1).unwrap(),
            ("2026-06-03".into(), None)
        );
        assert!(normalize_datetime("2026-13-01", 1).is_err());
        assert!(normalize_datetime("06/03/2026", 1).is_err());
    }
}
