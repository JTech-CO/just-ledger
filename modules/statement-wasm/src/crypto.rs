//! 페이로드 암호화 (백서 §7): 키는 사용자 패스프레이즈에서 Argon2id 로 파생하며
//! 서버에 저장하지 않는다 — 서버는 blob 을 복호화할 수 없다 (INV-6).
//!
//! 구성: Argon2id(passphrase, salt₁₆) → 32B 키 → ChaCha20-Poly1305(nonce₁₂, AAD).
//! 백서 §3.2 는 라이브러리로 age 를 들지만, age 의 패스프레이즈 모드는 내부 KDF 가
//! scrypt 라 같은 문서의 Argon2id 요구와 충돌한다. Argon2id + ChaCha20-Poly1305
//! (age 와 동일 계열 AEAD) 직접 구성으로 Argon2id 요구를 우선했다. (결정 로그 2026-07-21)
//!
//! 강건성: 서버를 왕복한 payload 는 신뢰할 수 없다 — 손상·변조된 봉투가 워커를
//! panic/OOM 시키지 않도록 nonce·blob 길이와 Argon2 파라미터 범위를 검증한다.
//! AAD 로 봉투의 서버 가시 필드(account_id‖file_hash)를 바인딩해 blob 스왑을 막는다.

use crate::error::ParseError;
use argon2::{Algorithm, Argon2, Params, Version};
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use serde::{Deserialize, Serialize};

/// Argon2id 파라미터 (OWASP 권장 최소선; 브라우저 WASM 에서 ~수백 ms)
pub const M_KIB: u32 = 19_456;
pub const T_COST: u32 = 2;
pub const P_COST: u32 = 1;

/// 계약 ingest-payload.schema.json 과 동일한 파라미터 허용 범위 — 변조 봉투로
/// m_kib 을 거대값으로 줘 wasm 워커를 OOM 시키는 것을 crypto 계층에서도 막는다.
const M_KIB_RANGE: std::ops::RangeInclusive<u32> = 8_192..=1_048_576;
const T_RANGE: std::ops::RangeInclusive<u32> = 1..=10;
const P_RANGE: std::ops::RangeInclusive<u32> = 1..=4;

const NONCE_LEN: usize = 12;
const SALT_LEN: usize = 16;
/// Poly1305 태그(16) 만큼은 최소 존재해야 유효 암호문
const MIN_BLOB_LEN: usize = 16;

#[derive(Debug, Serialize, Deserialize)]
pub struct CipherBox {
    pub alg: String,
    pub salt: String,
    pub nonce: String,
    pub m_kib: u32,
    pub t: u32,
    pub p: u32,
    pub blob: String,
}

fn derive_key(
    passphrase: &str,
    salt: &[u8],
    m_kib: u32,
    t: u32,
    p: u32,
) -> Result<[u8; 32], ParseError> {
    let params = Params::new(m_kib, t, p, Some(32))
        .map_err(|e| ParseError::Crypto(format!("Argon2 파라미터: {e}")))?;
    let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut key = [0u8; 32];
    argon
        .hash_password_into(passphrase.as_bytes(), salt, &mut key)
        .map_err(|e| ParseError::Crypto(format!("키 파생 실패: {e}")))?;
    Ok(key)
}

pub fn encrypt(plaintext: &[u8], passphrase: &str, aad: &[u8]) -> Result<CipherBox, ParseError> {
    let mut salt = [0u8; SALT_LEN];
    let mut nonce = [0u8; NONCE_LEN];
    getrandom::getrandom(&mut salt).map_err(|e| ParseError::Crypto(format!("CSPRNG: {e}")))?;
    getrandom::getrandom(&mut nonce).map_err(|e| ParseError::Crypto(format!("CSPRNG: {e}")))?;

    let key = derive_key(passphrase, &salt, M_KIB, T_COST, P_COST)?;
    let aead = ChaCha20Poly1305::new(Key::from_slice(&key));
    let ct = aead
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| ParseError::Crypto("암호화 실패".into()))?;

    Ok(CipherBox {
        alg: "argon2id-chacha20poly1305".to_owned(),
        salt: B64.encode(salt),
        nonce: B64.encode(nonce),
        m_kib: M_KIB,
        t: T_COST,
        p: P_COST,
        blob: B64.encode(ct),
    })
}

