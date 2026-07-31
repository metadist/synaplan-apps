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

// A version bump would otherwise stop the synchronization at the first release
// after it, because the matrix row for the new app version does not exist yet.
// The row is created from the previous one so the recorded API contract carries
// over instead of silently emptying.
function insertCompatibilityRow(rows, version) {
  const separator = rows.findIndex((line) => /^\|[\s-]*-{3,}/.test(line))
  if (separator < 0) throw new Error('COMPATIBILITY has no matrix table to extend')
  const previous = rows[separator + 1]?.startsWith('|') ? rows[separator + 1].split('|') : []
  const row = ['', ` ${version} `, ' ', previous[3] ?? ' ', ' — ', ' _empty (gate off)_ ', ' ', '']
  rows.splice(separator + 1, 0, row.join('|'))
  return separator + 1
}

export function updateReleaseRecords({ version, ref, dryRun = false }) {
  const compatibilityPath = join(ROOT, 'docs', 'COMPATIBILITY.md')
  const identifiersPath = join(ROOT, 'docs', 'IDENTIFIERS.md')
  const compatibility = readFileSync(compatibilityPath, 'utf8')
  const rows = compatibility.split(/\r?\n/)
  const matches = (line) =>
    line.startsWith('|') &&
    line
      .split('|')[1]
      ?.replace(/_\([^)]+\)_\s*/, '')
      .replaceAll('*', '')
      .trim() === version
  const existing = rows.findIndex(matches)
  const index = existing >= 0 ? existing : insertCompatibilityRow(rows, version)
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

// `--resolve` is the local escape hatch for a branch that has no release tag
// yet. The branch is never pinned: it is read once and the commit it points at
// right now is pinned instead, so the recorded pin stays immutable.
export function resolveRemoteRef(ref) {
  const output = execFileSync('git', ['ls-remote', 'origin', ref], {
    cwd: SUBMODULE,
    encoding: 'utf8',
  }).trim()
  const sha = output.split(/\r?\n/).filter(Boolean)[0]?.split(/\s+/)[0]
  if (!/^[0-9a-f]{40}$/i.test(sha ?? '')) {
    throw new Error(`Remote origin does not expose "${ref}"`)
  }
  return sha.toLowerCase()
}

function commitPin(ref, sha) {
  git(['add', 'synaplan', 'docs/COMPATIBILITY.md', 'docs/IDENTIFIERS.md'])
  git(['commit', '-m', `chore: pin synaplan to ${ref} (${sha.slice(0, 12)})`])
  console.log(`[sync-synaplan] committed the pin on ${git(['rev-parse', '--abbrev-ref', 'HEAD'])}`)
}

const USAGE = `Usage:
  node scripts/sync-synaplan.mjs --ref <tag-or-full-sha> [--dry-run] [--commit]
  node scripts/sync-synaplan.mjs --ref origin/main --resolve [--commit]

Options:
  --ref <ref>   Exact release tag or full commit SHA to pin
  --resolve     Read a branch once and pin the commit it currently points at
  --commit      Create a local commit for the pin and the updated release records
  --dry-run     Report what would change without touching the worktree
`

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const args = process.argv.slice(2)
  const refIndex = args.indexOf('--ref')
  if (refIndex < 0 || !args[refIndex + 1]) {
    console.error(USAGE)
    process.exitCode = 2
  } else {
    try {
      const requestedRef = args[refIndex + 1].trim()
      const dryRun = args.includes('--dry-run')
      const resolvedRef = args.includes('--resolve') ? resolveRemoteRef(requestedRef) : requestedRef
      const sha = fetchExplicitRef(resolvedRef, dryRun)
      const recordRef = /^[0-9a-f]{40}$/i.test(resolvedRef) ? sha : resolvedRef
      if (!dryRun) {
        git(['checkout', '--detach', sha], SUBMODULE)
        updateReleaseRecords({ version: appVersion(), ref: recordRef })
        console.log(`[sync-synaplan] pinned synaplan to ${recordRef} (${sha})`)
        if (args.includes('--commit')) commitPin(recordRef, sha)
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
