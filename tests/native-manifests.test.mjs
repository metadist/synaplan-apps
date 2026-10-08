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
    'NSSpeechRecognitionUsageDescription',
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

test('Info.plist uses the scene lifecycle with separate phone and CarPlay roles', () => {
  const plist = read(INFO_PLIST)
  assert.doesNotMatch(plist, /<key>UIMainStoryboardFile<\/key>/, 'storyboard moves into the scene')
  assert.match(plist, /<key>UIApplicationSceneManifest<\/key>/)
  assert.match(plist, /<key>UIApplicationSupportsMultipleScenes<\/key>\s*<false\/>/)
  assert.match(
    plist,
    /<key>UIWindowSceneSessionRoleApplication<\/key>[\s\S]*?<string>\$\(PRODUCT_MODULE_NAME\)\.SceneDelegate<\/string>[\s\S]*?<key>UISceneStoryboardFile<\/key>\s*<string>Main<\/string>/
  )
  assert.match(
    plist,
    /<key>CPTemplateApplicationSceneSessionRoleApplication<\/key>[\s\S]*?<string>CPTemplateApplicationScene<\/string>[\s\S]*?<string>\$\(PRODUCT_MODULE_NAME\)\.CarPlaySceneDelegate<\/string>/
  )
})

// ── iOS entitlements ─────────────────────────────────────────────────────────

const CARPLAY_ENTITLEMENT = 'com.apple.developer.carplay-voice-based-conversation'

test('CarPlay entitlement is limited to Simulator builds until Apple grants it', () => {
  const device = read('ios/App/App/App.entitlements')
  const simulator = read('ios/App/App/App-CarPlay.entitlements')
  assertWellFormed(device, 'App.entitlements')
  assertWellFormed(simulator, 'App-CarPlay.entitlements')

  // A device/archive build with an ungranted entitlement fails provisioning.
  assert.doesNotMatch(device, new RegExp(CARPLAY_ENTITLEMENT))
  assert.match(simulator, new RegExp(`<key>${CARPLAY_ENTITLEMENT}</key>\\s*<true/>`))
  // Everything the device build has, the Simulator build keeps.
  for (const key of device.matchAll(/<key>([^<]+)<\/key>/g)) {
    assert.match(simulator, new RegExp(`<key>${key[1]}</key>`), `simulator lost ${key[1]}`)
  }

  const pbx = read('ios/App/App.xcodeproj/project.pbxproj')
  const sim = pbx.match(
    /"CODE_SIGN_ENTITLEMENTS\[sdk=iphonesimulator\*\]" = "App\/App-CarPlay\.entitlements";/g
  )
  const base = pbx.match(/\bCODE_SIGN_ENTITLEMENTS = App\/App\.entitlements;/g)
  assert.equal(sim?.length, 2, 'Debug and Release simulator overrides')
  assert.equal(base?.length, 2, 'Debug and Release device entitlements')
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
