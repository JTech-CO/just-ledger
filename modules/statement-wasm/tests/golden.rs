//! 골든 테스트 (M3 DoD 1): 은행 CSV 3종의 파싱 결과가 기대 출력과 완전 일치.
//! 기대 파일 갱신: UPDATE_GOLDEN=1 cargo test — 갱신 후 반드시 사람이 diff 를
//! 검토(금액·부호·날짜·적요·지문)하고 커밋한다. 지문(source_hash)은 알고리즘
//! 회귀의 기준선이다.

use statement_wasm::parse::{derive_fingerprint_key, parse_statement_bytes};
use std::fs;
use std::path::PathBuf;

/// 골든 지문의 회귀 기준 키 — 고정 패스프레이즈에서 파생한다.
/// (실사용 키는 사용자 패스프레이즈에서 나오지만, 골든은 결정론적 고정값이 필요하다.)
fn golden_key() -> [u8; 32] {
    derive_fingerprint_key("golden-fixture-passphrase")
}

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/ingest")
        .join(name)
}

fn run_golden(csv_name: &str, expected_bank: &str) {
    let bytes = fs::read(fixture(csv_name)).expect("픽스처 읽기 실패");
    let parsed = parse_statement_bytes(&bytes, &golden_key()).expect("파싱 실패");
    assert_eq!(parsed.bank, expected_bank, "은행 프로파일 오감지");

    let got = serde_json::to_value(&parsed.records).unwrap();
    let expected_path = fixture(&csv_name.replace(".csv", ".expected.json"));

    if std::env::var("UPDATE_GOLDEN").as_deref() == Ok("1") {
        fs::write(
            &expected_path,
            serde_json::to_string_pretty(&got).unwrap() + "\n",
        )
        .expect("골든 기록 실패");
        eprintln!(
            "골든 갱신됨: {} — diff 검토 후 커밋할 것",
            expected_path.display()
        );
        return;
    }

    let expected: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(&expected_path).expect("기대 파일 없음 — UPDATE_GOLDEN=1 로 생성"),
    )
    .unwrap();
    assert_eq!(got, expected, "{csv_name}: 파싱 결과가 골든과 다름");
}

#[test]
fn golden_kb() {
    run_golden("kb.csv", "kb");
}

#[test]
fn golden_hana() {
    run_golden("hana.csv", "hana");
}

#[test]
fn golden_toss() {
    run_golden("toss.csv", "toss");
}

/// 파일 단위 재파싱 결정론 — 재업로드 중복 제거(DoD 2)의 클라이언트 측 전제
#[test]
fn reparse_is_deterministic() {
    for name in ["kb.csv", "hana.csv", "toss.csv"] {
        let bytes = fs::read(fixture(name)).unwrap();
        let a = parse_statement_bytes(&bytes, &golden_key()).unwrap();
        let b = parse_statement_bytes(&bytes, &golden_key()).unwrap();
        let ha: Vec<_> = a.records.iter().map(|r| &r.source_hash).collect();
        let hb: Vec<_> = b.records.iter().map(|r| &r.source_hash).collect();
        assert_eq!(ha, hb, "{name}: 재파싱 지문 불일치");
    }
}
