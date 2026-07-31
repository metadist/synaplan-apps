#!/usr/bin/env node
/**
 * Validate the OTA verification key before it is compiled into a build.
 *
 * The updater plugin parses this key at launch and calls `fatalError` when it
 * cannot, so a malformed value does not degrade the app, it kills it on every
 * device. Checking the key here turns that into a failed build.
 */

import { fileURLToPath } from 'node:url'

const PEM_MARKERS = /-----(?:BEGIN|END) (?:RSA )?PUBLIC KEY-----/g
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/
const DER_SEQUENCE = 0x30

/**
 * Strip carriage returns and surrounding whitespace.
 *
 * A browser submits a textarea with CRLF line endings, so a key pasted into the
 * GitHub web interface arrives with carriage returns. The plugin removes line
 * feeds but not carriage returns, and the leftovers break its base64 decoding.
 */
export function normalizePublicKey(value) {
  return (value ?? '').replace(/\r/g, '').trim()
}

/** Describe why the key is unusable, or return null when it is fine. */
export function publicKeyProblem(value) {
  const key = normalizePublicKey(value)
  if (!key) {
    return 'is empty'
  }
  const body = key.replace(PEM_MARKERS, '').replace(/\n/g, '').trim()
  if (!BASE64.test(body) || body.length % 4 !== 0) {
    return 'is not base64 once the PEM header and line breaks are removed'
  }
  const der = Buffer.from(body, 'base64')
  if (der.length < 64 || der[0] !== DER_SEQUENCE) {
    return 'does not decode to a DER-encoded RSA public key'
  }
  return null
}

// CLI entry — run directly (not when imported).
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const problem = publicKeyProblem(process.env.SYNAPLAN_OTA_PUBLIC_KEY)
  if (problem) {
    console.error(
      `::error::CAPGO_BUNDLE_PUBLIC_KEY ${problem}. It must be an environment ` +
        'VARIABLE (not a secret) holding the PEM public key from `capgo key create`, ' +
        'otherwise the app cannot verify a signed bundle.'
    )
    process.exit(1)
  }
  console.log('[ota-key] the OTA verification key parses')
}
