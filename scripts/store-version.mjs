#!/usr/bin/env node
// Sets the app version for a store binary the release chain does not open on
// its own: an app-only release, or a resubmission after the current version was
// approved. Same rule as the synchronization: follow the pinned Synaplan tag,
// else count the patch up.
import { appVersion, nextStoreVersion, submoduleIdentity, writeAppVersion } from './release-lib.mjs'

const dryRun = process.argv.includes('--dry-run')
const { tag } = submoduleIdentity()
const current = appVersion()
const next = nextStoreVersion(current, tag)

if (!dryRun) writeAppVersion(next)
console.log(
  `[store-version] ${dryRun ? 'would set' : 'set'} app ${current} → ${next} (synaplan ${tag || 'untagged pin'})`
)
