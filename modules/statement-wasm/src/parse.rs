//! 파싱 본체: 디코드 → 프로파일 감지 → 행 해석 → 정규화 → 지문.
//!
//! 지문 (백서 §4.3 확장):
//!   source_hash = BLAKE3( norm_datetime ‖ US ‖ amount ‖ US ‖ norm_merchant ‖ US ‖ ordinal )
//! ordinal 은 같은 파일 안에서 (일시, 금액, 상점) 이 완전히 같은 튜플의 발생 순번(0부터).
//! 백서 공식 그대로면 같은 날 같은 가게 같은 금액의 '정당한 중복 거래'가 서버
//! 유니크 제약에서 유실된다. 순번은 파일 행 순서를 따르므로 재업로드에도 결정론적 —
//! 중복 제거(DoD 2)는 그대로 성립한다. (결정 로그 2026-07-21)
//!
//! 성능(DoD 3): 컬럼 인덱스는 루프 전 1회 해석, 순번 맵 키는 튜플 문자열 대신
//! 튜플 해시([u8;32], Copy) — 지문 공식·산출값은 불변이다.

use crate::amount::parse_amount;
use crate::csv::{split_fields, split_lines};
use crate::decode::decode;
use crate::error::ParseError;
use crate::normalize::{normalize_datetime, normalize_merchant, normalize_text};
use crate::profile::{detect_profile, field, Bank};
use crate::record::{Parsed, StatementRecord};
use std::collections::HashMap;

/// 지문 입력 구분자 (필드 경계 모호성 차단)
const US: &[u8] = &[0x1F];

fn tuple_hasher(norm_datetime: &str, amount_minor: i64, norm_merchant: &str) -> blake3::Hasher {
    let mut h = blake3::Hasher::new();
    h.update(norm_datetime.as_bytes());
    h.update(US);
    h.update(amount_minor.to_string().as_bytes());
    h.update(US);
    h.update(norm_merchant.as_bytes());
    h.update(US);
    h
}

pub fn fingerprint(
    norm_datetime: &str,
    amount_minor: i64,
    norm_merchant: &str,
    ordinal: u32,
) -> String {
    let mut h = tuple_hasher(norm_datetime, amount_minor, norm_merchant);
    h.update(ordinal.to_string().as_bytes());
    h.finalize().to_hex().to_string()
}

/// 은행별로 미리 해석한 컬럼 인덱스 (행 루프에서 이름 조회 금지)
enum Cols {
    Split {
        dt: usize,
        desc: usize,
        cp: usize,
        out: usize,
        inn: usize,
        bal: usize,
    },
    Signed {
        dt: usize,
        desc: usize,
        amt: usize,
        bal: usize,
        memo: usize,
    },
}

