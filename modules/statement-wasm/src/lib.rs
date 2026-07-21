//! statement-wasm — 명세서 파싱·정규화·지문·암호화 (브라우저 Web Worker 에서 실행).
//!
//! 흐름 (백서 §4.2-2): 패스프레이즈 입력 → 파일 드롭 → 파싱·정규화·keyed BLAKE3 지문
//! → 암호화 → 업로드. 서버 가시 필드는 지문·일자·금액·통화뿐이고, 적요·상대처·메모는
//! cipher.blob 안에만 있다 (INV-6). 지문은 패스프레이즈 파생 키로 keyed 라 서버가
//! 재계산할 수 없다. 계약: contracts/statement-record.schema.json, ingest-payload.schema.json.

pub mod amount;
pub mod crypto;
pub mod csv;
pub mod decode;
pub mod error;
pub mod normalize;
pub mod parse;
pub mod profile;
pub mod record;

use error::ParseError;
use record::{Parsed, StatementRecord};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

/// 서버 가시 최소 레코드 (ingest-payload.records[])
#[derive(Debug, Serialize, Deserialize)]
pub struct MinimalRecord {
    pub source_hash: String,
    pub occurred_on: String,
    pub amount_minor: String,
    pub currency: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IngestPayload {
    pub account_id: String,
    pub filename: String,
    pub file_hash: String,
    pub record_count: u32,
    pub records: Vec<MinimalRecord>,
    pub cipher: crypto::CipherBox,
}

/// AEAD AAD = account_id ‖ US ‖ file_hash. 봉투의 서버 가시 필드에 blob 을 바인딩해
/// 다른 봉투로의 blob 스왑을 복호화 단계에서 거절한다.
fn cipher_aad(account_id: &str, file_hash: &str) -> Vec<u8> {
    let mut aad = Vec::with_capacity(account_id.len() + file_hash.len() + 1);
    aad.extend_from_slice(account_id.as_bytes());
    aad.push(0x1F);
    aad.extend_from_slice(file_hash.as_bytes());
    aad
}

/// 파싱된 전체 레코드 → 업로드 봉투. 전체 레코드(JSON)는 암호화 blob 으로만 실린다.
pub fn build_payload(
    parsed: &[StatementRecord],
    passphrase: &str,
    account_id: &str,
    filename: &str,
    file_bytes: &[u8],
) -> Result<IngestPayload, ParseError> {
    let file_hash = blake3::hash(file_bytes).to_hex().to_string();
    let full_json = serde_json::to_string(parsed)
        .map_err(|e| ParseError::Format(format!("직렬화 실패: {e}")))?;
    let aad = cipher_aad(account_id, &file_hash);
    let cipher = crypto::encrypt(full_json.as_bytes(), passphrase, &aad)?;

    Ok(IngestPayload {
        account_id: account_id.to_owned(),
        filename: filename.to_owned(),
        file_hash,
        record_count: parsed.len() as u32,
        records: parsed
            .iter()
            .map(|r| MinimalRecord {
                source_hash: r.source_hash.clone(),
                occurred_on: r.occurred_on.clone(),
                amount_minor: r.amount_minor.clone(),
                currency: r.currency.clone(),
            })
            .collect(),
        cipher,
    })
}

// ── wasm-bindgen 경계 (JSON 문자열 왕복 — 금액은 어차피 문자열) ──────────────

/// 파싱 + keyed 지문. passphrase 로 지문 전용 키를 파생한다 (서버는 이 키를 모른다).
#[wasm_bindgen]
pub fn parse_statement(bytes: &[u8], passphrase: &str) -> Result<String, JsError> {
    let key = parse::derive_fingerprint_key(passphrase);
    let parsed: Parsed = parse::parse_statement_bytes(bytes, &key).map_err(to_js)?;
    serde_json::to_string(&parsed).map_err(|e| JsError::new(&e.to_string()))
}

/// 파싱만 하고 건수 반환 — 업로드 전 사전 스캔(진행률 총량)·벤치 계측용.
#[wasm_bindgen]
pub fn parse_statement_count(bytes: &[u8], passphrase: &str) -> Result<u32, JsError> {
    let key = parse::derive_fingerprint_key(passphrase);
    let parsed = parse::parse_statement_bytes(bytes, &key).map_err(to_js)?;
    Ok(parsed.records.len() as u32)
}

#[wasm_bindgen]
pub fn build_ingest_payload(
    records_json: &str,
    passphrase: &str,
    account_id: &str,
    filename: &str,
    file_bytes: &[u8],
) -> Result<String, JsError> {
    let records: Vec<StatementRecord> =
        serde_json::from_str(records_json).map_err(|e| JsError::new(&e.to_string()))?;
    let payload =
        build_payload(&records, passphrase, account_id, filename, file_bytes).map_err(to_js)?;
    serde_json::to_string(&payload).map_err(|e| JsError::new(&e.to_string()))
}

/// 로컬 표시·검증용 복호화 (서버는 이 함수를 가질 수 없다 — 키가 없으므로).
/// AAD 로 봉투 필드를 바인딩해 blob 스왑을 거절한다.
#[wasm_bindgen]
pub fn decrypt_ingest_blob(payload_json: &str, passphrase: &str) -> Result<String, JsError> {
    let payload: IngestPayload =
        serde_json::from_str(payload_json).map_err(|e| JsError::new(&e.to_string()))?;
    let aad = cipher_aad(&payload.account_id, &payload.file_hash);
    let plain = crypto::decrypt(&payload.cipher, passphrase, &aad).map_err(to_js)?;
    String::from_utf8(plain).map_err(|e| JsError::new(&e.to_string()))
}

fn to_js(e: ParseError) -> JsError {
    JsError::new(&e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// M3 DoD 4 의 축소판: 업로드 봉투 바이트에 평문 적요·상대처·메모가 없어야 한다
    #[test]
    fn payload_contains_no_plaintext_description() {
        let csv = "\u{FEFF}거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n\
                   2026-06-01 08:12:45,스타벅스 강남점,체크카드,-4500,150800,회사근처\n";
        let key = parse::derive_fingerprint_key("패스프레이즈");
        let parsed = parse::parse_statement_bytes(csv.as_bytes(), &key).unwrap();
        let payload = build_payload(
            &parsed.records,
            "패스프레이즈",
            "11111111-1111-1111-1111-111111111111",
            "stmt.csv",
            csv.as_bytes(),
        )
        .unwrap();
        let wire = serde_json::to_string(&payload).unwrap();
        assert!(!wire.contains("스타벅스"));
        assert!(!wire.contains("회사근처")); // 메모도 blob 안에만
        assert!(wire.contains("-4500"));
        assert!(wire.contains("2026-06-01"));

        // 복호화하면 전체 레코드(메모 포함)가 복원된다
        let payload_json = serde_json::to_string(&payload).unwrap();
        let payload_back: IngestPayload = serde_json::from_str(&payload_json).unwrap();
        let aad = cipher_aad(&payload_back.account_id, &payload_back.file_hash);
        let plain = crypto::decrypt(&payload_back.cipher, "패스프레이즈", &aad).unwrap();
        let restored: Vec<record::StatementRecord> =
            serde_json::from_str(std::str::from_utf8(&plain).unwrap()).unwrap();
        assert_eq!(restored, parsed.records);
        assert_eq!(restored[0].description, "스타벅스 강남점");
        assert_eq!(restored[0].memo.as_deref(), Some("회사근처"));
    }

    /// blob 을 다른 봉투(account_id 변조)로 스왑하면 복호화 거절 (AAD 바인딩)
    #[test]
    fn blob_swap_rejected() {
        let csv = "\u{FEFF}거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n\
                   2026-06-01 08:12:45,가게,체크카드,-1000,1000,\n";
        let key = parse::derive_fingerprint_key("pw");
        let parsed = parse::parse_statement_bytes(csv.as_bytes(), &key).unwrap();
        let mut payload =
            build_payload(&parsed.records, "pw", "acct-A", "s.csv", csv.as_bytes()).unwrap();
        payload.account_id = "acct-B".to_owned(); // 봉투 변조
                                                  // decrypt_ingest_blob 와 동일 경로 (wasm-bindgen 래퍼는 네이티브 테스트 불가 —
                                                  // JsError 가 wasm 전용이라 내부 API 로 같은 의미를 검증한다)
        let aad = cipher_aad(&payload.account_id, &payload.file_hash);
        assert!(crypto::decrypt(&payload.cipher, "pw", &aad).is_err());
        // 원본 봉투 필드면 성공 (대조군)
        let aad_ok = cipher_aad("acct-A", &payload.file_hash);
        assert!(crypto::decrypt(&payload.cipher, "pw", &aad_ok).is_ok());
    }
}
