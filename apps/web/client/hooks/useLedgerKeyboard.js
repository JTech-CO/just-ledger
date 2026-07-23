// 원장 키보드 조작 (디자인 백서 §2.2). 마우스 없이 원장 전체를 조작한다(DoD 3).
//   j/k  행 이동   Enter  상세(Inspector) 열기   e  인라인 편집
//   /    검색 포커스   Esc  상세·검색 닫기
//
// 입력 필드(input/textarea/select·contenteditable)에 포커스가 있을 때는 단축키를
// 가로채지 않는다 — 검색어에 'j' 를 못 치면 안 된다. 편집 컨트롤이 DOM 에 없는
// (settled) 행에서 'e' 는 아무 일도 하지 않는다.

import { useEffect } from 'react';

const isTypingTarget = (el) => {
  if (!el) return false;
  const tag = el.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable;
};

/**
 * @param {object} opts
 * @param {number} opts.count  행 수
 * @param {number} opts.activeIndex
 * @param {(next:number)=>void} opts.setActiveIndex
 * @param {()=>void} opts.onEnter  상세 열기
 * @param {()=>void} opts.onEdit  현재 행 편집(편집 불가면 no-op)
 * @param {()=>void} opts.onSearch  검색 포커스
 * @param {()=>void} opts.onEscape  닫기
 * @param {boolean} [opts.enabled=true]
 */
export function useLedgerKeyboard({
  count,
  activeIndex,
  setActiveIndex,
  onEnter,
  onEdit,
  onSearch,
  onEscape,
  enabled = true,
}) {
  useEffect(() => {
    if (!enabled) return undefined;

    function onKeyDown(e) {
      // Esc 는 입력 중에도 동작(검색·상세 닫기). 나머지는 입력 필드에서 무시.
      if (e.key === 'Escape') {
        onEscape?.();
        return;
      }
      if (isTypingTarget(e.target)) return;
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      switch (e.key) {
        case 'j':
        case 'ArrowDown':
          e.preventDefault();
          setActiveIndex(Math.min((activeIndex < 0 ? -1 : activeIndex) + 1, count - 1));
          break;
        case 'k':
        case 'ArrowUp':
          e.preventDefault();
          setActiveIndex(Math.max((activeIndex < 0 ? count : activeIndex) - 1, 0));
          break;
        case 'Enter':
          if (activeIndex >= 0) {
            e.preventDefault();
            onEnter?.();
          }
          break;
        case 'e':
          if (activeIndex >= 0) {
            e.preventDefault();
            onEdit?.();
          }
          break;
        case '/':
          e.preventDefault();
          onSearch?.();
          break;
        default:
          break;
      }
    }

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [enabled, count, activeIndex, setActiveIndex, onEnter, onEdit, onSearch, onEscape]);
}
