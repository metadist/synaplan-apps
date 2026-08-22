#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  DEFAULT_MANIFEST,
  ROOT,
  appVersion,
  buildNumber,
  bundleVersion,
  checksumTree,
  submoduleIdentity,
  validatePublicOtaConfig,
} from './release-lib.mjs'

export function createReleaseManifest({
  distDir = join(ROOT, 'synaplan', 'frontend', 'dist'),
  env = process.env,
  generatedAt = new Date().toISOString(),
} = {}) {
  if (!existsSync(distDir)) throw new Error(`Web bundle directory does not exist: ${distDir}`)
  const apiContractPath = join(distDir, 'openapi-contract.sha256')
  if (!existsSync(apiContractPath)) {
    throw new Error(`OpenAPI contract checksum is missing: ${apiContractPath}`)
  }
  const apiContractSha256 = readFileSync(apiContractPath, 'utf8').trim()
  if (!/^[0-9a-f]{64}$/.test(apiContractSha256)) {
    throw new Error('OpenAPI contract checksum must be a lowercase SHA256 value')
  }
  const version = appVersion()
  const build = buildNumber(env)
  const synaplan = submoduleIdentity()
  const ota = validatePublicOtaConfig(env)
  const nativeVersion = String(env.SYNAPLAN_NATIVE_VERSION || version).trim()
  const nativeBuild = String(env.SYNAPLAN_NATIVE_BUILD || build).trim()
  if (nativeVersion !== version) {
    throw new Error(
      `SYNAPLAN_NATIVE_VERSION (${nativeVersion}) must match package version (${version})`
    )
  }
  if (!/^[1-9]\d*$/.test(nativeBuild)) {
    throw new Error('SYNAPLAN_NATIVE_BUILD must be a positive integer')
  }

  return {
    schemaVersion: 1,
    apiContractSha256,
    bundleVersion: bundleVersion({
      version,
      sha: synaplan.sha,
      tag: synaplan.tag,
      build,
    }),
    channel: ota.defaultChannel,
    generatedAt,
    app: {
      version,
      build,
      nativeCompatibility: {
        minVersion: nativeVersion,
        maxVersion: nativeVersion,
        iosBuild: nativeBuild,
        androidVersionCode: Number(nativeBuild),
      },
    },
    synaplan: {
      sha: synaplan.sha,
      tag: synaplan.tag,
    },
    files: checksumTree(distDir, new Set(['release-manifest.json', 'ota-bundle.zip'])),
  }
}

function parseArgs(argv) {
  const outputIndex = argv.indexOf('--output')
  const distIndex = argv.indexOf('--dist')
  return {
    dryRun: argv.includes('--dry-run'),
    output: outputIndex >= 0 ? resolve(argv[outputIndex + 1]) : DEFAULT_MANIFEST,
    distDir:
      distIndex >= 0 ? resolve(argv[distIndex + 1]) : join(ROOT, 'synaplan', 'frontend', 'dist'),
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    const args = parseArgs(process.argv.slice(2))
    const manifest = createReleaseManifest({ distDir: args.distDir })
    if (args.dryRun) {
      console.log(JSON.stringify(manifest, null, 2))
    } else {
      mkdirSync(dirname(args.output), { recursive: true })
      writeFileSync(args.output, `${JSON.stringify(manifest, null, 2)}\n`)
      console.log(`[release-manifest] wrote ${args.output}`)
      console.log(
        `[release-manifest] bundle=${manifest.bundleVersion} files=${manifest.files.length}`
      )
    }
  } catch (error) {
    console.error(`[release-manifest] ${error.message}`)
    process.exitCode = 1
  }
}
