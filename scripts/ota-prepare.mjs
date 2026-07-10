#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

import { ROOT, sha256File, validatePublicOtaConfig } from './release-lib.mjs'
import { createReleaseManifest } from './release-manifest.mjs'

const dryRun = process.argv.includes('--dry-run')
const distDir = join(ROOT, 'synaplan', 'frontend', 'dist')

try {
  const ota = validatePublicOtaConfig()
  if (!ota.updateUrl || !ota.channelUrl || !ota.statsUrl || !ota.publicKey) {
    throw new Error(
      'Self-hosted preparation requires update, channel, stats, and public signing-key configuration'
    )
  }
  const manifest = createReleaseManifest({ distDir })
  const artifactDir = join(ROOT, 'artifacts', 'ota')
  const zipPath = join(artifactDir, `${manifest.bundleVersion}.zip`)
  const planPath = join(artifactDir, `${manifest.bundleVersion}.publish.json`)

  if (dryRun) {
    console.log(
      JSON.stringify(
        {
          action: 'prepare-only',
          bundleVersion: manifest.bundleVersion,
          channel: manifest.channel,
          updateUrl: ota.updateUrl,
          channelUrl: ota.channelUrl,
          statsUrl: ota.statsUrl,
          zipPath,
          publishes: false,
        },
        null,
        2
      )
    )
  } else {
    mkdirSync(artifactDir, { recursive: true })
    writeFileSync(join(distDir, 'release-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
    if (existsSync(zipPath)) rmSync(zipPath)
    execFileSync('zip', ['-q', '-r', zipPath, '.'], { cwd: distDir, stdio: 'inherit' })
    const plan = {
      schemaVersion: 1,
      action: 'upload-to-self-hosted-capgo',
      publishes: false,
      bundleVersion: manifest.bundleVersion,
      appId: 'com.synaplan.app',
      channel: manifest.channel,
      updateUrl: ota.updateUrl,
      channelUrl: ota.channelUrl,
      statsUrl: ota.statsUrl,
      artifact: {
        file: zipPath,
        sha256: sha256File(zipPath),
      },
    }
    mkdirSync(dirname(planPath), { recursive: true })
    writeFileSync(planPath, `${JSON.stringify(plan, null, 2)}\n`)
    console.log(`[ota-prepare] zip=${zipPath}`)
    console.log(`[ota-prepare] publish-plan=${planPath}`)
    console.log('[ota-prepare] no upload or external publication was attempted')
  }
} catch (error) {
  console.error(`[ota-prepare] ${error.message}`)
  process.exitCode = 1
}
