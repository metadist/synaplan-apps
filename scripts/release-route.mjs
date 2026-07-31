#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { ROOT, git } from './release-lib.mjs'

export const RELEASE_ROUTE = join(ROOT, '.github', 'release-route.json')

// Only these two routes exist for an app delivery. `backend-only` and
// `no-app-impact` never reach this file, because the source repository does not
// tag or dispatch them at all.
export const DELIVERY_ROUTES = ['ota-candidate', 'store-required']

const RELEASE_TAG = /^v\d+(?:\.\d+){1,2}(?:[+-][0-9A-Za-z.-]+)?$/

export function createReleaseRoute({
  tag,
  sha,
  classification,
  sourceRunId = '',
  recordedAt = new Date().toISOString(),
}) {
  if (!RELEASE_TAG.test(String(tag))) {
    throw new Error(`Refusing a release route without an exact release tag: ${tag}`)
  }
  if (!/^[0-9a-f]{40}$/i.test(String(sha))) {
    throw new Error(`Refusing a release route without a full commit SHA: ${sha}`)
  }
  if (!DELIVERY_ROUTES.includes(classification)) {
    throw new Error(
      `Refusing an unknown delivery route "${classification}"; expected one of ${DELIVERY_ROUTES.join(', ')}`
    )
  }
  return {
    schemaVersion: 1,
    tag: String(tag),
    sha: String(sha).toLowerCase(),
    classification,
    sourceRunId: String(sourceRunId),
    recordedAt: new Date(recordedAt).toISOString(),
  }
}

export function readReleaseRoute(path = RELEASE_ROUTE) {
  const route = JSON.parse(readFileSync(path, 'utf8'))
  // Re-validating on read keeps a hand-edited or truncated file from routing a
  // delivery; the workflow that consumes this fails instead of guessing.
  return createReleaseRoute(route)
}

// A route that no longer describes the pinned submodule is stale: the pin moved
// on without the automation, so acting on it would deliver the wrong revision.
export function verifyReleaseRoute(path = RELEASE_ROUTE) {
  const route = readReleaseRoute(path)
  const gitlink = git(['ls-files', '--stage', 'synaplan']).split(/\s+/)[1]
  if (gitlink !== route.sha) {
    throw new Error(`Release route targets ${route.sha}, but the pinned gitlink is ${gitlink}`)
  }
  return route
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const args = process.argv.slice(2)
  const value = (name) => {
    const index = args.indexOf(`--${name}`)
    return index >= 0 ? args[index + 1] : undefined
  }
  if (args.includes('--verify')) {
    try {
      const route = verifyReleaseRoute()
      for (const key of ['classification', 'tag', 'sha']) {
        console.log(`${key}=${route[key]}`)
      }
    } catch (error) {
      console.error(`[release-route] ${error.message}`)
      process.exitCode = 1
    }
  } else {
    try {
      const route = createReleaseRoute({
        tag: value('tag'),
        sha: value('sha'),
        classification: value('classification'),
        sourceRunId: value('source-run-id') ?? '',
        ...(value('recorded-at') ? { recordedAt: value('recorded-at') } : {}),
      })
      writeFileSync(RELEASE_ROUTE, `${JSON.stringify(route, null, 2)}\n`)
      console.log(`[release-route] ${route.classification} for ${route.tag} (${route.sha})`)
    } catch (error) {
      console.error(`[release-route] ${error.message}`)
      process.exitCode = 1
    }
  }
}
