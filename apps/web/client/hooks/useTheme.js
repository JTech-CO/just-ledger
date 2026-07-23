// 테마 정책 (디자인 백서 §2.1): Light 기본 + prefers-color-scheme 자동 +
// 수동 토글(localStorage 저장). 명시 선택이 자동 감지를 이긴다 — tokens.css 의
// :root[data-theme] 규칙과 짝을 이룬다.

import { useCallback, useEffect, useState } from 'react';

const KEY = 'jl-theme';

/** 저장된 명시 테마 or 시스템 선호 → 유효 테마 */
function resolve(stored) {
  if (stored === 'light' || stored === 'dark') return stored;
  if (typeof window !== 'undefined' && window.matchMedia) {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return 'light';
}

export function useTheme() {
  const [stored, setStored] = useState(() => {
    try {
      return localStorage.getItem(KEY);
    } catch {
      return null;
    }
  });
  const [theme, setTheme] = useState(() => resolve(stored));

  // 명시 선택이 없으면 시스템 변경을 따라간다
  useEffect(() => {
    if (stored === 'light' || stored === 'dark') return undefined;
    const mq = window.matchMedia?.('(prefers-color-scheme: dark)');
    if (!mq) return undefined;
    const onChange = () => setTheme(resolve(null));
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, [stored]);

  // 유효 테마를 root 에 스탬프 (tokens.css 가 data-theme 로 오버라이드)
  useEffect(() => {
    const root = document.documentElement;
    if (stored === 'light' || stored === 'dark') {
      root.setAttribute('data-theme', stored);
    } else {
      root.removeAttribute('data-theme');
    }
  }, [stored]);

  const toggle = useCallback(() => {
    setTheme((cur) => {
      const next = cur === 'dark' ? 'light' : 'dark';
      try {
        localStorage.setItem(KEY, next);
      } catch {
        /* localStorage 불가(프라이빗 모드 등) — 세션 내에서만 적용 */
      }
      setStored(next);
      return next;
    });
  }, []);

  return { theme, toggle };
}
