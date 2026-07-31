#!/usr/bin/env node
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  DEFAULT_MANIFEST,
  ROOT,
  appVersion,
  bundleVersion,
  checksumTree,
  findCompatibilityRow,
  git,
  isBootstrapRef,
  readJson,
  scanServiceWorkerGuard,
  submoduleIdentity,
  validatePublicOtaConfig,
} from './release-lib.mjs'

export const NATIVE_CAPACITOR_CONFIGS = [
  join('ios', 'App', 'App', 'capacitor.config.json'),
  join('android', 'app', 'src', 'main', 'assets', 'capacitor.config.json'),
]

// The live-reload dev server (SYNAPLAN_DEV_SERVER) writes server.url into the
// synced native configuration. A binary that loads its UI from a developer
// machine would break for every user and would not survive store review, so the
// synced files are checked directly rather than trusting the build environment.
export function scanNativeServerUrl(root = ROOT) {
  const findings = []
  for (const relativePath of NATIVE_CAPACITOR_CONFIGS) {
    const path = join(root, relativePath)
    if (!existsSync(path)) continue
    const url = readJson(path).server?.url
    if (url) findings.push(`${relativePath} points the WebView at a remote server: ${url}`)
  }
  return findings
}

export function collectDrift({ bootstrap = false, manifestPath = DEFAULT_MANIFEST } = {}) {
  const errors = []
  const warnings = []
  const version = appVersion()
  const identity = submoduleIdentity()

  const gitlink = git(['ls-files', '--stage', 'synaplan']).split(/\s+/)[1]
  if (!gitlink) errors.push('The synaplan gitlink is missing from HEAD')
  else if (gitlink !== identity.sha) {
    errors.push(`Submodule worktree ${identity.sha} differs from pinned gitlink ${gitlink}`)
  }

  const identifiers = readFileSync(join(ROOT, 'docs', 'IDENTIFIERS.md'), 'utf8')
  const identifierRef = identifiers.match(
    /\*\*(?:Pinned to|Current (?:development )?pin):\*\*\s*`([^`]+)`/
  )?.[1]
  const matchesIdentity = (ref) =>
    ref === identity.tag ||
    ref === identity.sha ||
    (/^[0-9a-f]{7,40}$/i.test(ref) && identity.sha.startsWith(ref))
  if (!identifierRef) {
    errors.push('docs/IDENTIFIERS.md does not declare a pinned synaplan ref')
  } else if (bootstrap && /^v3\./.test(identifierRef) && !identity.tag) {
    warnings.push(`IDENTIFIERS still records bootstrap ref ${identifierRef}`)
  } else if (!matchesIdentity(identifierRef)) {
    errors.push(`IDENTIFIERS pin ${identifierRef} does not identify ${identity.sha}`)
  }

  const compatibility = readFileSync(join(ROOT, 'docs', 'COMPATIBILITY.md'), 'utf8')
  const row = findCompatibilityRow(compatibility, version)
  if (!row) {
    errors.push(`COMPATIBILITY has no row for app ${version}`)
  } else if (isBootstrapRef(row.synaplanRef)) {
    const message = `COMPATIBILITY has a bootstrap synaplan ref for app ${version}`
    ;(bootstrap ? warnings : errors).push(message)
  } else if (!matchesIdentity(row.synaplanRef)) {
    errors.push(`COMPATIBILITY ref ${row.synaplanRef} does not identify ${identity.sha}`)
  }

  if (!existsSync(manifestPath)) {
    const message = `Release manifest is missing: ${manifestPath}`
    ;(bootstrap ? warnings : errors).push(message)
  } else {
    const manifest = readJson(manifestPath)
    if (manifest.app?.version !== version) {
      errors.push(`Manifest app version ${manifest.app?.version} differs from ${version}`)
    }
    if (manifest.synaplan?.sha !== identity.sha) {
      errors.push(`Manifest synaplan SHA ${manifest.synaplan?.sha} differs from ${identity.sha}`)
    }
    if (manifest.synaplan?.tag !== identity.tag) {
      errors.push(`Manifest synaplan tag ${manifest.synaplan?.tag} differs from ${identity.tag}`)
    }
    const apiContractPath = join(ROOT, 'synaplan', 'frontend', 'dist', 'openapi-contract.sha256')
    const apiContractSha256 = existsSync(apiContractPath)
      ? readFileSync(apiContractPath, 'utf8').trim()
      : null
    if (!apiContractSha256 || manifest.apiContractSha256 !== apiContractSha256) {
      errors.push('Manifest OpenAPI contract checksum differs from the built web bundle')
    }
    const expectedBundle = bundleVersion({
      version,
      sha: identity.sha,
      tag: identity.tag,
      build: manifest.app?.build,
    })
    if (manifest.bundleVersion !== expectedBundle) {
      errors.push(
        `Manifest bundle version ${manifest.bundleVersion} differs from ${expectedBundle}`
      )
    }
    if (
      manifest.app?.nativeCompatibility?.minVersion !== version ||
      manifest.app?.nativeCompatibility?.maxVersion !== version
    ) {
      errors.push('Manifest native compatibility must be locked to the package app version')
    }
    const expectedChannel = validatePublicOtaConfig().defaultChannel
    if (manifest.channel !== expectedChannel) {
      errors.push(`Manifest channel ${manifest.channel} differs from ${expectedChannel}`)
    }
    const distDir = join(ROOT, 'synaplan', 'frontend', 'dist')
    const actualFiles = checksumTree(distDir, new Set(['release-manifest.json', 'ota-bundle.zip']))
    if (JSON.stringify(manifest.files) !== JSON.stringify(actualFiles)) {
      errors.push('Manifest file checksums differ from the built web bundle')
    }
    const recordedBundle = row?.otaBundle?.trim()
    const hasRecordedBundle = recordedBundle && !/^(?:—|-|none)$/i.test(recordedBundle)
    if (
      row &&
      !isBootstrapRef(row.synaplanRef) &&
      hasRecordedBundle &&
      recordedBundle !== manifest.bundleVersion
    ) {
      errors.push(`COMPATIBILITY OTA bundle ${row.otaBundle} differs from the release manifest`)
    }
  }

  for (const finding of scanNativeServerUrl()) errors.push(finding)

  const serviceWorkers = scanServiceWorkerGuard(join(ROOT, 'synaplan', 'frontend', 'src'))
  for (const file of serviceWorkers.unguardedFiles) {
    const message = `Native service-worker guard is missing in synaplan/frontend/src/${file}`
    ;(bootstrap ? warnings : errors).push(message)
  }

  return { errors, warnings, version, identity, serviceWorkers }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const bootstrap = process.argv.includes('--bootstrap')
  const dryRun = process.argv.includes('--dry-run')
  const manifestIndex = process.argv.indexOf('--manifest')
  const manifestPath =
    manifestIndex >= 0 ? join(process.cwd(), process.argv[manifestIndex + 1]) : DEFAULT_MANIFEST
  try {
    const result = collectDrift({ bootstrap, manifestPath })
    for (const warning of result.warnings) console.warn(`[release-drift] WARNING: ${warning}`)
    for (const error of result.errors) console.error(`[release-drift] ERROR: ${error}`)
    console.log(
      `[release-drift] app=${result.version} synaplan=${result.identity.tag || result.identity.shortSha} ` +
        `serviceWorkers=${result.serviceWorkers.registrations} mode=${bootstrap ? 'bootstrap' : 'strict'}${dryRun ? ' dry-run' : ''}`
    )
    if (result.errors.length > 0) process.exitCode = 1
  } catch (error) {
    console.error(`[release-drift] ${error.message}`)
    process.exitCode = 1
  }
}
