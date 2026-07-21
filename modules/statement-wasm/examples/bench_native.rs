//! 네이티브 파싱 벤치 — wasm 배수 파악용 (cargo run --release --example bench_native).
//! DoD 3 의 정본 계측은 make bench-wasm (wasm 경로).

use statement_wasm::parse::{derive_fingerprint_key, parse_statement_bytes};
use std::time::Instant;

fn main() {
    let merchants = [
        "스타벅스 강남점",
        "지에스25 서울역점",
        "쿠팡 주식회사",
        "넷플릭스서비시스코리아",
        "김밥천국 역삼점",
    ];
    let mut csv = String::with_capacity(51 * 1024 * 1024);
    csv.push_str(
        "KB국민은행 거래내역조회\n계좌번호,123456-78-901234\n조회기간,2026.01.01 ~ 2026.12.31\n",
    );
    csv.push_str("순번,거래일시,적요,보낸분/받는분,출금액(원),입금액(원),잔액(원),거래점\n");
    let mut i: usize = 0;
    while csv.len() < 50 * 1024 * 1024 {
        i += 1;
        let amt = 1000 + (i % 90000);
        // 천단위 콤마 삽입 (간단 3자리 그룹)
        let s = amt.to_string();
        let mut grouped = String::new();
        for (j, c) in s.chars().enumerate() {
            if j > 0 && (s.len() - j).is_multiple_of(3) {
                grouped.push(',');
            }
            grouped.push(c);
        }
        csv.push_str(&format!(
            "{},2026.{:02}.{:02} {:02}:{:02}:00,체크카드,{},\"{}\",\"0\",\"1,000,000\",강남\n",
            i,
            1 + (i % 12),
            1 + (i % 28),
            i % 24,
            i % 60,
            merchants[i % merchants.len()],
            grouped
        ));
    }
    println!("합성 CSV: {:.1}MB, {}행", csv.len() as f64 / 1048576.0, i);

    let bytes = csv.as_bytes();
    let key = derive_fingerprint_key("bench");
    let t = Instant::now();
    let parsed = parse_statement_bytes(bytes, &key).unwrap();
    println!(
        "네이티브 파싱: {}건, {}ms",
        parsed.records.len(),
        t.elapsed().as_millis()
    );

    let t = Instant::now();
    let json = serde_json::to_string(&parsed).unwrap();
    println!(
        "직렬화: {:.1}MB, {}ms",
        json.len() as f64 / 1048576.0,
        t.elapsed().as_millis()
    );
}
