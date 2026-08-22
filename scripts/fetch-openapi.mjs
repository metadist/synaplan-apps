#!/usr/bin/env node
/**
 * Resolves the OpenAPI contract that `build.sh` needs.
 *
 * `build.sh` deliberately refuses to guess a source: a release build must use the
 * contract that belongs to the pinned commit, and a silent production fallback
 * would hide a mismatch. This helper makes the two legitimate sources explicit
 * and prints the resulting file path, so the build stays a single, exclusive
 * choice:
 *
 *   SYNAPLAN_OPENAPI_FILE="$(npm run --silent openapi:fetch)" ./build.sh
 *
 * Sources:
 *   --from-local [url]  A running backend, default http://localhost:8000/api/doc.json
 *   --from-release      The attested artifact of the pinned Synaplan commit (needs gh)
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { ROOT, SUBMODULE, git } from './release-lib.mjs'

const DEFAULT_LOCAL_URL = 'http://localhost:8000/api/doc.json'
const SOURCE_REPOSITORY = 'metadist/synaplan'

const outputDirectory = join(ROOT, 'artifacts', 'openapi')

function assertJson(path) {
  JSON.parse(readFileSync(path, 'utf8'))
  return path
}

async function fromLocal(url) {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`${url} answered ${response.status}; is the backend running?`)
  }
  const path = join(outputDirectory, 'openapi-spec.json')
  writeFileSync(path, await response.text())
  return assertJson(path)
}

function fromRelease() {
  const sha = git(['rev-parse', 'HEAD'], SUBMODULE)
  const tag = git(['describe', '--tags', '--exact-match', 'HEAD'], SUBMODULE)
  const name = `mobile-release-${tag}-${sha}`
  const id = execFileSync(
    'gh',
    [
      'api',
      '--method',
      'GET',
      `repos/${SOURCE_REPOSITORY}/actions/artifacts`,
      '-f',
      `name=${name}`,
      '--jq',
      '[.artifacts[] | select(.expired == false)] | first | .id // empty',
    ],
    { encoding: 'utf8' }
  ).trim()
  if (!id) throw new Error(`No unexpired artifact "${name}" exists in ${SOURCE_REPOSITORY}`)
  const archive = join(tmpdir(), `${name}.zip`)
  writeFileSync(
    archive,
    execFileSync('gh', ['api', `repos/${SOURCE_REPOSITORY}/actions/artifacts/${id}/zip`], {
      encoding: 'buffer',
      maxBuffer: 64 * 1024 * 1024,
    })
  )
  execFileSync('unzip', ['-o', '-q', archive, '-d', outputDirectory], { stdio: 'inherit' })
  return assertJson(join(outputDirectory, 'openapi-spec.json'))
}

const args = process.argv.slice(2)
try {
  mkdirSync(outputDirectory, { recursive: true })
  const localIndex = args.indexOf('--from-local')
  const path = args.includes('--from-release')
    ? fromRelease()
    : await fromLocal(
        localIndex >= 0 && args[localIndex + 1] && !args[localIndex + 1].startsWith('--')
          ? args[localIndex + 1]
          : DEFAULT_LOCAL_URL
      )
  console.log(path)
} catch (error) {
  console.error(`[fetch-openapi] ${error.message}`)
  process.exitCode = 1
}
