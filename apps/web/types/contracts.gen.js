// AUTO-GENERATED from contracts/*.schema.json — 수정 금지. pnpm gen:types 로 재생성.
// 금액(MoneyMinor/PositiveMinor)은 최소 화폐 단위 정수 '문자열'이다 (INV-4).

/** @typedef {string} Uuid  */

/** @typedef {string} Currency — ISO 4217 alpha-3. DB CHAR(3). */

/** @typedef {string} Date — 달력 날짜 YYYY-MM-DD (occurred_on 등). */

/** @typedef {string} Timestamp — RFC3339 / ISO8601 UTC 타임스탬프 (posted_at 등). */

/** @typedef {string} MoneyMinor — 부호 있는 최소 화폐 단위 정수를 문자열로. 잔액·증감 델타에 사용. 선행 0 금지. 최대 18자리로 i64/BIGINT 범위 안에 머문다(19자리는 i64 최대 9.22e18을 넘길 수 있어 금지). */

/** @typedef {string} PositiveMinor — 양의 최소 화폐 단위 정수 문자열. entry.amount_minor 전용 (INV-2: > 0, 부호는 direction이 담당). 최대 18자리(i64/BIGINT 안전 범위). */

/** @typedef {{num: any, den: any}} Ratio — 환율은 실수가 아니라 유리수 쌍 num/den 으로 보관한다. 두 값 모두 최소단위 정수 문자열, den > 0. */

/** @typedef {"asset"|"liability"|"equity"|"income"|"expense"} AccountType  */

/** @typedef {"draft"|"classified"|"posted"|"settled"} TxnStatus — draft → classified → posted → settled. posted 이상은 INV-1 균형 검사 대상, settled는 INV-3 불변. */

/** @typedef {"debit"|"credit"} Direction  */

/** @typedef {"manual"|"prolog"|"lua"|"haskell"} RuleSource  */

/** @typedef {"received"|"parsing"|"deduping"|"drafting"|"done"|"failed"} IngestState  */

/**
 * @typedef {Object} Account — 복식부기 계정. 데이터 모델 §2.3-1. 잔액은 이 계약에 포함하지 않는다(파생값, 롤업 함수 산출).
 * @property {Uuid} id
 * @property {string} code
 * @property {string} name
 * @property {AccountType} type
 * @property {Currency} currency
 * @property {Uuid|null} [parent_id]
 * @property {boolean} is_closed
 */

/**
 * @typedef {Object} BalanceRow — 계정 × 통화 잔액 스냅샷. balance_minor = sum(debit) - sum(credit), posted 이상만 반영 (DB account_balance 산출). 실시간 balance_changed 이벤트의 row 와 잔액 조회 응답이 공유하는 단일 형태.
 * @property {Uuid} account_id
 * @property {Currency} currency
 * @property {MoneyMinor} balance_minor
 */

/**
 * @typedef {Object} Entry — 분개 행. 데이터 모델 §2.3-3. amount_minor는 항상 양수 문자열이고 부호는 direction이 담당한다 (INV-2). 한 txn의 통화별 debit 합 = credit 합 (INV-1).
 * @property {string} [id]
 * @property {Uuid} [txn_id]
 * @property {Uuid} account_id
 * @property {Direction} direction
 * @property {PositiveMinor} amount_minor
 * @property {Currency} currency
 */

/**
 * @typedef {Object} IngestBatch — 명세서 인제스트 배치. 데이터 모델 §2.3-8. 업로드 페이로드는 클라이언트에서 암호화되며, 평문 상대처·적요는 서버에 도달하지 않는다 (INV-6).
 * @property {Uuid} id
 * @property {Uuid|null} [account_id]
 * @property {string} filename
 * @property {number} [row_count]
 * @property {IngestState} state
 * @property {Timestamp|null} [started_at]
 * @property {Timestamp|null} [finished_at]
 */

/**
 * @typedef {Object} IngestPayload — 클라이언트 → 서버 인제스트 업로드 봉투. 서버가 볼 수 있는 것은 원장 구성에 필요한 최소 필드(지문·일자·금액·통화)뿐이며, 적요·상대처가 담긴 전체 레코드는 cipher.blob 안에만 존재한다 — 키는 사용자 패스프레이즈 Argon2id 파생으로 서버는 복호화할 수 없다 (INV-6, M3 DoD 4 바이트 검사 대상).
 * @property {Uuid} account_id
 * @property {string} filename
 * @property {string} file_hash
 * @property {number} record_count
 * @property {Array<{source_hash: string, occurred_on: Date, amount_minor: MoneyMinor, currency: Currency}>} records
 * @property {{alg: "argon2id-chacha20poly1305", salt: string, nonce: string, m_kib: number, t: number, p: number, blob: string}} cipher
 */

/** @typedef {{type: "balance_changed", row: BalanceRow}|{type: "settlement_done", period: {start: Date, end: Date}}|{type: "ingest_progress", batch_id: Uuid, state: IngestState, processed?: number, total?: number}} NotifyEvent — PostgreSQL NOTIFY → Elixir 채널 → 브라우저 store 로 흐르는 실시간 이벤트 프레임. store/ledgerStore.js applyRealtime 의 단일 진입점 계약. M1 DoD 6 / M7 검증 대상. */

/**
 * @typedef {Object} StatementRecord — 정규화된 명세서 레코드 — Rust WASM 파서의 출력이자 골든 픽스처 기대 형식. 클라이언트 전용 산물이다: description/counterparty/memo 가 포함된 이 형태는 절대 평문으로 서버에 전송·저장되지 않는다 (INV-6). 서버로 가는 것은 ingest-payload 의 최소 필드 + 암호화 blob 뿐.
 * @property {string} source_hash
 * @property {Date} occurred_on
 * @property {string} [occurred_time]
 * @property {MoneyMinor} amount_minor
 * @property {Currency} currency
 * @property {string} description
 * @property {string|null} [counterparty]
 * @property {string|null} [memo]
 * @property {MoneyMinor|null} [balance_minor]
 */

/**
 * @typedef {Object} Txn — 거래(전표). 데이터 모델 §2.3-2. entries를 함께 담아 원자적으로 생성한다. posted 이상 상태는 통화별 균형이 맞아야 한다 (INV-1). settled 기간은 불변 (INV-3).
 * @property {Uuid} [id]
 * @property {Date} occurred_on
 * @property {string} [memo]
 * @property {string} [source_hash]
 * @property {Uuid|null} [batch_id]
 * @property {TxnStatus} status
 * @property {Timestamp|null} [posted_at]
 * @property {Array<Entry>} entries
 */

export {};
