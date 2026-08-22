/*
 * Gate 2 (Click) — integrity guard for the Maestro flows. Dependency-free: this
 * does NOT run Maestro (that needs a built app + emulator/simulator and is
 * device-gated). It keeps the committed flows honest so they can't silently rot:
 *   - correct, env-parameterised appId
 *   - a flow body (launchApp + at least one assertion)
 *   - the stable app-owned anchors the flows rely on (from synaplan-native.js)
 * The remaining locale-/network-independent app-owned anchor is the non-prod
 * environment badge (the old "Server settings" gear was removed; the server
 * switch now lives in the SPA's Admin → App server panel). If someone changes
 * the env-badge label, this fails here in `npm run ci-local` long before the
 * device run would.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const MAESTRO_DIR = join(ROOT, '.maestro')
const read = (rel) => readFileSync(join(MAESTRO_DIR, rel), 'utf-8')

const flows = readdirSync(MAESTRO_DIR)
  .filter((f) => f.endsWith('.yaml'))
  .sort()

test('the .maestro suite contains the expected app-shell flows', () => {
  for (const expected of ['01-smoke.yaml', '03-env-badge.yaml']) {
    assert.ok(flows.includes(expected), `missing Maestro flow: ${expected}`)
  }
})

for (const file of flows) {
  test(`${file} is a well-formed, env-parameterised Maestro flow`, () => {
    const body = read(file)

    // Header/body separator (Maestro flow config block followed by commands).
    assert.ok(body.includes('---'), `${file}: missing the '---' header separator`)

    // appId must be parameterised so one flow runs against any env build.
    assert.match(body, /appId:\s*\$\{APP_ID\}/, `${file}: appId must be \${APP_ID}`)

    // ...with a sane default that targets our bundle id family.
    const def = body.match(/APP_ID:\s*(\S+)/)
    assert.ok(def, `${file}: missing an env: APP_ID default`)
    assert.ok(
      def[1].startsWith('com.synaplan.app'),
      `${file}: APP_ID default "${def[1]}" must be a com.synaplan.app[.env] id`
    )

    // A real flow: it launches the app and asserts at least one thing.
    assert.match(body, /-\s*launchApp/, `${file}: must launch the app`)
    assert.match(
      body,
      /(assertVisible|assertNotVisible|extendedWaitUntil)/,
      `${file}: must assert something`
    )
  })
}

test('01-smoke anchors on the app-owned env badge (no white screen)', () => {
  const body = read('01-smoke.yaml')
  assert.match(body, /DEV\|STAGING/, 'smoke flow must wait for the app-owned env badge')
  assert.match(body, /clearState:\s*true/, 'smoke flow should cold-launch from a clean state')
  const def = body.match(/APP_ID:\s*(\S+)/)
  assert.ok(
    def && def[1] !== 'com.synaplan.app',
    'smoke flow must default to a non-prod build (the env badge is prod-hidden)'
  )
})

test('03-env-badge defaults to a non-prod build and checks the env badge', () => {
  const body = read('03-env-badge.yaml')
  const def = body.match(/APP_ID:\s*(\S+)/)
  assert.ok(def && def[1] !== 'com.synaplan.app', 'env-badge flow must default to a non-prod build')
  assert.match(body, /DEV|STAGING/, 'env-badge flow must assert the env label')
})
