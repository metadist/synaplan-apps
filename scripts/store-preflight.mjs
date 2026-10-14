#!/usr/bin/env node
/**
 * Refuse a store build whose marketing version Apple will reject.
 *
 * A version train closes when that version is approved. The TestFlight upload
 * is the last step of store-rc.yml, so discovering it there spends the whole
 * signed build. This script only reads App Store Connect. It never creates a
 * version and never counts one up — that stays `npm run release:version`.
 *
 * Credentials (from the store-qa environment, never logged):
 *   APP_STORE_CONNECT_KEY_ID
 *   APP_STORE_CONNECT_ISSUER_ID
 *   APP_STORE_CONNECT_PRIVATE_KEY   PKCS#8 PEM (.p8)
 */
import { createSign, createPrivateKey, createVerify } from 'node:crypto'
import { appendFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { resolveAppConfig } from './app-config.mjs'
import { appVersion, compareVersions } from './release-lib.mjs'

const ASC_ORIGIN = 'https://api.appstoreconnect.apple.com'
const TOKEN_LIFETIME_SECONDS = 19 * 60

/**
 * States in which Apple still accepts a new build of that version. Anything
 * else, including a state this list does not know yet, counts as closed:
 * uploading and then learning the train was shut is the failure this exists
 * to avoid. The message names the state so an unfamiliar one can be classified.
 */
export const OPEN_APP_STORE_STATES = [
  'PREPARE_FOR_SUBMISSION',
  'WAITING_FOR_REVIEW',
  'IN_REVIEW',
  'REJECTED',
  'METADATA_REJECTED',
  'DEVELOPER_REJECTED',
  'INVALID_BINARY',
]

/**
 * The highest version whose train is closed, or null when every listed version
 * is still open. An unreadable version string fails the check: a closed train
 * that cannot be compared must not be treated as absent.
 */
export function closedTrainVersion(versions) {
  let highest = null
  for (const entry of versions ?? []) {
    const state = String(entry?.state ?? '').trim()
    if (OPEN_APP_STORE_STATES.includes(state)) continue
    const version = String(entry?.versionString ?? '').trim()
    if (compareVersions(version, version) !== 0) {
      throw new Error(
        `App Store version "${version || '(empty)'}" in state ${state || 'unknown'} is not plain semver`
      )
    }
    if (!highest || compareVersions(version, highest.version) > 0) {
      highest = { version, state: state || 'unknown' }
    }
  }
  return highest
}

/** A message when `current` cannot be uploaded, or null when it can. */
export function preflightProblem({ current, closed }) {
  if (!closed) return null
  const order = compareVersions(current, closed.version)
  if (order === null) {
    return `App version ${current} is not plain semver (major.minor.patch)`
  }
  if (order > 0) return null
  const state = closed.state || 'unknown state'
  return (
    `App ${current} is not above ${closed.version} (${state}). That version's App Store train is closed. ` +
    'Run `npm run release:version`, merge the pull request, then start Mobile Store RC again.'
  )
}

/** A PEM private key, including one whose newlines were escaped into a single line. */
export function normalizePrivateKey(value) {
  const trimmed = String(value ?? '')
    .replace(/\r/g, '')
    .trim()
  if (!trimmed || trimmed.includes('\n')) return trimmed
  return trimmed.replace(/\\n/g, '\n')
}

/**
 * App Store Connect bearer token. Lifetime stays under Apple's 20 minute cap
 * so a minute of clock skew still fits. The signature is raw R||S (64 bytes
 * for P-256); the DER form Apple rejects is the Node default.
 */
export function appStoreConnectToken({ keyId, issuerId, privateKey, now = Date.now() }) {
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' }
  const issuedAt = Math.floor(now / 1000)
  const payload = {
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + TOKEN_LIFETIME_SECONDS,
    aud: 'appstoreconnect-v1',
  }
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url')
  const signingInput = `${encode(header)}.${encode(payload)}`
  let key
  try {
    key = createPrivateKey(privateKey)
  } catch {
    throw new Error('APP_STORE_CONNECT_PRIVATE_KEY is not a usable private key')
  }
  const signature = createSign('SHA256')
    .update(signingInput)
    .sign({ key, dsaEncoding: 'ieee-p1363' })
  return `${signingInput}.${signature.toString('base64url')}`
}

/** True when `token` was signed by `publicKey`. Tests use this; the CLI does not. */
export function verifyAppStoreConnectToken(token, publicKey) {
  const [header, payload, signature] = String(token).split('.')
  if (!header || !payload || !signature) return false
  const raw = Buffer.from(signature, 'base64url')
  return createVerify('SHA256')
    .update(`${header}.${payload}`)
    .verify({ key: publicKey, dsaEncoding: 'ieee-p1363' }, raw)
}

function requiredEnv(name) {
  const value = String(process.env[name] ?? '').trim()
  if (!value) throw new Error(`${name} is empty`)
  return value
}

function assertAscUrl(value) {
  const url = new URL(value)
  if (url.origin !== ASC_ORIGIN) {
    throw new Error('App Store Connect returned a link outside its API')
  }
  return url
}

async function readAsc(url, token) {
  let response
  try {
    response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
  } catch {
    throw new Error('App Store Connect could not be reached')
  }
  if (!response.ok) {
    throw new Error(`App Store Connect answered HTTP ${response.status}`)
  }
  return response.json()
}

function versionEntries(payload) {
  return (payload?.data ?? []).map((item) => ({
    versionString: item?.attributes?.versionString,
    state: item?.attributes?.appVersionState || item?.attributes?.appStoreState || '',
  }))
}

async function listAppStoreVersions(bundleId, token) {
  const apps = await readAsc(
    `${ASC_ORIGIN}/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=2`,
    token
  )
  const found = apps.data?.length ?? 0
  if (found !== 1) {
    throw new Error(
      `Expected one App Store Connect app for the production bundle id, found ${found}`
    )
  }
  const appId = String(apps.data[0]?.id ?? '')
  if (!/^[0-9]+$/.test(appId)) {
    throw new Error('App Store Connect returned an app without a numeric id')
  }
  const versions = []
  let url = `${ASC_ORIGIN}/v1/apps/${appId}/appStoreVersions?filter[platform]=IOS&limit=200`
  for (let page = 0; page < 10 && url; page += 1) {
    const payload = await readAsc(url, token)
    versions.push(...versionEntries(payload))
    const next = payload.links?.next
    if (!next) break
    url = assertAscUrl(next).toString()
  }
  return versions
}

function summarize(message) {
  const path = process.env.GITHUB_STEP_SUMMARY
  if (path) appendFileSync(path, `${message}\n`)
}

function report(level, message) {
  console.error(`::${level}::${message}`)
  summarize(message)
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const warnOnly = process.argv.includes('--warn-only')
  const versionFlag = process.argv.indexOf('--version')
  const current = versionFlag >= 0 ? process.argv[versionFlag + 1] : appVersion()
  try {
    if (!current) throw new Error('App version is empty')
    const token = appStoreConnectToken({
      keyId: requiredEnv('APP_STORE_CONNECT_KEY_ID'),
      issuerId: requiredEnv('APP_STORE_CONNECT_ISSUER_ID'),
      privateKey: normalizePrivateKey(requiredEnv('APP_STORE_CONNECT_PRIVATE_KEY')),
    })
    const versions = await listAppStoreVersions(resolveAppConfig().bundleId, token)
    const closed = closedTrainVersion(versions)
    const problem = preflightProblem({ current, closed })
    if (problem) {
      report(warnOnly ? 'warning' : 'error', problem)
      if (!warnOnly) process.exitCode = 1
    } else {
      const message = closed
        ? `App ${current} is above the closed train ${closed.version} (${closed.state}).`
        : `App ${current} is not blocked by a closed App Store train.`
      console.log(`[store-preflight] ${message}`)
      summarize(message)
    }
  } catch (error) {
    report('error', error instanceof Error ? error.message : 'App Store Connect preflight failed')
    process.exitCode = 1
  }
}
