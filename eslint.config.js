// Flat ESLint config for the app-owned code in synaplan-apps (Epic 12.2, gate 1).
// Scope: capacitor.config.ts, scripts/, tests/, and the vanilla bootstrap. The
// synaplan/ submodule has its own ESLint and is ignored here.
import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import globals from 'globals'
import prettier from 'eslint-config-prettier'

export default tseslint.config(
  {
    // `build/` + `build-*/` are local xcodebuild output (archives contain a copy
    // of the bundled SPA); linting them would drown the gate in generated code.
    ignores: [
      'ios/**',
      'android/**',
      'synaplan/**',
      'node_modules/**',
      '**/dist/**',
      'build/**',
      'build-*/**',
    ],
  },
  js.configs.recommended,
  // TypeScript (light, non type-aware — tsc handles the typecheck in `npm run typecheck`).
  {
    files: ['**/*.ts'],
    extends: [tseslint.configs.recommended],
    languageOptions: {
      globals: { ...globals.node },
    },
  },
  // ESM Node scripts + tests.
  {
    files: ['**/*.mjs'],
    languageOptions: {
      sourceType: 'module',
      globals: { ...globals.node },
    },
  },
  // Vanilla ES5 browser bootstrap (app/synaplan-native.js) — relaxed on purpose:
  // it runs before the SPA module, so `var`/IIFE and best-effort empty catches are
  // intentional, not mistakes.
  {
    files: ['app/**/*.js'],
    languageOptions: {
      // ES5 syntax (var/IIFE, no arrow funcs) but the WebView provides modern runtime
      // builtins (Promise, fetch, AbortController, URL), so include those globals too.
      ecmaVersion: 5,
      sourceType: 'script',
      globals: { ...globals.browser, ...globals.es2017 },
    },
    rules: {
      'no-var': 'off',
      'no-empty': ['error', { allowEmptyCatch: true }],
      'no-unused-vars': ['warn', { args: 'none', caughtErrors: 'none' }],
    },
  },
  prettier
)
