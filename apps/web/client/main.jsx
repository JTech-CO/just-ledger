import { Component } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import './styles/tokens.css';
import './styles/global.css';

// 전역 오류 경계 — 렌더 예외가 백지 화면이 되지 않게 한다 (원장 앱에서 백지는
// 데이터 유실로 오인된다). 세분화된 경계는 M8.
class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }
  static getDerivedStateFromError(error) {
    return { error };
  }
  render() {
    if (this.state.error) {
      return (
        <main style={{ padding: 'var(--sp-5)' }}>
          <p role="alert" className="negative">
            화면 렌더 중 오류가 발생했습니다: {String(this.state.error?.message ?? this.state.error)}
          </p>
          <p className="muted">데이터는 안전합니다. 새로고침 후에도 반복되면 보고해 주세요.</p>
        </main>
      );
    }
    return this.props.children;
  }
}

createRoot(document.getElementById('root')).render(
  <ErrorBoundary>
    <App />
  </ErrorBoundary>,
);
