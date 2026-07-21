//! 파싱·암호화 오류. 오류 메시지에 명세서 내용(적요·상대처)을 싣지 않는다 —
//! 오류가 서버 로그로 전파되어도 평문이 남지 않게 (INV-6).

use std::fmt;

#[derive(Debug)]
pub enum ParseError {
    Encoding(String),
    /// (행 번호 1-기준, 사유) — 사유에는 필드 '종류'만, 값은 넣지 않는다
    Row(usize, String),
    Format(String),
    Crypto(String),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::Encoding(m) => write!(f, "인코딩 오류: {m}"),
            ParseError::Row(n, m) => write!(f, "{n}행 파싱 오류: {m}"),
            ParseError::Format(m) => write!(f, "포맷 오류: {m}"),
            ParseError::Crypto(m) => write!(f, "암호화 오류: {m}"),
        }
    }
}

impl std::error::Error for ParseError {}
