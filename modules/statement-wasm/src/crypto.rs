//! 페이로드 암호화 (백서 §7): 키는 사용자 패스프레이즈에서 Argon2id 로 파생하며
//! 서버에 저장하지 않는다 — 서버는 blob 을 복호화할 수 없다 (INV-6).
//!
//! 구성: Argon2id(passphrase, salt₁₆) → 32B 키 → ChaCha20-Poly1305(nonce₁₂).
//! 백서 §3.2 는 라이브러리로 age 를 들지만, age 의 패스프레이즈 모드는 내부 KDF 가
//! scrypt 라 같은 문서의 Argon2id 요구와 충돌한다. Argon2id + ChaCha20-Poly1305
//! (age 와 동일 계열 AEAD) 직접 구성으로 Argon2id 요구를 우선했다. (결정 로그 2026-07-21)

use crate::error::ParseError;
use argon2::{Algorithm, Argon2, Params, Version};
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use serde::{Deserialize, Serialize};

/// Argon2id 파라미터 (OWASP 권장 최소선; 브라우저 WASM 에서 ~수백 ms)
pub const M_KIB: u32 = 19_456;
pub const T_COST: u32 = 2;
pub const P_COST: u32 = 1;

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

pub fn encrypt(plaintext: &[u8], passphrase: &str) -> Result<CipherBox, ParseError> {
    let mut salt = [0u8; 16];
    let mut nonce = [0u8; 12];
    getrandom::getrandom(&mut salt).map_err(|e| ParseError::Crypto(format!("CSPRNG: {e}")))?;
    getrandom::getrandom(&mut nonce).map_err(|e| ParseError::Crypto(format!("CSPRNG: {e}")))?;

    let key = derive_key(passphrase, &salt, M_KIB, T_COST, P_COST)?;
    let aead = ChaCha20Poly1305::new(Key::from_slice(&key));
    let ct = aead
        .encrypt(Nonce::from_slice(&nonce), plaintext)
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

pub fn decrypt(cipher: &CipherBox, passphrase: &str) -> Result<Vec<u8>, ParseError> {
    if cipher.alg != "argon2id-chacha20poly1305" {
        return Err(ParseError::Crypto(format!(
            "알 수 없는 알고리즘: {}",
            cipher.alg
        )));
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

    let key = derive_key(passphrase, &salt, cipher.m_kib, cipher.t, cipher.p)?;
    let aead = ChaCha20Poly1305::new(Key::from_slice(&key));
    aead.decrypt(Nonce::from_slice(&nonce), blob.as_ref())
        .map_err(|_| ParseError::Crypto("복호화 실패 (패스프레이즈 불일치 또는 손상)".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_and_wrong_passphrase() {
        let msg = "스타벅스 강남점 4,500원".as_bytes();
        let boxed = encrypt(msg, "올바른 암호").unwrap();
        assert_eq!(decrypt(&boxed, "올바른 암호").unwrap(), msg);
        assert!(decrypt(&boxed, "틀린 암호").is_err());
    }

    #[test]
    fn blob_hides_plaintext_bytes() {
        let msg = "테크컴퍼니".as_bytes();
        let boxed = encrypt(msg, "pw").unwrap();
        let blob = B64.decode(&boxed.blob).unwrap();
        // 평문 바이트 열이 암호문에 그대로 나타나지 않는다 (INV-6 바이트 검사의 축소판)
        assert!(!blob.windows(msg.len()).any(|w| w == msg));
    }
}