pub fn parse_statement_bytes(bytes: &[u8]) -> Result<Parsed, ParseError> {
    let text = decode(bytes)?;
    let lines = split_lines(&text);
    let profile = detect_profile(&lines)?;

    let cols = match profile.bank {
        Bank::Kb => Cols::Split {
            dt: profile.idx("거래일시")?,
            desc: profile.idx("적요")?,
            cp: profile.idx("보낸분/받는분")?,
            out: profile.idx("출금액(원)")?,
            inn: profile.idx("입금액(원)")?,
            bal: profile.idx("잔액(원)")?,
        },
        Bank::Hana => Cols::Split {
            dt: profile.idx("거래일시")?,
            desc: profile.idx("적요")?,
            cp: profile.idx("의뢰인/수취인")?,
            out: profile.idx("출금액")?,
            inn: profile.idx("입금액")?,
            bal: profile.idx("거래후잔액")?,
        },
        Bank::Toss => Cols::Signed {
            dt: profile.idx("거래 일시")?,
            desc: profile.idx("적요")?,
            amt: profile.idx("거래 금액")?,
            bal: profile.idx("거래 후 잔액")?,
            memo: profile.idx("메모")?,
        },
    };

    let n_rows = lines.len().saturating_sub(profile.header_idx + 1);
    let mut records = Vec::with_capacity(n_rows);
    // 튜플 해시 → 다음 발생 순번 (키가 Copy 라 행마다 문자열 클론이 없다)
    let mut seen: HashMap<[u8; 32], u32> = HashMap::with_capacity(n_rows);

    for (i, line) in lines.iter().enumerate().skip(profile.header_idx + 1) {
        let row = i + 1; // 사람 기준 행 번호
        let fields = split_fields(line);

        let (raw_dt, description, counterparty, amount, balance): (
            &str,
            String,
            Option<String>,
            i64,
            Option<i64>,
        ) = match &cols {
            Cols::Split {
                dt,
                desc,
                cp,
                out,
                inn,
                bal,
            } => {
                let out_v = parse_amount(field(&fields, *out, row)?, row)?;
                let inn_v = parse_amount(field(&fields, *inn, row)?, row)?;
                let bal_v = parse_amount(field(&fields, *bal, row)?, row)?;
                let cp_v = normalize_text(field(&fields, *cp, row)?);
                (
                    field(&fields, *dt, row)?,
                    normalize_text(field(&fields, *desc, row)?),
                    if cp_v.is_empty() { None } else { Some(cp_v) },
                    inn_v - out_v,
                    Some(bal_v),
                )
            }
            Cols::Signed {
                dt,
                desc,
                amt,
                bal,
                memo,
            } => {
                let amt_v = parse_amount(field(&fields, *amt, row)?, row)?;
                let bal_v = parse_amount(field(&fields, *bal, row)?, row)?;
                let memo_v = normalize_text(field(&fields, *memo, row)?);
                (
                    field(&fields, *dt, row)?,
                    normalize_text(field(&fields, *desc, row)?),
                    if memo_v.is_empty() {
                        None
                    } else {
                        Some(memo_v)
                    },
                    amt_v,
                    Some(bal_v),
                )
            }
        };

        let (occurred_on, occurred_time) = normalize_datetime(raw_dt, row)?;

        // 지문용 상점: 상대처가 있으면 상대처, 없으면 적요
        let merchant_src = counterparty.as_deref().unwrap_or(&description);
        let norm_merchant = normalize_merchant(merchant_src);
        let norm_dt = match &occurred_time {
            Some(t) => format!("{occurred_on}T{t}"),
            None => occurred_on.clone(),
        };

        // 순번 키 = 튜플 해시. Hasher 클론은 상태(~2KB) 복사라 행마다 하면 오히려
        // 느리다 — 작은 입력이므로 두 번 해싱하는 쪽이 압도적으로 저렴하다.
        let key: [u8; 32] = *tuple_hasher(&norm_dt, amount, &norm_merchant)
            .finalize()
            .as_bytes();
        let ordinal = *seen.get(&key).unwrap_or(&0);
        seen.insert(key, ordinal + 1);

        let mut h = tuple_hasher(&norm_dt, amount, &norm_merchant);
        h.update(ordinal.to_string().as_bytes());
        let source_hash = h.finalize().to_hex().to_string();

        records.push(StatementRecord {
            source_hash,
            occurred_on,
            occurred_time,
            amount_minor: amount.to_string(),
            currency: "KRW".to_owned(),
            description,
            counterparty,
            balance_minor: balance.map(|b| b.to_string()),
        });
    }

    Ok(Parsed {
        bank: profile.bank.id().to_owned(),
        records,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_tuples_get_distinct_ordinals() {
        let csv = "\u{FEFF}거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n\
                   2026-06-01 08:12:45,GS25,체크카드,-3200,150800,\n\
                   2026-06-01 08:12:45,GS25,체크카드,-3200,147600,\n";
        let p = parse_statement_bytes(csv.as_bytes()).unwrap();
        assert_eq!(p.records.len(), 2);
        assert_ne!(p.records[0].source_hash, p.records[1].source_hash);

        // 재파싱 시 완전히 같은 지문 (재업로드 결정론 — DoD 2 의 전제)
        let p2 = parse_statement_bytes(csv.as_bytes()).unwrap();
        assert_eq!(p.records[0].source_hash, p2.records[0].source_hash);
        assert_eq!(p.records[1].source_hash, p2.records[1].source_hash);
    }

    #[test]
    fn incremental_hash_equals_reference_formula() {
        // 최적화(튜플 해시 재사용)가 공식 정의와 같은 값을 내는지 고정 검증
        let h = fingerprint("2026-06-01T08:12:45", -3200, "gs25", 1);
        let mut r = blake3::Hasher::new();
        r.update("2026-06-01T08:12:45".as_bytes());
        r.update(&[0x1F]);
        r.update("-3200".as_bytes());
        r.update(&[0x1F]);
        r.update("gs25".as_bytes());
        r.update(&[0x1F]);
        r.update("1".as_bytes());
        assert_eq!(h, r.finalize().to_hex().to_string());
    }

    #[test]
    fn merchant_normalization_merges_variants() {
        // 전각/카드 접두어 표기가 달라도 같은 상점이면 같은 지문 (다른 시각 제외)
        let a = fingerprint(
            "2026-06-01T08:00:00",
            -1000,
            &crate::normalize::normalize_merchant("체크카드 ＧＳ２５"),
            0,
        );
        let b = fingerprint(
            "2026-06-01T08:00:00",
            -1000,
            &crate::normalize::normalize_merchant("gs25"),
            0,
        );
        assert_eq!(a, b);
    }
}
