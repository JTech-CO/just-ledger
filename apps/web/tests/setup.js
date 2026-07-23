// 테스트 setup — happy-dom 은 레이아웃을 계산하지 않아 요소 크기가 0 이다.
// @tanstack/react-virtual 은 스크롤 컨테이너 크기로 렌더 범위를 정하므로,
// 뷰포트 크기와 ResizeObserver 를 stub 해 가상화가 예측 가능하게 동작하게 한다.
// (node 환경 테스트에는 HTMLElement 가 없으므로 존재할 때만 적용한다.)

if (typeof globalThis.ResizeObserver === 'undefined') {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
}

if (typeof HTMLElement !== 'undefined') {
  const define = (prop, value) => {
    Object.defineProperty(HTMLElement.prototype, prop, {
      configurable: true,
      get() {
        return value;
      },
    });
  };
  // 스크롤 컨테이너: 600px 뷰포트 → 34px 행 약 18개 + overscan 12 렌더
  define('clientHeight', 600);
  define('clientWidth', 800);

  if (!HTMLElement.prototype.getBoundingClientRect.__stubbed) {
    const rect = () => ({ width: 800, height: 600, top: 0, left: 0, right: 800, bottom: 600, x: 0, y: 0, toJSON() {} });
    rect.__stubbed = true;
    HTMLElement.prototype.getBoundingClientRect = rect;
  }
}