pub fn decrypt(cipher: &CipherBox, passphrase: &str, aad: &[u8]) -> Result<Vec<u8>, ParseError> {
    if cipher.alg != "argon2id-chacha20poly1305" {
        return Err(ParseError::Crypto(format!(
            "알 수 없는 알고리즘: {}",
            cipher.alg
        )));
    }
    // 파라미터 범위 검증 (변조 봉투의 OOM/오작동 차단) — from_slice panic 방지 전에.
    if !M_KIB_RANGE.contains(&cipher.m_kib)
        || !T_RANGE.contains(&cipher.t)
        || !P_RANGE.contains(&cipher.p)
    {
        return Err(ParseError::Crypto("Argon2 파라미터가 허용 범위 밖".into()));
    }

    let salt = B64
        .decode(&cipher.salt)
        .map_err(|_| ParseError::Crypto("salt base64 오류".into()))?;
    let nonce = B64
        .decode(&cipher.nonce)
        .map_err(|_| ParseError::Crypto("nonce base64 오류".into()))?;
    let blob = B64
        .decode(&cipher.blob)
        .map_err(|_| ParseError::Crypto("blob base64 오류".into()))?;

    // from_slice 는 길이 불일치 시 panic — 사전 검증으로 손상 봉투가 워커를 죽이지 않게.
    if nonce.len() != NONCE_LEN {
        return Err(ParseError::Crypto("nonce 길이 오류".into()));
    }
    if salt.is_empty() {
        return Err(ParseError::Crypto("salt 비어 있음".into()));
    }
    if blob.len() < MIN_BLOB_LEN {
        return Err(ParseError::Crypto("blob 이 너무 짧음".into()));
    }

    let key = derive_key(passphrase, &salt, cipher.m_kib, cipher.t, cipher.p)?;
    let aead = ChaCha20Poly1305::new(Key::from_slice(&key));
    aead.decrypt(Nonce::from_slice(&nonce), Payload { msg: &blob, aad })
        .map_err(|_| ParseError::Crypto("복호화 실패 (패스프레이즈 불일치·손상·봉투 변조)".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    const AAD: &[u8] = b"acct-1|filehash";

    #[test]
    fn roundtrip_and_wrong_passphrase() {
        let msg = "스타벅스 강남점 4,500원".as_bytes();
        let boxed = encrypt(msg, "올바른 암호", AAD).unwrap();
        assert_eq!(decrypt(&boxed, "올바른 암호", AAD).unwrap(), msg);
        assert!(decrypt(&boxed, "틀린 암호", AAD).is_err());
    }

    #[test]
    fn aad_mismatch_fails() {
        let boxed = encrypt(b"data", "pw", AAD).unwrap();
        assert!(decrypt(&boxed, "pw", "다른-봉투".as_bytes()).is_err());
    }

    #[test]
    fn corrupt_envelope_does_not_panic() {
        let mut boxed = encrypt(b"data", "pw", AAD).unwrap();
        // 잘못된 nonce 길이 (8바이트) — panic 대신 Err
        boxed.nonce = B64.encode([0u8; 8]);
        assert!(decrypt(&boxed, "pw", AAD).is_err());
        // 파라미터 범위 밖 — panic/OOM 대신 Err
        let mut b2 = encrypt(b"data", "pw", AAD).unwrap();
        b2.m_kib = u32::MAX;
        assert!(decrypt(&b2, "pw", AAD).is_err());
    }

    #[test]
    fn blob_hides_plaintext_bytes() {
        let msg = "테크컴퍼니".as_bytes();
        let boxed = encrypt(msg, "pw", AAD).unwrap();
        let blob = B64.decode(&boxed.blob).unwrap();
        assert!(!blob.windows(msg.len()).any(|w| w == msg));
    }
}
