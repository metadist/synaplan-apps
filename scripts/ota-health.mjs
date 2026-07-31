#!/usr/bin/env node
import { fileURLToPath } from 'node:url'

export const APP_ID = 'com.synaplan.app'

/**
 * Observes a published OTA bundle through Capgo's self-hosted statistics API.
 *
 * What that API can and cannot tell us decides the whole design here. The only
 * per-bundle series it exposes is `GET /app/{appId}/bundle_usage`, built from
 * the `daily_version` rollup: one row per day and version, counting the devices
 * that reported in. There is no failure counter anywhere in the public API, and
 * the granularity is a day, not a minute.
 *
 * So this module measures ADOPTION — how many devices actually run a bundle —
 * and never claims to have measured a failure rate. That is still meaningful: a
 * device that cannot start a bundle reverts itself within `appReadyTimeout` and
 * reports the PREVIOUS version again. A bundle whose adoption stays at zero
 * while other versions keep reporting is therefore the observable signature of a
 * broken rollout.
 *
 * It is deliberately not the signature of a *slow* rollout being distinguished
 * from a broken one: devices only check in when the app is foregrounded, so low
 * adoption shortly after publishing is normal. `evaluateOtaHealth` only reaches
 * `unhealthy` once enough devices reported on the observed day, which is why the
 * workflow treats withdrawal as opt-in rather than the default.
 */

const DAY_MS = 24 * 60 * 60 * 1000

/** Widest window the rollup can answer for; `from`/`to` are required by the API. */
export function observationWindow(now = new Date(), days = 2) {
  const to = new Date(now)
  const from = new Date(now.getTime() - days * DAY_MS)
  return { from: from.toISOString(), to: to.toISOString() }
}

/**
 * Builds the statistics request.
 *
 * `base` is the statistics function root (for our deployment
 * `https://api.<domain>/statistics`). A base carrying `{appId}` or `{bundle}` is
 * substituted verbatim instead, so a deployment with a different API shape can
 * be pointed at without changing this file.
 */
export function statisticsUrl(base, bundle, appId = APP_ID, window = observationWindow()) {
  if (base.includes('{bundle}') || base.includes('{appId}')) {
    return base.replaceAll('{bundle}', encodeURIComponent(bundle)).replaceAll('{appId}', appId)
  }
  const url = new URL(`${base.replace(/\/$/, '')}/app/${encodeURIComponent(appId)}/bundle_usage`)
  url.searchParams.set('from', window.from)
  url.searchParams.set('to', window.to)
  return url.toString()
}

const lastPositive = (values) => {
  if (!Array.isArray(values)) return 0
  for (let index = values.length - 1; index >= 0; index -= 1) {
    const value = values[index]
    if (typeof value === 'number' && Number.isFinite(value) && value > 0) return value
  }
  return 0
}

/**
 * Reduces the Chart.js-shaped payload to "devices on the observed bundle" versus
 * "devices reporting any version". `metaCounts` carries device counts; `data`
 * carries percentages, so the counts are what we read.
 */
export function extractAdoption(payload, bundle) {
  const datasets = Array.isArray(payload?.datasets) ? payload.datasets : []
  let onBundle = 0
  let total = 0
  for (const dataset of datasets) {
    const devices = lastPositive(dataset?.metaCounts)
    total += devices
    if (dataset?.label === bundle) onBundle += devices
  }
  return { onBundle, total }
}

export function evaluateOtaHealth({ onBundle, total, minDevices = 25 }) {
  const share = total === 0 ? 0 : onBundle / total
  if (total < minDevices) {
    return {
      status: 'inconclusive',
      share,
      reason: `Only ${total} of ${minDevices} devices reported in so far; the rollup is daily, so this is expected shortly after publishing.`,
    }
  }
  if (onBundle === 0) {
    return {
      status: 'unhealthy',
      share,
      reason: `${total} devices reported in and not one of them runs the bundle, which is what an on-device revert looks like.`,
    }
  }
  return {
    status: 'healthy',
    share,
    reason: `${onBundle} of ${total} reporting devices run the bundle (${(share * 100).toFixed(1)}%).`,
  }
}

async function fetchAdoption({ base, bundle, apiKey }) {
  const response = await fetch(statisticsUrl(base, bundle), {
    headers: { authorization: apiKey, accept: 'application/json' },
  })
  if (!response.ok) {
    throw new Error(`Statistics endpoint answered ${response.status}`)
  }
  return extractAdoption(await response.json(), bundle)
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
  const options = { minDevices: Number(value('min-devices', '25')) }

  // Fail loudly instead of reporting a green health check nobody measured.
  if (!base || !apiKey || !bundle) {
    console.error(
      '[ota-health] CAPGO_STATS_API_URL, CAPGO_API_KEY and --bundle are required to observe a release'
    )
    process.exit(1)
  }

  const deadline = Date.now() + deadlineMinutes * 60_000
  let verdict = {
    status: 'inconclusive',
    share: 0,
    reason: 'No statistics were returned within the observation window.',
  }

  while (Date.now() < deadline) {
    try {
      verdict = evaluateOtaHealth({
        ...(await fetchAdoption({ base, bundle, apiKey })),
        ...options,
      })
    } catch (error) {
      verdict = {
        status: 'inconclusive',
        share: 0,
        reason: `Statistics unavailable: ${error.message}`,
      }
    }
    if (verdict.status !== 'inconclusive') break
    await sleep(intervalSeconds * 1000)
  }

  console.log(`status=${verdict.status}`)
  console.log(`share=${verdict.share.toFixed(4)}`)
  console.log(`reason=${verdict.reason}`)
}
