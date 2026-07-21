//! 정규화된 명세서 레코드 — contracts/statement-record.schema.json 과 1:1.
//! 이 형태(적요·상대처 포함)는 평문으로 서버에 가지 않는다 (INV-6).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StatementRecord {
    /// BLAKE3(normalize(일시) ‖ 금액 ‖ normalize(상대처) ‖ 동일튜플 순번), hex 64자
    pub source_hash: String,
    /// YYYY-MM-DD
    pub occurred_on: String,
    /// HH:MM:SS (명세서에 시각이 있을 때만)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub occurred_time: Option<String>,
    /// 부호 있는 최소 화폐 단위 정수 문자열 (출금 음수)
    pub amount_minor: String,
    /// ISO 4217
    pub currency: String,
    /// 적요 (NFKC·공백 축약 후)
    pub description: String,
    /// 상대처/의뢰인/수취인 (있는 포맷만). 지문 상점 성분에 사용될 수 있는 '불변' 필드다.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub counterparty: Option<String>,
    /// 사용자 메모 (토스 등). 거래 후 언제든 편집되는 '가변' 필드라 지문에 넣지 않는다.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub memo: Option<String>,
    /// 거래 후 잔액 (있는 포맷만)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub balance_minor: Option<String>,
}

/// 파서 최상위 출력
#[derive(Debug, Serialize, Deserialize)]
pub struct Parsed {
    /// 감지된 은행 프로파일 식별자: "kb" | "hana" | "toss"
    pub bank: String,
    pub records: Vec<StatementRecord>,
}
