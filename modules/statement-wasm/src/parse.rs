//! 파싱 본체: 디코드 → 프로파일 감지 → 행 해석 → 정규화 → 지문.
//!
//! 지문 (백서 §4.3 확장):
//!   source_hash = BLAKE3_keyed( fp_key, 일시 ‖ US ‖ 금액 ‖ US ‖ 정규화상점 ‖ US ‖ 순번 )
//! - keyed: 무키 해시면 서버가 (평문 일자·금액 + 상점명 사전)으로 오프라인 대조해
//!   상대처를 복원할 수 있다(INV-6 우회). fp_key 는 패스프레이즈에서 파생한 사용자별
//!   비밀 키이므로 서버는 지문을 재계산할 수 없다. 키가 사용자별 고정이라 재업로드
//!   결정론(중복 제거, DoD 2)은 그대로 성립한다.
//! - 상점 성분은 '불변' 필드만 쓴다: counterparty(상대처)가 있으면 그것, 없으면
//!   description(적요). 사용자 메모(토스)처럼 편집 가능한 필드는 memo 로 분리해
//!   지문에서 제외한다 — 넣으면 메모 편집만으로 지문이 바뀌어 겹침 재업로드에서
//!   같은 거래가 중복 유입된다. (결정 로그 2026-07-21)
//! - 순번(ordinal): 같은 파일 안에서 (일시, 금액, 상점) 완전 동일 튜플의 발생 순번.
//!   정당한 중복 거래(같은 날 같은 가게 같은 금액)의 유실을 막는다.

use crate::amount::{parse_amount, parse_amount_or_zero};
use crate::csv::{split_fields, split_lines};
use crate::decode::decode;
use crate::error::ParseError;
use crate::normalize::{normalize_datetime, normalize_merchant, normalize_text};
use crate::profile::{detect_profile, field, Bank};
use crate::record::{Parsed, StatementRecord};
use std::collections::HashMap;

/// 지문 입력 구분자 (필드 경계 모호성 차단)
const US: &[u8] = &[0x1F];

/// 패스프레이즈 → 지문 전용 32B 키. BLAKE3 KDF 모드는 빠르고(파싱마다 저렴) salt
/// 없이 결정론적이라 재업로드 시 같은 키를 낸다. 컨텍스트로 용도를 분리한다.
pub fn derive_fingerprint_key(passphrase: &str) -> [u8; 32] {
    blake3::derive_key(
        "just-ledger statement fingerprint v1",
        passphrase.as_bytes(),
    )
}

fn tuple_hasher(
    key: &[u8; 32],
    norm_datetime: &str,
    amount_minor: i64,
    norm_merchant: &str,
) -> blake3::Hasher {
    let mut h = blake3::Hasher::new_keyed(key);
    h.update(norm_datetime.as_bytes());
    h.update(US);
    h.update(amount_minor.to_string().as_bytes());
    h.update(US);
    h.update(norm_merchant.as_bytes());
    h.update(US);
    h
}

