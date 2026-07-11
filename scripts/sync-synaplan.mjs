#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { ROOT, SUBMODULE, appVersion, git } from './release-lib.mjs'

export function rejectMovingBranch(ref) {
  if (/^(?:refs\/heads\/)?(?:main|master)$/i.test(ref) || /^origin\/(?:main|master)$/i.test(ref)) {
    throw new Error('Refusing to pin a moving main/master branch; provide an explicit tag or SHA')
  }
  if (/^(?:origin\/)?HEAD$/i.test(ref)) {
    throw new Error('Refusing to pin remote HEAD; provide an explicit tag or SHA')
  }
  if (!/^[0-9a-f]{40}$/i.test(ref) && !/^v\d+(?:\.\d+){1,2}(?:[+-][0-9A-Za-z.-]+)?$/.test(ref)) {
    throw new Error('Refusing non-immutable ref; provide an exact v* tag or full commit SHA')
  }
}

function fetchExplicitRef(ref, dryRun) {
  rejectMovingBranch(ref)
  const isSha = /^[0-9a-f]{40}$/i.test(ref)
  if (!dryRun) {
    const remoteRef = isSha ? ref : `refs/tags/${ref}:refs/tags/${ref}`
    execFileSync('git', ['fetch', '--no-tags', 'origin', remoteRef], {
      cwd: SUBMODULE,
      stdio: 'inherit',
    })
    return isSha
      ? git(['rev-parse', 'FETCH_HEAD^{commit}'], SUBMODULE)
      : git(['rev-parse', `${ref}^{commit}`], SUBMODULE)
  }
  if (dryRun) {
    const output = execFileSync(
      'git',
      ['ls-remote', '--tags', 'origin', ref, `refs/tags/${ref}`, `refs/tags/${ref}^{}`],
      { cwd: SUBMODULE, encoding: 'utf8' }
    ).trim()
    const lines = output.split(/\r?\n/).filter(Boolean)
    const peeled = lines.find((line) => line.endsWith('^{}')) || lines[0]
    if (!peeled) throw new Error(`Remote origin does not expose explicit tag/ref "${ref}"`)
    return peeled.split(/\s+/)[0]
  }
}

export function updateReleaseRecords({ version, ref, dryRun = false }) {
  const compatibilityPath = join(ROOT, 'docs', 'COMPATIBILITY.md')
  const identifiersPath = join(ROOT, 'docs', 'IDENTIFIERS.md')
  const compatibility = readFileSync(compatibilityPath, 'utf8')
  const rows = compatibility.split(/\r?\n/)
  const index = rows.findIndex(
    (line) =>
      line.startsWith('|') &&
      line
        .split('|')[1]
        ?.replace(/_\([^)]+\)_\s*/, '')
        .replaceAll('*', '')
        .trim() === version
  )
  if (index < 0) throw new Error(`COMPATIBILITY has no row for app ${version}`)
  const cells = rows[index].split('|')
  cells[1] = ` ${version} `
  cells[2] = ` \`${ref}\` `
  cells[4] = ' — '
  cells[6] = ` Reviewed mobile baseline ${ref} `
  rows[index] = cells.join('|')
  const nextCompatibility = rows.join('\n')

  const identifiers = readFileSync(identifiersPath, 'utf8')
  const pinPattern =
    /- \*\*(?:Pinned to|Current (?:development )?pin):\*\*.*(?:\r?\n\s{2}.*)*(?:\r?\n- \*\*Release pin:\*\*.*(?:\r?\n\s{2}.*)*)?/
  if (!pinPattern.test(identifiers)) {
    throw new Error('Could not locate the IDENTIFIERS submodule pin')
  }
  const nextIdentifiers = identifiers.replace(
    pinPattern,
    `- **Current pin:** \`${ref}\` (exact release tag/SHA; never a moving branch).`
  )

  if (!dryRun) {
    writeFileSync(compatibilityPath, nextCompatibility)
    writeFileSync(identifiersPath, nextIdentifiers)
  }
  return { compatibility: nextCompatibility, identifiers: nextIdentifiers }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const args = process.argv.slice(2)
  const refIndex = args.indexOf('--ref')
  if (refIndex < 0 || !args[refIndex + 1]) {
    console.error('Usage: node scripts/sync-synaplan.mjs --ref <tag-or-full-sha> [--dry-run]')
    process.exitCode = 2
  } else {
    try {
      const requestedRef = args[refIndex + 1].trim()
      const dryRun = args.includes('--dry-run')
      const sha = fetchExplicitRef(requestedRef, dryRun)
      const recordRef = /^[0-9a-f]{40}$/i.test(requestedRef) ? sha : requestedRef
      if (!dryRun) {
        git(['checkout', '--detach', sha], SUBMODULE)
        updateReleaseRecords({ version: appVersion(), ref: recordRef })
        console.log(`[sync-synaplan] pinned synaplan to ${recordRef} (${sha})`)
      } else {
        updateReleaseRecords({ version: appVersion(), ref: recordRef, dryRun: true })
        console.log(`[sync-synaplan] dry-run: would pin synaplan to ${recordRef} (${sha})`)
      }
    } catch (error) {
      console.error(`[sync-synaplan] ${error.message}`)
      process.exitCode = 1
    }
  }
}
