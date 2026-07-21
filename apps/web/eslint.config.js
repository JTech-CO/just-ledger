import js from '@eslint/js';
import globals from 'globals';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  { ignores: ['dist/**', 'types/*.gen.js', 'node_modules/**'] },
  js.configs.recommended,
  {
    files: ['**/*.{js,mjs,jsx}'],
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'module',
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...globals.node, ...globals.browser },
    },
    plugins: { react, 'react-hooks': reactHooks },
    settings: { react: { version: 'detect' } },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react/jsx-uses-vars': 'error',   // JSX 사용을 no-unused-vars 에 인지시킨다
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      // INV-4 1차 방어선 (정본 검사는 scripts/check-no-float.mjs)
      'no-restricted-globals': ['error',
        { name: 'parseFloat', message: '금액 경로 금지 (INV-4). 문자열/BigInt 만.' }],
      'no-restricted-properties': ['error',
        { object: 'Number', property: 'parseFloat', message: 'INV-4' },
        { object: 'Math', property: 'round', message: '금액이라면 INV-4 위반. 반올림 정본은 COBOL.' }],
    },
  },
];
