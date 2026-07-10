import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { collectDrift } from '../scripts/release-drift.mjs'
import { classifyReleaseRoute, runReleaseDrill } from '../scripts/release-drill.mjs'
import {
  ROOT,
  bundleVersion,
  checkServiceWorkerGuard,
  validatePublicOtaConfig,
} from '../scripts/release-lib.mjs'
import { createReleaseManifest } from '../scripts/release-manifest.mjs'
import { rejectMovingBranch, updateReleaseRecords } from '../scripts/sync-synaplan.mjs'

const read = (path) => readFileSync(join(ROOT, path), 'utf8')

test('bundle versions bind app, Synaplan ref/SHA, and CI build', () => {
  const first = bundleVersion({
    version: '4.0.0',
    sha: 'a'.repeat(40),
    tag: 'v4.0.0',
    build: '100',
  })
  const second = bundleVersion({
    version: '4.0.0',
    sha: 'a'.repeat(40),
    tag: 'v4.0.0',
    build: '101',
  })
  assert.equal(first, '4.0.0-synaplan.4-0-0.aaaaaaaaaaaa.ci.100')
  assert.notEqual(first, second)
})

test('production self-hosted OTA endpoints require HTTPS', () => {
  assert.throws(
    () =>
      validatePublicOtaConfig({
        SYNAPLAN_ENV: 'prod',
        SYNAPLAN_OTA_UPDATE_URL: 'http://updates.example.test',
      }),
    /must use HTTPS/
  )
  assert.deepEqual(
    validatePublicOtaConfig({
      SYNAPLAN_ENV: 'prod',
      SYNAPLAN_OTA_UPDATE_URL: 'https://updates.example.test',
      SYNAPLAN_OTA_CHANNEL_URL: 'https://channels.example.test',
      SYNAPLAN_OTA_STATS_URL: 'https://stats.example.test',
      SYNAPLAN_OTA_PUBLIC_KEY: 'public-key',
      SYNAPLAN_OTA_DEFAULT_CHANNEL: 'stable',
    }),
    {
      updateUrl: 'https://updates.example.test',
      channelUrl: 'https://channels.example.test',
      statsUrl: 'https://stats.example.test',
      publicKey: 'public-key',
      defaultChannel: 'stable',
    }
  )
})

