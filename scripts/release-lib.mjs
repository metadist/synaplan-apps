import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { basename, join, relative } from 'node:path'

export const ROOT = new URL('../', import.meta.url).pathname.replace(/\/$/, '')
export const SUBMODULE = join(ROOT, 'synaplan')
export const DEFAULT_MANIFEST = join(SUBMODULE, 'frontend', 'dist', 'release-manifest.json')

export function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'))
}

export function git(args, cwd = ROOT) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim()
}

export function appVersion() {
  return String(readJson(join(ROOT, 'package.json')).version)
}

export function buildNumber(env = process.env) {
  const explicit = String(env.SYNAPLAN_BUILD_NUMBER ?? env.CI_BUILD_NUMBER ?? '').trim()
  if (/^[1-9]\d*$/.test(explicit)) return explicit
  return git(['rev-list', '--count', 'HEAD']) || '1'
}

export function submoduleIdentity() {
  const sha = git(['rev-parse', 'HEAD'], SUBMODULE)
  let tag = null
  try {
    tag = git(['describe', '--tags', '--exact-match', 'HEAD'], SUBMODULE)
  } catch {
    // A bootstrap commit is allowed before the coordinated v4 tag exists.
  }
  return { sha, shortSha: sha.slice(0, 12), tag }
}

export function bundleVersion({ version, sha, tag, build }) {
  const ref = tag
    ?.replace(/^v/, '')
    .replace(/[^0-9A-Za-z-]+/g, '-')
    .replace(/^-|-$/g, '')
  const ci = String(build).replace(/[^0-9A-Za-z-]+/g, '-')
  const source = ref ? `${ref}.${sha.slice(0, 12)}` : sha.slice(0, 12)
  return `${version}-synaplan.${source}.ci.${ci}`
}

export function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex')
}

export function checksumTree(directory, excluded = new Set()) {
  const files = []
  const visit = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) =>
      a.name.localeCompare(b.name)
    )) {
      const path = join(dir, entry.name)
      if (entry.isDirectory()) visit(path)
      else if (entry.isFile() && !excluded.has(basename(path))) {
        files.push({
          path: relative(directory, path).replaceAll('\\', '/'),
          sha256: sha256File(path),
        })
      }
    }
  }
  visit(directory)
  return files
}

export function parseCompatibility(markdown) {
  const rows = markdown
    .split(/\r?\n/)
    .filter((line) => line.startsWith('|') && !line.includes('---'))
    .slice(1)
    .map((line) =>
      line
        .split('|')
        .slice(1, -1)
        .map((cell) => cell.trim())
    )
  return rows.map((cells) => ({
    appVersion: cells[0]
      ?.replace(/_\([^)]+\)_\s*/, '')
      .replaceAll('*', '')
      .trim(),
    synaplanRef: cells[1]?.replaceAll('*', '').replaceAll('_', '').replaceAll('`', '').trim(),
    apiContract: cells[2]?.trim(),
    otaBundle: cells[3]?.replaceAll('`', '').trim(),
    minAppVersion: cells[4]?.trim(),
    notes: cells[5]?.trim(),
  }))
}

export function findCompatibilityRow(markdown, version) {
  return parseCompatibility(markdown).find((row) => row.appVersion === version)
}

export function isBootstrapRef(value) {
  return !value || /TBD|baseline tag|unreleased/i.test(value)
}

export function validatePublicOtaConfig(env = process.env) {
  const appEnv = String(env.SYNAPLAN_ENV || 'prod')
    .trim()
    .toLowerCase()
  const updateUrl = String(env.SYNAPLAN_OTA_UPDATE_URL || '').trim()
  const channelUrl = String(env.SYNAPLAN_OTA_CHANNEL_URL || '').trim()
  const statsUrl = String(env.SYNAPLAN_OTA_STATS_URL || '').trim()
  const publicKey = String(env.SYNAPLAN_OTA_PUBLIC_KEY || '').trim()
  const defaultChannel = String(env.SYNAPLAN_OTA_DEFAULT_CHANNEL || 'production').trim()
  if (!/^[a-z0-9][a-z0-9._-]*$/i.test(defaultChannel)) {
    throw new Error('SYNAPLAN_OTA_DEFAULT_CHANNEL must be a simple channel name')
  }
  for (const [name, value] of [
    ['SYNAPLAN_OTA_UPDATE_URL', updateUrl],
    ['SYNAPLAN_OTA_CHANNEL_URL', channelUrl],
    ['SYNAPLAN_OTA_STATS_URL', statsUrl],
  ]) {
    if (!value) continue
    let url
    try {
      url = new URL(value)
    } catch {
      throw new Error(`${name} must be an absolute URL`)
    }
    if (appEnv === 'prod' && url.protocol !== 'https:') {
      throw new Error(`${name} must use HTTPS for production builds`)
    }
  }
  return { updateUrl, channelUrl, statsUrl, publicKey, defaultChannel }
}

export function checkServiceWorkerGuard(source) {
  const registrations = source.match(/(?:navigator\.)?serviceWorker\s*\.\s*register\s*\(/g) ?? []
  if (registrations.length === 0) return { registrations: 0, guarded: true }
  const nativeGuard =
    /(?:!isNativeApp\s*\(\)|!Capacitor\.isNativePlatform\s*\(\)|if\s*\(\s*isNativeApp\s*\(\)\s*\)\s*(?:return|throw))/
  return { registrations: registrations.length, guarded: nativeGuard.test(source) }
}

export function scanServiceWorkerGuard(directory) {
  if (!existsSync(directory)) return { registrations: 0, unguardedFiles: [] }
  let registrations = 0
  const unguardedFiles = []
  const visit = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name)
      if (entry.isDirectory()) visit(path)
      else if (/\.(?:js|mjs|ts|vue)$/.test(entry.name)) {
        const result = checkServiceWorkerGuard(readFileSync(path, 'utf8'))
        registrations += result.registrations
        if (!result.guarded) unguardedFiles.push(relative(directory, path))
      }
    }
  }
  visit(directory)
  return { registrations, unguardedFiles }
}
