#!/usr/bin/env node
// Sets the app version for a store binary the release chain does not open on
// its own: an app-only release, or a resubmission after the current version was
// approved. Same rule as the synchronization: follow the pinned Synaplan tag,
// else count the patch up. The compatibility row is written in the same step,
// because the strict release check refuses a version the matrix does not list.
import { fileURLToPath } from 'node:url'

import { appVersion, nextStoreVersion, submoduleIdentity, writeAppVersion } from './release-lib.mjs'
import { updateReleaseRecords } from './sync-synaplan.mjs'

export function planStoreVersion({ current, tag, sha, dryRun }) {
  const next = nextStoreVersion(current, tag)
  const ref = tag || sha
  if (!ref) {
    throw new Error('Cannot record a store version without a pinned Synaplan tag or SHA')
  }
  if (!dryRun) writeAppVersion(next)
  const records = updateReleaseRecords({ version: next, ref, dryRun })
  return { current, next, ref, records }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const dryRun = process.argv.includes('--dry-run')
  try {
    const { tag, sha } = submoduleIdentity()
    const plan = planStoreVersion({ current: appVersion(), tag, sha, dryRun })
    console.log(
      `[store-version] ${dryRun ? 'would set' : 'set'} app ${plan.current} → ${plan.next} (synaplan ${tag || 'untagged pin'})`
    )
  } catch (error) {
    console.error(`[store-version] ${error instanceof Error ? error.message : error}`)
    process.exitCode = 1
  }
}
