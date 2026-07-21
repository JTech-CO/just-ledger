//! 은행 프로파일 — 헤더 시그니처로 감지하고, 컬럼은 이름으로 해석한다
//! (인덱스 하드코딩 금지: 은행이 컬럼 순서를 바꿔도 이름이 살아 있으면 동작).
//! 프리앰블(계좌번호·조회기간 줄)은 헤더 행을 찾을 때까지 건너뛴다.
//!
//! 성능(DoD 3): 이름 → 인덱스 해석은 헤더에서 1회만 한다. 행 루프에서는
//! 미리 해석한 인덱스로 직접 접근한다 (행마다 문자열 조회 금지).

use crate::csv::split_fields;
use crate::error::ParseError;
use std::borrow::Cow;
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Bank {
    Kb,
    Hana,
    Toss,
}

impl Bank {
    pub fn id(&self) -> &'static str {
        match self {
            Bank::Kb => "kb",
            Bank::Hana => "hana",
            Bank::Toss => "toss",
        }
    }
}

pub struct Profile {
    pub bank: Bank,
    /// 헤더 행 인덱스 (split_lines 결과 기준)
    pub header_idx: usize,
    /// 정규화된 컬럼명 → 필드 인덱스
    cols: HashMap<String, usize>,
}

/// 컬럼명 정규화: 공백 제거 (예: "거래 일시" → "거래일시")
fn col_key(name: &str) -> String {
    name.split_whitespace().collect()
}

fn has(cols: &HashMap<String, usize>, name: &str) -> bool {
    cols.contains_key(&col_key(name))
}

/// 헤더 시그니처: 각 은행 export 를 유일하게 식별하는 컬럼 조합
fn detect_bank(cols: &HashMap<String, usize>) -> Option<Bank> {
    if has(cols, "출금액(원)") && has(cols, "입금액(원)") {
        return Some(Bank::Kb);
    }
    if has(cols, "출금액") && has(cols, "입금액") && has(cols, "거래후잔액") {
        return Some(Bank::Hana);
    }
    if has(cols, "거래 금액") && has(cols, "거래 후 잔액") {
        return Some(Bank::Toss);
    }
    None
}

pub fn detect_profile(lines: &[&str]) -> Result<Profile, ParseError> {
    // 프리앰블은 짧다 — 앞 20행 안에서 헤더를 찾는다
    for (i, line) in lines.iter().take(20).enumerate() {
        let fields = split_fields(line);
        let cols: HashMap<String, usize> = fields
            .iter()
            .enumerate()
            .map(|(idx, f)| (col_key(f.as_ref()), idx))
            .collect();
        if let Some(bank) = detect_bank(&cols) {
            return Ok(Profile {
                bank,
                header_idx: i,
                cols,
            });
        }
    }
    Err(ParseError::Format(
        "지원하는 은행 헤더를 찾지 못함 (kb/hana/toss)".into(),
    ))
}

impl Profile {
    /// 컬럼 인덱스 1회 해석 (행 루프 진입 전에 호출)
    pub fn idx(&self, name: &str) -> Result<usize, ParseError> {
        self.cols
            .get(&col_key(name))
            .copied()
            .ok_or_else(|| ParseError::Format(format!("컬럼 없음: {name}")))
    }
}

/// 해석된 인덱스로 행 필드 접근
pub fn field<'a>(
    fields: &'a [Cow<'a, str>],
    idx: usize,
    row: usize,
) -> Result<&'a str, ParseError> {
    fields
        .get(idx)
        .map(|s| s.as_ref())
        .ok_or_else(|| ParseError::Row(row, format!("필드 부족 (인덱스 {idx})")))
}
