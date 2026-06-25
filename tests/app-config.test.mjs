/*
 * Parse/config gate (Epic 12.3/12.4) for the Epic 10.1 build-identity resolver.
 * Uses Node's built-in test runner (`node --test`) — zero extra dependencies.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

import { resolveAppConfig } from '../scripts/app-config.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const pkgVersion = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf-8')).version

/** Run `resolveAppConfig()` with a controlled environment, then restore it. */
function withEnv(env, fn) {
  const saved = { SYNAPLAN_ENV: process.env.SYNAPLAN_ENV, SYNAPLAN_BUILD_NUMBER: process.env.SYNAPLAN_BUILD_NUMBER }
  try {
    delete process.env.SYNAPLAN_ENV
    delete process.env.SYNAPLAN_BUILD_NUMBER
    for (const [k, v] of Object.entries(env)) process.env[k] = v
    return fn()
  } finally {
    for (const k of ['SYNAPLAN_ENV', 'SYNAPLAN_BUILD_NUMBER']) {
      if (saved[k] === undefined) delete process.env[k]
      else process.env[k] = saved[k]
    }
  }
}

test('prod is the default environment (no suffix, plain name)', () => {
  const cfg = withEnv({ SYNAPLAN_BUILD_NUMBER: '7' }, resolveAppConfig)
  assert.equal(cfg.env, 'prod')
  assert.equal(cfg.bundleId, 'com.synaplan.app')
  assert.equal(cfg.appName, 'Synaplan')
})

test('dev gets the .dev id suffix and "Dev" name suffix', () => {
  const cfg = withEnv({ SYNAPLAN_ENV: 'dev', SYNAPLAN_BUILD_NUMBER: '7' }, resolveAppConfig)
  assert.equal(cfg.bundleId, 'com.synaplan.app.dev')
  assert.equal(cfg.appName, 'Synaplan Dev')
})

test('staging gets the .staging id suffix and "Staging" name suffix', () => {
  const cfg = withEnv({ SYNAPLAN_ENV: 'staging', SYNAPLAN_BUILD_NUMBER: '7' }, resolveAppConfig)
  assert.equal(cfg.bundleId, 'com.synaplan.app.staging')
  assert.equal(cfg.appName, 'Synaplan Staging')
})

test('env is case-insensitive', () => {
  const cfg = withEnv({ SYNAPLAN_ENV: 'DEV', SYNAPLAN_BUILD_NUMBER: '7' }, resolveAppConfig)
  assert.equal(cfg.env, 'dev')
  assert.equal(cfg.bundleId, 'com.synaplan.app.dev')
})

test('unknown environment is rejected', () => {
  assert.throws(() => withEnv({ SYNAPLAN_ENV: 'qa' }, resolveAppConfig), /Unknown SYNAPLAN_ENV/)
})

test('version is the single source of truth from package.json', () => {
  const cfg = withEnv({ SYNAPLAN_BUILD_NUMBER: '7' }, resolveAppConfig)
  assert.equal(cfg.version, pkgVersion)
})

test('SYNAPLAN_BUILD_NUMBER drives the build number when set', () => {
  const cfg = withEnv({ SYNAPLAN_BUILD_NUMBER: '4242' }, resolveAppConfig)
  assert.equal(cfg.buildNumber, 4242)
})

test('build number falls back to a positive integer (git count / 1)', () => {
  const cfg = withEnv({}, resolveAppConfig)
  assert.ok(Number.isInteger(cfg.buildNumber) && cfg.buildNumber > 0, `got ${cfg.buildNumber}`)
})

test('a non-numeric build number is ignored in favor of the fallback', () => {
  const cfg = withEnv({ SYNAPLAN_BUILD_NUMBER: 'not-a-number' }, resolveAppConfig)
  assert.ok(Number.isInteger(cfg.buildNumber) && cfg.buildNumber > 0)
})
