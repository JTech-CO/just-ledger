// 최소 IndexedDB 래퍼 — 로컬 앱(오프라인 실사용) 영속 계층. 외부 의존 없음.
// 저장소: accounts(keyPath id), txns(keyPath id), meta(keyPath k).
//
// 데이터는 이 브라우저 프로파일·이 기기에만 저장된다. 동기화·백업은 없다
// (앱이 내보내기/가져오기로 백업 수단을 제공한다).

const DB_NAME = 'just-ledger-local';
const DB_VERSION = 1;

/** @returns {Promise<IDBDatabase>} */
function open() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('accounts')) db.createObjectStore('accounts', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('txns')) db.createObjectStore('txns', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta', { keyPath: 'k' });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

/** @param {IDBTransaction} tx */
function done(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

/** @param {string} store @returns {Promise<Array<any>>} */
export async function getAll(store) {
  const db = await open();
  try {
    const tx = db.transaction(store, 'readonly');
    const req = tx.objectStore(store).getAll();
    const rows = await new Promise((resolve, reject) => {
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
    return rows;
  } finally {
    db.close();
  }
}

/** 한 저장소에 여러 레코드를 추가/갱신 */
export async function putAll(store, records) {
  const db = await open();
  try {
    const tx = db.transaction(store, 'readwrite');
    const os = tx.objectStore(store);
    for (const r of records) os.put(r);
    await done(tx);
  } finally {
    db.close();
  }
}

/** 한 레코드 추가/갱신 */
export async function put(store, record) {
  return putAll(store, [record]);
}

/** 여러 저장소를 비운다 */
export async function clearStores(stores) {
  const db = await open();
  try {
    const tx = db.transaction(stores, 'readwrite');
    for (const s of stores) tx.objectStore(s).clear();
    await done(tx);
  } finally {
    db.close();
  }
}

/** 저장소 전체를 원자적으로 교체(가져오기용) */
export async function replaceAll(data) {
  const db = await open();
  try {
    const tx = db.transaction(['accounts', 'txns'], 'readwrite');
    tx.objectStore('accounts').clear();
    tx.objectStore('txns').clear();
    for (const a of data.accounts || []) tx.objectStore('accounts').put(a);
    for (const t of data.txns || []) tx.objectStore('txns').put(t);
    await done(tx);
  } finally {
    db.close();
  }
}
