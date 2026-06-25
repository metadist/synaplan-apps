/*
 * Gate 3 (parse/validate) for the native manifests. Dependency-free: Node's test
 * runner + a tiny XML well-formedness check. Catches the store-fatal breakages
 * early — a missing iOS purpose string crashes/rejects, a dropped Android
 * permission silently disables a feature, and a broken plist fails upload.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

import { assertWellFormed } from '../scripts/xml-wellformed.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (rel) => readFileSync(join(ROOT, rel), 'utf-8')

const INFO_PLIST = 'ios/App/App/Info.plist'
const PRIVACY = 'ios/App/App/PrivacyInfo.xcprivacy'
const ANDROID_MANIFEST = 'android/app/src/main/AndroidManifest.xml'

// ── iOS Info.plist ───────────────────────────────────────────────────────────

test('Info.plist is well-formed XML', () => {
  assertWellFormed(read(INFO_PLIST), 'Info.plist')
})

test('Info.plist declares every permission purpose string (missing → crash/reject)', () => {
  const plist = read(INFO_PLIST)
  const required = [
    'NSCameraUsageDescription',
    'NSMicrophoneUsageDescription',
    'NSPhotoLibraryUsageDescription',
    'NSPhotoLibraryAddUsageDescription',
    'NSFaceIDUsageDescription',
  ]
  for (const key of required) {
    const m = plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`))
    assert.ok(m, `Info.plist missing <key>${key}</key>`)
    assert.ok(m[1].trim().length > 0, `Info.plist ${key} purpose string is empty`)
  }
})

test('Info.plist keeps the Epic 10.1 build-setting variables (version/bundle id wiring)', () => {
  const plist = read(INFO_PLIST)
  assert.match(
    plist,
    /<key>CFBundleIdentifier<\/key>\s*<string>\$\(PRODUCT_BUNDLE_IDENTIFIER\)<\/string>/
  )
  assert.match(
    plist,
    /<key>CFBundleShortVersionString<\/key>\s*<string>\$\(MARKETING_VERSION\)<\/string>/
  )
  assert.match(
    plist,
    /<key>CFBundleVersion<\/key>\s*<string>\$\(CURRENT_PROJECT_VERSION\)<\/string>/
  )
  assert.match(plist, /<key>CFBundleDisplayName<\/key>\s*<string>[^<]+<\/string>/)
})

test('Info.plist keeps the OAuth deep-link scheme (Epic 3)', () => {
  assert.match(read(INFO_PLIST), /<string>com\.synaplan\.app<\/string>/)
})

// ── iOS privacy manifest (Epic 9.2) ──────────────────────────────────────────

test('PrivacyInfo.xcprivacy is well-formed XML', () => {
  assertWellFormed(read(PRIVACY), 'PrivacyInfo.xcprivacy')
})

test('PrivacyInfo.xcprivacy declares the required-reason API structure', () => {
  const p = read(PRIVACY)
  for (const key of [
    'NSPrivacyTracking',
    'NSPrivacyCollectedDataTypes',
    'NSPrivacyAccessedAPITypes',
  ]) {
    assert.match(p, new RegExp(`<key>${key}</key>`), `PrivacyInfo missing <key>${key}</key>`)
  }
  // Every accessed-API entry must pair a type with at least one reason code.
  assert.match(p, /<key>NSPrivacyAccessedAPIType<\/key>/)
  assert.match(p, /<key>NSPrivacyAccessedAPITypeReasons<\/key>/)
})

// ── Android manifest ─────────────────────────────────────────────────────────

test('AndroidManifest.xml is well-formed XML', () => {
  assertWellFormed(read(ANDROID_MANIFEST), 'AndroidManifest.xml')
})

test('AndroidManifest declares the required permissions (Epic 7)', () => {
  const m = read(ANDROID_MANIFEST)
  for (const perm of [
    'android.permission.INTERNET',
    'android.permission.RECORD_AUDIO',
    'android.permission.CAMERA',
  ]) {
    assert.match(
      m,
      new RegExp(`<uses-permission android:name="${perm.replace(/\./g, '\\.')}"`),
      `missing ${perm}`
    )
  }
})

test('AndroidManifest uses the Epic 10.1 ${appLabel} placeholder (env-aware launcher name)', () => {
  const m = read(ANDROID_MANIFEST)
  const count = (m.match(/android:label="\$\{appLabel\}"/g) || []).length
  assert.ok(count >= 1, 'AndroidManifest should label the app via ${appLabel}')
  assert.doesNotMatch(
    m,
    /android:label="@string\/app_name"/,
    'app_name label should be replaced by ${appLabel}'
  )
})

test('AndroidManifest keeps the OAuth deep-link intent filter (Epic 3)', () => {
  assert.match(
    read(ANDROID_MANIFEST),
    /<data android:scheme="com\.synaplan\.app" android:host="oauth"\s*\/>/
  )
})

// ── well-formedness checker self-test (so the gate itself is trustworthy) ─────

test('assertWellFormed rejects unbalanced/mismatched XML', () => {
  assert.throws(() => assertWellFormed('<a><b></a></b>', 't'), /mismatched/)
  assert.throws(() => assertWellFormed('<a><b></b>', 't'), /unclosed/)
  assert.doesNotThrow(() => assertWellFormed('<a x="b>c"><b/></a>', 't'))
  assert.doesNotThrow(() => assertWellFormed('<?xml version="1.0"?><!-- c --><a/>', 't'))
})
