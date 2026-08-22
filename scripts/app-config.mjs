#!/usr/bin/env node
/*
 * app-config.mjs — Epic 10.1: multi-environment + versioning (single source).
 *
 * Resolves the build identity and stamps it into the iOS native project so dev /
 * staging / prod builds carry distinct bundle IDs, a visible app-name suffix, and
 * the correct version numbers. The human version is owned by THIS repo's
 * package.json (the same value that drives the UA token in capacitor.config.ts and
 * the iOS MARKETING_VERSION); the monotonic build number comes from CI
 * (SYNAPLAN_BUILD_NUMBER) and falls back to the git commit count locally.
 * Identifiers are locked in docs/IDENTIFIERS.md.
 *
 * Android is configured Gradle-natively (android/app/build.gradle reads the same
 * package.json + the SYNAPLAN_ENV / SYNAPLAN_BUILD_NUMBER inputs), so this script
 * only needs to patch the iOS project, where there is no equivalent build hook.
 *
 * Inputs (env vars, all optional):
 *   SYNAPLAN_ENV           dev | staging | prod   (default: prod)
 *   SYNAPLAN_BUILD_NUMBER  monotonic integer      (default: git commit count, else 1)
 *
 * Usage:
 *   node scripts/app-config.mjs          # patch iOS + print resolved config
 *   node scripts/app-config.mjs --print  # print resolved config only (no writes)
 *
 * Idempotent: re-running with the same inputs is a no-op.
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execSync } from 'node:child_process'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')

const BASE_BUNDLE_ID = 'com.synaplan.app'
const BASE_APP_NAME = 'Synaplan'

// env → (bundle-id suffix, app-name suffix). Frozen in docs/IDENTIFIERS.md.
const ENV_MATRIX = {
  prod: { idSuffix: '', nameSuffix: '' },
  staging: { idSuffix: '.staging', nameSuffix: ' Staging' },
  dev: { idSuffix: '.dev', nameSuffix: ' Dev' },
}

function resolveBuildNumber() {
  const fromEnv = (process.env.SYNAPLAN_BUILD_NUMBER || '').trim()
  if (/^\d+$/.test(fromEnv) && Number(fromEnv) > 0) {
    return Number(fromEnv)
  }
  try {
    const count = execSync('git rev-list --count HEAD', {
      cwd: ROOT,
      stdio: ['ignore', 'pipe', 'ignore'],
    })
      .toString()
      .trim()
    if (/^\d+$/.test(count) && Number(count) > 0) {
      return Number(count)
    }
  } catch {
    /* not a git checkout / git unavailable — fall through */
  }
  return 1
}

/** Resolve the full build identity from env + package.json. Throws on bad env. */
export function resolveAppConfig() {
  const env = (process.env.SYNAPLAN_ENV || 'prod').trim().toLowerCase()
  const matrix = ENV_MATRIX[env]
  if (!matrix) {
    throw new Error(`Unknown SYNAPLAN_ENV "${env}" — use dev | staging | prod`)
  }
  const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf-8'))
  return {
    env,
    version: String(pkg.version),
    buildNumber: resolveBuildNumber(),
    bundleId: BASE_BUNDLE_ID + matrix.idSuffix,
    appName: BASE_APP_NAME + matrix.nameSuffix,
  }
}

/** Stamp version + bundle id + display name into the iOS native project. */
function patchIos(cfg) {
  const pbxPath = join(ROOT, 'ios/App/App.xcodeproj/project.pbxproj')
  let pbx = readFileSync(pbxPath, 'utf-8')
  pbx = pbx.replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${cfg.version};`)
  pbx = pbx.replace(
    /CURRENT_PROJECT_VERSION = [^;]+;/g,
    `CURRENT_PROJECT_VERSION = ${cfg.buildNumber};`
  )
  pbx = pbx.replace(
    /PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/g,
    `PRODUCT_BUNDLE_IDENTIFIER = ${cfg.bundleId};`
  )
  writeFileSync(pbxPath, pbx)

  const plistPath = join(ROOT, 'ios/App/App/Info.plist')
  let plist = readFileSync(plistPath, 'utf-8')
  plist = plist.replace(
    /(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*(<\/string>)/,
    `$1${cfg.appName}$2`
  )
  writeFileSync(plistPath, plist)
}

// CLI entry — run directly (not when imported).
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const cfg = resolveAppConfig()
  const printOnly = process.argv.includes('--print')
  if (!printOnly) {
    patchIos(cfg)
  }
  console.log(
    `[app-config] env=${cfg.env} version=${cfg.version} build=${cfg.buildNumber} ` +
      `bundleId=${cfg.bundleId} name="${cfg.appName}"${printOnly ? ' (print-only)' : ' → iOS patched'}`
  )
}
