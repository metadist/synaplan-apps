#!/usr/bin/env node
import { fileURLToPath } from 'node:url'

export const APP_ID = 'com.synaplan.app'

const INSTALL_FIELDS = ['install', 'installs', 'success', 'succeeded']
const FAILURE_FIELDS = ['fail', 'fails', 'failed', 'failures']

const sumField = (entry, fields) => {
  for (const field of fields) {
    const value = entry?.[field]
    if (typeof value === 'number' && Number.isFinite(value)) return value
  }
  return 0
}

// The self-hosted statistics endpoint may answer with a single object or with a
// row per day. Both are reduced to one pair of counters.
export function extractCounts(payload) {
  const rows = Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.data)
      ? payload.data
      : [payload]
  return rows.reduce(
    (totals, row) => ({
      installs: totals.installs + sumField(row, INSTALL_FIELDS),
      failures: totals.failures + sumField(row, FAILURE_FIELDS),
    }),
    { installs: 0, failures: 0 }
  )
}

export function evaluateOtaHealth({ installs, failures, minInstalls = 25, maxFailureRate = 0.05 }) {
  const attempts = installs + failures
  const failureRate = attempts === 0 ? 0 : failures / attempts
  if (attempts < minInstalls) {
    return {
      status: 'inconclusive',
      failureRate,
      reason: `Only ${attempts} of ${minInstalls} update attempts observed so far.`,
    }
  }
  if (failureRate > maxFailureRate) {
    return {
      status: 'unhealthy',
      failureRate,
      reason: `${failures} of ${attempts} update attempts failed (${(failureRate * 100).toFixed(1)}%).`,
    }
  }
  return {
    status: 'healthy',
    failureRate,
    reason: `${failures} of ${attempts} update attempts failed, within the accepted rate.`,
  }
}

export function statisticsUrl(base, bundle, appId = APP_ID) {
  if (base.includes('{bundle}')) {
    return base.replaceAll('{bundle}', encodeURIComponent(bundle)).replaceAll('{appId}', appId)
  }
  const url = new URL(base)
  url.searchParams.set('app_id', appId)
  url.searchParams.set('version', bundle)
  return url.toString()
}

async function fetchCounts({ base, bundle, apiKey }) {
  const response = await fetch(statisticsUrl(base, bundle), {
    headers: { authorization: apiKey, accept: 'application/json' },
  })
  if (!response.ok) {
    throw new Error(`Statistics endpoint answered ${response.status}`)
  }
  return extractCounts(await response.json())
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const args = process.argv.slice(2)
  const value = (name, fallback) => {
    const index = args.indexOf(`--${name}`)
    return index >= 0 ? args[index + 1] : fallback
  }
  const base = process.env.CAPGO_STATS_API_URL
  const apiKey = process.env.CAPGO_API_KEY
  const bundle = value('bundle')
  const deadlineMinutes = Number(value('deadline-minutes', '20'))
  const intervalSeconds = Number(value('interval-seconds', '120'))
  const options = {
    minInstalls: Number(value('min-installs', '25')),
    maxFailureRate: Number(value('max-failure-rate', '0.05')),
  }

  // Fail loudly instead of reporting a green health check nobody measured.
  if (!base || !apiKey || !bundle) {
    console.error(
      '[ota-health] CAPGO_STATS_API_URL, CAPGO_API_KEY and --bundle are required to observe a release'
    )
    process.exit(1)
  }

  const deadline = Date.now() + deadlineMinutes * 60_000
  let result = { status: 'inconclusive', failureRate: 0, reason: 'No observation completed.' }
  let counts = { installs: 0, failures: 0 }

  while (Date.now() < deadline) {
    try {
      counts = await fetchCounts({ base, bundle, apiKey })
      result = evaluateOtaHealth({ ...counts, ...options })
      if (result.status !== 'inconclusive') break
    } catch (error) {
      result = { status: 'unknown', failureRate: 0, reason: error.message }
    }
    await sleep(intervalSeconds * 1000)
  }

  console.log(`status=${result.status}`)
  console.log(`installs=${counts.installs}`)
  console.log(`failures=${counts.failures}`)
  console.log(`failure_rate=${result.failureRate.toFixed(4)}`)
  console.log(`reason=${result.reason}`)
}