test('release manifest contains deterministic checksums and native compatibility', () => {
  const directory = mkdtempSync(join(tmpdir(), 'synaplan-release-'))
  try {
    writeFileSync(join(directory, 'index.html'), '<h1>Synaplan</h1>\n')
    writeFileSync(join(directory, 'app.js'), 'console.info("bundle")\n')
    writeFileSync(join(directory, 'openapi-contract.sha256'), `${'a'.repeat(64)}\n`)
    const manifest = createReleaseManifest({
      distDir: directory,
      env: {
        SYNAPLAN_BUILD_NUMBER: '77',
        SYNAPLAN_NATIVE_BUILD: '77',
        SYNAPLAN_OTA_DEFAULT_CHANNEL: 'candidate',
      },
      generatedAt: '2026-07-10T08:00:00.000Z',
    })
    assert.equal(manifest.app.version, '4.0.0')
    assert.equal(manifest.app.nativeCompatibility.minVersion, '4.0.0')
    assert.equal(manifest.app.nativeCompatibility.maxVersion, '4.0.0')
    assert.equal(manifest.app.nativeCompatibility.androidVersionCode, 77)
    assert.equal(manifest.channel, 'candidate')
    assert.equal(manifest.apiContractSha256, 'a'.repeat(64))
    assert.deepEqual(
      manifest.files.map((file) => file.path),
      ['app.js', 'index.html', 'openapi-contract.sha256']
    )
    assert.ok(manifest.files.every((file) => /^[0-9a-f]{64}$/.test(file.sha256)))
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})

test('release drill routes backend, conforming OTA, and native changes', () => {
  assert.deepEqual(
    runReleaseDrill().map((scenario) => scenario.result.route),
    ['backend-only', 'ota-candidate', 'store-required']
  )
  assert.equal(
    classifyReleaseRoute(['synaplan/frontend/src/services/purchases.ts'], {
      conforming: true,
    }).route,
    'store-required'
  )
  assert.equal(
    classifyReleaseRoute(['synaplan/frontend/src/components/NewBehavior.vue'], {
      conforming: true,
    }).route,
    'store-required'
  )
})

test('native service-worker registrations require an explicit native guard', () => {
  assert.deepEqual(checkServiceWorkerGuard('navigator.serviceWorker.register("/sw.js")'), {
    registrations: 1,
    guarded: false,
  })
  assert.deepEqual(
    checkServiceWorkerGuard(
      'if (!isNativeApp()) { navigator.serviceWorker.register("/service-worker.js") }'
    ),
    { registrations: 1, guarded: true }
  )
})

test('bootstrap drift check only warns when a build manifest is absent', () => {
  const directory = mkdtempSync(join(tmpdir(), 'synaplan-drift-'))
  try {
    const result = collectDrift({
      bootstrap: true,
      manifestPath: join(directory, 'missing-release-manifest.json'),
    })
    assert.deepEqual(result.errors, [])
    assert.ok(result.warnings.some((warning) => warning.includes('Release manifest')))
    assert.deepEqual(result.serviceWorkers.unguardedFiles, [])
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})

test('sync rejects moving main branches and updates release records deterministically in dry-run', () => {
  for (const ref of ['main', 'master', 'origin/main', 'refs/heads/main', 'HEAD']) {
    assert.throws(() => rejectMovingBranch(ref), /Refusing to pin/)
  }
  const compatibilityBefore = read('docs/COMPATIBILITY.md')
  const identifiersBefore = read('docs/IDENTIFIERS.md')
  const result = updateReleaseRecords({ version: '4.0.0', ref: 'v4.0.0', dryRun: true })
  assert.match(result.compatibility, /`v4\.0\.0`/)
  assert.doesNotMatch(result.compatibility, /_\(development\)_ 4\.0\.0/)
  assert.match(result.compatibility, /Reviewed mobile baseline v4\.0\.0/)
  assert.match(result.identifiers, /Current pin:\*\* `v4\.0\.0`/)
  assert.equal(read('docs/COMPATIBILITY.md'), compatibilityBefore)
  assert.equal(read('docs/IDENTIFIERS.md'), identifiersBefore)
})

test('build source selection is exclusive and shell syntax remains valid', () => {
  const build = read('build.sh')
  assert.match(build, /SYNAPLAN_OPENAPI_FILE/)
  assert.match(build, /Set exactly one of SYNAPLAN_OPENAPI_URL or SYNAPLAN_OPENAPI_FILE/)
  assert.match(build, /SYNAPLAN_OPENAPI_SOURCE/)
  execFileSync('bash', ['-n', join(ROOT, 'build.sh')])
  const conflict = spawnSync('bash', [join(ROOT, 'build.sh'), '--web-only'], {
    cwd: ROOT,
    env: {
      ...process.env,
      SYNAPLAN_OPENAPI_URL: 'https://example.test/openapi.json',
      SYNAPLAN_OPENAPI_FILE: 'openapi.json',
    },
    encoding: 'utf8',
  })
  assert.equal(conflict.status, 2)
  assert.match(conflict.stderr, /Set exactly one/)
  const missing = spawnSync('bash', [join(ROOT, 'build.sh'), '--web-only'], {
    cwd: ROOT,
    env: {
      ...process.env,
      SYNAPLAN_OPENAPI_URL: '',
      SYNAPLAN_OPENAPI_FILE: '',
    },
    encoding: 'utf8',
  })
  assert.equal(missing.status, 2)
  assert.match(missing.stderr, /Set exactly one/)
  assert.match(build, /openapi-contract\.sha256/)
})

test('Capacitor config exposes only public self-hosted OTA settings', () => {
  const config = read('capacitor.config.ts')
  for (const variable of [
    'SYNAPLAN_OTA_UPDATE_URL',
    'SYNAPLAN_OTA_CHANNEL_URL',
    'SYNAPLAN_OTA_STATS_URL',
    'SYNAPLAN_OTA_PUBLIC_KEY',
    'SYNAPLAN_OTA_DEFAULT_CHANNEL',
  ]) {
    assert.match(config, new RegExp(variable))
  }
  assert.match(config, /must use HTTPS for production builds/)
  assert.doesNotMatch(config, /CAPGO_TOKEN|PRIVATE_KEY|API_SECRET/)
  for (const safetySetting of ['autoUpdate', 'resetWhenUpdate', 'appReadyTimeout']) {
    assert.match(config, new RegExp(`${safetySetting}:`))
  }
})
