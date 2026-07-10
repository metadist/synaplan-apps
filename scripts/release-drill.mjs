#!/usr/bin/env node
import { fileURLToPath } from 'node:url'

const NATIVE_OR_RELEASE_PATH =
  /^(?:android|ios|capacitor\.config\.ts|package(?:-lock)?\.json|scripts\/app-config\.mjs)/
const OTA_FORBIDDEN_PATH =
  /(?:purchase|payment|billing|entitlement|subscription|iap|native|capacitor|package(?:-lock)?\.json)/i
const BACKEND_MOBILE_RISK =
  /(?:\/Controller\/|\/Service\/Client\/|auth|mobile|openapi|payment|purchase|subscription|stripe)/i
const OTA_ALLOWLIST =
  /^(?:synaplan\/frontend\/src\/(?:.*\.css|i18n\/[^/]+\.json|assets\/|components\/icons\/)|synaplan\/frontend\/public\/.*\.(?:svg|png|jpe?g|webp)$)/

export function classifyReleaseRoute(changes, { conforming = false } = {}) {
  const paths = [...new Set(changes.map((path) => String(path).replaceAll('\\', '/')))].sort()
  if (paths.length === 0) throw new Error('At least one changed path is required')

  if (
    paths.every((path) => path.startsWith('synaplan/backend/') && !BACKEND_MOBILE_RISK.test(path))
  ) {
    return {
      route: 'backend-only',
      reason: 'Only backend files changed; no app or bundled web assets need publication.',
      paths,
    }
  }

  const otaAllowlisted = paths.every((path) => OTA_ALLOWLIST.test(path))
  const forbidden = paths.find((path) => OTA_FORBIDDEN_PATH.test(path))
  if (otaAllowlisted && conforming && !forbidden) {
    return {
      route: 'ota-candidate',
      reason: 'Only explicitly conforming web assets changed; prepare a signed staged OTA.',
      paths,
    }
  }

  const native = paths.find((path) => NATIVE_OR_RELEASE_PATH.test(path))
  return {
    route: 'store-required',
    reason: forbidden
      ? `OTA policy blocks sensitive path: ${forbidden}`
      : native
        ? `Native/release configuration changed: ${native}`
        : conforming
          ? 'The change set is not limited to bundled frontend assets.'
          : 'Web changes were not explicitly approved as OTA-conforming.',
    paths,
  }
}

export function runReleaseDrill() {
  const scenarios = [
    {
      name: 'backend-only',
      changes: ['synaplan/backend/src/Service/ReportExportService.php'],
      options: {},
      expected: 'backend-only',
    },
    {
      name: 'ota-candidate',
      changes: ['synaplan/frontend/src/i18n/en.json', 'synaplan/frontend/src/style.css'],
      options: { conforming: true },
      expected: 'ota-candidate',
    },
    {
      name: 'store-required',
      changes: ['ios/App/App/Info.plist', 'synaplan/frontend/src/services/purchases.ts'],
      options: { conforming: true },
      expected: 'store-required',
    },
  ]
  return scenarios.map((scenario) => {
    const result = classifyReleaseRoute(scenario.changes, scenario.options)
    if (result.route !== scenario.expected) {
      throw new Error(`${scenario.name}: expected ${scenario.expected}, got ${result.route}`)
    }
    return { ...scenario, result }
  })
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    const args = process.argv.slice(2)
    const separator = args.indexOf('--')
    if (separator >= 0) {
      const result = classifyReleaseRoute(args.slice(separator + 1), {
        conforming: args.includes('--conforming'),
      })
      console.log(JSON.stringify(result, null, 2))
    } else {
      for (const scenario of runReleaseDrill()) {
        console.log(`[release-drill] ${scenario.name} -> ${scenario.result.route}`)
      }
      console.log('[release-drill] no external publication was attempted')
    }
  } catch (error) {
    console.error(`[release-drill] ${error.message}`)
    process.exitCode = 1
  }
}