pub fn fingerprint(
    key: &[u8; 32],
    norm_datetime: &str,
    amount_minor: i64,
    norm_merchant: &str,
    ordinal: u32,
) -> String {
    let mut h = tuple_hasher(key, norm_datetime, amount_minor, norm_merchant);
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

pub fn parse_statement_bytes(bytes: &[u8], fp_key: &[u8; 32]) -> Result<Parsed, ParseError> {
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

        // description(적요), counterparty(상대처, 불변), memo(가변), amount, balance
        let (raw_dt, description, counterparty, memo, amount, balance): (
            &str,
            String,
            Option<String>,
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
                // 출금·입금은 미해당 칸이 공란인 은행이 있어 공란=0 으로 해석
                let out_v = parse_amount_or_zero(field(&fields, *out, row)?, row)?;
                let inn_v = parse_amount_or_zero(field(&fields, *inn, row)?, row)?;
                let bal_v = parse_amount(field(&fields, *bal, row)?, row)?;
                let cp_v = normalize_text(field(&fields, *cp, row)?);
                (
                    field(&fields, *dt, row)?,
                    normalize_text(field(&fields, *desc, row)?),
                    if cp_v.is_empty() { None } else { Some(cp_v) },
                    None,
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
                    None, // 토스는 상대처 정보가 없다 — 지문 상점은 적요(불변)를 쓴다
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

        // 지문용 상점: 불변 필드만 — 상대처가 있으면 상대처, 없으면 적요 (메모 제외)
        let merchant_src = counterparty.as_deref().unwrap_or(&description);
        let norm_merchant = normalize_merchant(merchant_src);
        let norm_dt = match &occurred_time {
            Some(t) => format!("{occurred_on}T{t}"),
            None => occurred_on.clone(),
        };

        // 순번 키 = 튜플 해시. 작은 입력이라 두 번 해싱이 Hasher 클론보다 저렴하다.
        let key: [u8; 32] = *tuple_hasher(fp_key, &norm_dt, amount, &norm_merchant)
            .finalize()
            .as_bytes();
        let ordinal = *seen.get(&key).unwrap_or(&0);
        seen.insert(key, ordinal + 1);

        let mut h = tuple_hasher(fp_key, &norm_dt, amount, &norm_merchant);
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
            memo,
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

    const K: &[u8; 32] = &[7u8; 32];

    #[test]
    fn identical_tuples_get_distinct_ordinals() {
        let csv = "\u{FEFF}거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n\
                   2026-06-01 08:12:45,GS25,체크카드,-3200,150800,\n\
                   2026-06-01 08:12:45,GS25,체크카드,-3200,147600,\n";
        let p = parse_statement_bytes(csv.as_bytes(), K).unwrap();
        assert_eq!(p.records.len(), 2);
        assert_ne!(p.records[0].source_hash, p.records[1].source_hash);

        // 재파싱 시 완전히 같은 지문 (재업로드 결정론 — DoD 2 의 전제)
        let p2 = parse_statement_bytes(csv.as_bytes(), K).unwrap();
        assert_eq!(p.records[0].source_hash, p2.records[0].source_hash);
        assert_eq!(p.records[1].source_hash, p2.records[1].source_hash);
    }

    #[test]
    fn memo_change_does_not_move_fingerprint() {
        // 메모만 다르고 나머지가 같은 두 파일 — 지문이 같아야 중복 제거가 성립한다
        let a = "\u{FEFF}거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n\
                 2026-06-10 21:15:03,친구에게 보냄,토스송금,-45000,102600,\n";
        let b = "\u{FEFF}거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n\
                 2026-06-10 21:15:03,친구에게 보냄,토스송금,-45000,102600,나중에 단 메모\n";
        let pa = parse_statement_bytes(a.as_bytes(), K).unwrap();
        let pb = parse_statement_bytes(b.as_bytes(), K).unwrap();
        assert_eq!(pa.records[0].source_hash, pb.records[0].source_hash);
        assert_eq!(pa.records[0].memo, None);
        assert_eq!(pb.records[0].memo.as_deref(), Some("나중에 단 메모"));
    }

    #[test]
    fn different_key_yields_different_fingerprint() {
        // 서버가 무키로 재계산할 수 없음을 대변: 키가 다르면 지문이 다르다
        let csv = "\u{FEFF}거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n\
                   2026-06-01 08:12:45,GS25,체크카드,-3200,150800,\n";
        let with_k1 = parse_statement_bytes(csv.as_bytes(), &[1u8; 32]).unwrap();
        let with_k2 = parse_statement_bytes(csv.as_bytes(), &[2u8; 32]).unwrap();
        assert_ne!(
            with_k1.records[0].source_hash,
            with_k2.records[0].source_hash
        );
    }

    #[test]
    fn incremental_hash_equals_reference_formula() {
        let h = fingerprint(K, "2026-06-01T08:12:45", -3200, "gs25", 1);
        let mut r = blake3::Hasher::new_keyed(K);
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
        let a = fingerprint(
            K,
            "2026-06-01T08:00:00",
            -1000,
            &crate::normalize::normalize_merchant("체크카드 ＧＳ２５"),
            0,
        );
        let b = fingerprint(
            K,
            "2026-06-01T08:00:00",
            -1000,
            &crate::normalize::normalize_merchant("gs25"),
            0,
        );
        assert_eq!(a, b);
    }
}
