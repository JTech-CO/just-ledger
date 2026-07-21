//! 금액 파싱 — 은행별 표기(천단위 콤마, △, 괄호, +/-)를 최소 화폐 단위 i64 로.
//! 부동소수점을 절대 경유하지 않는다 (INV-4). KRW 는 소수 자릿수가 없으므로
//! 소수점이 나타나면 포맷 오류로 거절한다 (조용한 절삭 금지).

use crate::error::ParseError;

/// 계약 moneyMinor 상한: 최대 18자리 (i64 안전 범위)
const MAX_ABS: i64 = 999_999_999_999_999_999;

/// "4,500" / "△52000" / "(1,000)" / "+1250" / "-3,200" / "0" → i64
pub fn parse_amount(raw: &str, row: usize) -> Result<i64, ParseError> {
    let s = raw.trim();
    if s.is_empty() {
        return Err(ParseError::Row(row, "금액 필드가 비어 있음".into()));
    }

    // 음수 표기 판별: △(U+25B3)·▲(U+25B2)·선행 '-'·괄호
    let (negative, body): (bool, &str) = if let Some(rest) = s.strip_prefix('△') {
        (true, rest)
    } else if let Some(rest) = s.strip_prefix('▲') {
        (true, rest)
    } else if let Some(rest) = s.strip_prefix('-') {
        (true, rest)
    } else if let Some(rest) = s.strip_prefix('+') {
        (false, rest)
    } else if s.starts_with('(') && s.ends_with(')') {
        (true, &s[1..s.len() - 1])
    } else {
        (false, s)
    };

    let mut value: i64 = 0;
    let mut digits = 0usize;
    for c in body.chars() {
        match c {
            '0'..='9' => {
                let d = (c as u8 - b'0') as i64;
                value = value
                    .checked_mul(10)
                    .and_then(|v| v.checked_add(d))
                    .ok_or_else(|| ParseError::Row(row, "금액 자릿수 초과".into()))?;
                digits += 1;
            }
            ',' => {} // 천단위 구분자
            '.' => {
                // KRW 최소 단위엔 소수점이 없다 — 절삭하지 않고 거절한다
                return Err(ParseError::Row(row, "소수점 금액은 지원하지 않음".into()));
            }
            _ => {
                return Err(ParseError::Row(row, "금액에 허용되지 않는 문자".into()));
            }
        }
    }
    if digits == 0 {
        return Err(ParseError::Row(row, "금액에 숫자가 없음".into()));
    }
    if value > MAX_ABS {
        return Err(ParseError::Row(row, "금액이 계약 상한(18자리) 초과".into()));
    }
    Ok(if negative { -value } else { value })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_and_commas() {
        assert_eq!(parse_amount("0", 1).unwrap(), 0);
        assert_eq!(parse_amount("4,500", 1).unwrap(), 4500);
        assert_eq!(parse_amount("3,500,000", 1).unwrap(), 3_500_000);
    }

    #[test]
    fn negative_notations() {
        assert_eq!(parse_amount("△52000", 1).unwrap(), -52000);
        assert_eq!(parse_amount("▲1,000", 1).unwrap(), -1000);
        assert_eq!(parse_amount("(1,000)", 1).unwrap(), -1000);
        assert_eq!(parse_amount("-3,200", 1).unwrap(), -3200);
        assert_eq!(parse_amount("+1250", 1).unwrap(), 1250);
    }

    #[test]
    fn rejects_decimal_and_garbage() {
        assert!(parse_amount("1234.00", 1).is_err());
        assert!(parse_amount("12a3", 1).is_err());
        assert!(parse_amount("", 1).is_err());
        assert!(parse_amount("△", 1).is_err());
    }

    #[test]
    fn contract_upper_bound() {
        assert_eq!(
            parse_amount("999,999,999,999,999,999", 1).unwrap(),
            999_999_999_999_999_999
        );
        assert!(parse_amount("1,000,000,000,000,000,000", 1).is_err());
    }
}
