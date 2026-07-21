//! 입력 바이트 → 문자열. 은행 CSV 는 CP949(국민·하나)와 UTF-8(BOM 포함, 토스)이 섞여 있다.
//! 판별 규칙: UTF-8 BOM → UTF-8 / 유효한 UTF-8 → UTF-8 / 그 외 → CP949(WHATWG EUC-KR).
//! 유효한 UTF-8 은 복사 없이 빌린다 (50MB 파일 기준 수십 ms 절약 — DoD 3).

use crate::error::ParseError;
use std::borrow::Cow;

pub fn decode(bytes: &[u8]) -> Result<Cow<'_, str>, ParseError> {
    // UTF-8 BOM
    let body = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);

    if let Ok(s) = std::str::from_utf8(body) {
        return Ok(Cow::Borrowed(s));
    }

    // encoding_rs 의 EUC-KR 은 실무 CP949(windows-949) 와 동일 매핑이다.
    let (cow, _, had_errors) = encoding_rs::EUC_KR.decode(body);
    if had_errors {
        return Err(ParseError::Encoding(
            "UTF-8 도 CP949 도 아닌 바이트 열".into(),
        ));
    }
    Ok(Cow::Owned(cow.into_owned()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf8_bom_stripped() {
        let mut b = vec![0xEF, 0xBB, 0xBF];
        b.extend_from_slice("가나다".as_bytes());
        assert_eq!(decode(&b).unwrap(), "가나다");
    }

    #[test]
    fn cp949_decoded() {
        let (enc, _, _) = encoding_rs::EUC_KR.encode("은행,거래");
        assert_eq!(decode(&enc).unwrap(), "은행,거래");
    }

    #[test]
    fn plain_utf8_borrows() {
        let s = "토스뱅크".as_bytes();
        match decode(s).unwrap() {
            Cow::Borrowed(v) => assert_eq!(v, "토스뱅크"),
            Cow::Owned(_) => panic!("유효 UTF-8 인데 복사됨"),
        }
    }
}
