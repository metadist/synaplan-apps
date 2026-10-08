/*
 * Contract gate for the native CarPlay layer (ios/App/App/CarPlay).
 *
 * CarPlay runs without the WebView, so its Swift code re-implements a few
 * things the SPA owns: where the session lives in the Keychain, which
 * endpoints and fields it calls, and the User-Agent the backend requires
 * before it hands out Bearer tokens. Each test pins one of those against the
 * pinned `synaplan` submodule (or the installed plugin), so a pin bump that
 * moves any of them fails here instead of silently signing the car out.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (path) => readFileSync(join(ROOT, path), 'utf-8')

const CARPLAY_DIR = 'ios/App/App/CarPlay'
const SWIFT_CONTRACT = read(`${CARPLAY_DIR}/CarSessionContract.swift`)
const SWIFT_MODELS = read(`${CARPLAY_DIR}/CarAPIModels.swift`)
const SWIFT_CLIENT = read(`${CARPLAY_DIR}/SynaplanCarClient.swift`)
const SWIFT_PARSER = read(`${CARPLAY_DIR}/SynaplanStreamParser.swift`)
const SWIFT_TESTS = read('ios/CarPlayLogic/Tests/CarPlayLogicTests/CarPlayLogicTests.swift')

const NATIVE_AUTH = read('synaplan/frontend/src/services/api/nativeAuth.ts')
const NATIVE_RUNTIME = read('synaplan/frontend/src/services/api/nativeRuntime.ts')
const API_SCHEMAS = read('synaplan/frontend/src/generated/api-schemas.ts')
const STREAM_CONTROLLER = read('synaplan/backend/src/Controller/StreamController.php')
const AUTH_CONTROLLER = read('synaplan/backend/src/Controller/AuthController.php')
const CHAT_CONTROLLER = read('synaplan/backend/src/Controller/ChatController.php')
const MESSAGE_CONTROLLER = read('synaplan/backend/src/Controller/MessageController.php')
const CLIENT_CONTEXT = read('synaplan/backend/src/Service/Client/ClientContextResolver.php')

/** The SPA's `serverScope()` algorithm, reimplemented exactly. */
function djb2Scope(url) {
  let hash = 5381
  for (let i = 0; i < url.length; i++) {
    hash = ((hash << 5) + hash + url.charCodeAt(i)) | 0
  }
  return (hash >>> 0).toString(36)
}

/** Body of a generated zod schema constant, up to the next export. */
function schemaBody(name) {
  const start = API_SCHEMAS.indexOf(`export const ${name} = `)
  assert.notEqual(start, -1, `${name} missing from the generated OpenAPI schemas`)
  const end = API_SCHEMAS.indexOf('\nexport const ', start + 1)
  return API_SCHEMAS.slice(start, end === -1 ? undefined : end)
}

test('SPA session keys are still djb2-scoped secure-storage items', () => {
  assert.match(NATIVE_AUTH, /let hash = 5381/)
  assert.match(NATIVE_AUTH, /hash = \(\(hash << 5\) \+ hash \+ url\.charCodeAt\(i\)\) \| 0/)
  assert.match(NATIVE_AUTH, /return \(hash >>> 0\)\.toString\(36\)/)
  assert.match(NATIVE_AUTH, /const url = getNativeApiBaseUrl\(\)/)
  assert.match(NATIVE_AUTH, /`syn_native_at_\$\{serverScope\(\)\}`/)
  assert.match(NATIVE_AUTH, /`syn_native_rt_\$\{serverScope\(\)\}`/)
  assert.match(NATIVE_AUTH, /SecureStorage\.setItem\(key, value\)/)

  assert.match(SWIFT_CONTRACT, /var hash: Int32 = 5381/)
  assert.match(SWIFT_CONTRACT, /"syn_native_at_"/)
  assert.match(SWIFT_CONTRACT, /"syn_native_rt_"/)
})

test('secure-storage key prefix matches the installed plugin', () => {
  const base = read('node_modules/@aparajita/capacitor-secure-storage/dist/esm/base.js')
  const prefix = base.match(/this\.prefix = '([^']+)'/)
  assert.ok(prefix, 'plugin default prefix not found')
  assert.match(SWIFT_CONTRACT, new RegExp(`secureStoragePrefix = "${prefix[1]}"`))
  assert.doesNotMatch(NATIVE_AUTH, /setKeyPrefix/, 'the SPA must keep the default prefix')
})

test('server URL normalization and default match getNativeApiBaseUrl()', () => {
  assert.match(NATIVE_RUNTIME, /return override\.trim\(\)\.replace\(\/\\\/\$\/, ''\)/)
  const fallback = NATIVE_RUNTIME.match(/DEFAULT_NATIVE_API_BASE_URL = '([^']+)'/)
  assert.ok(fallback)
  assert.match(SWIFT_CONTRACT, new RegExp(`defaultServerUrl = "${fallback[1]}"`))
})

test('Swift djb2 reference vectors equal the SPA algorithm', () => {
  const vectors = [...SWIFT_TESTS.matchAll(/serverScope\(for: "([^"]+)"\), "([0-9a-z]+)"\)/g)].map(
    (match) => ({ url: match[1], scope: match[2] })
  )
  assert.ok(vectors.length >= 3, 'expected djb2 vectors in CarPlayLogicTests.swift')
  for (const { url, scope } of vectors) {
    assert.equal(djb2Scope(url), scope, url)
  }
})

test('CarPlay User-Agent satisfies the backend token gate', () => {
  const pattern = CLIENT_CONTEXT.match(/UA_PATTERN = '\/(.+)\/';/)
  assert.ok(pattern, 'UA_PATTERN not found')
  const regex = new RegExp(pattern[1])
  assert.match(SWIFT_MODELS, /"Synaplan Mobile V\\\(major\)\.\\\(minor\) CarPlay"/)
  for (const sample of ['Synaplan Mobile V4.0 CarPlay', 'Synaplan Mobile V1.0 CarPlay']) {
    assert.match(sample, regex)
  }
})

test('chat list and create responses carry the fields the car reads', () => {
  const list = schemaBody('get_api_chats_list_Response')
  for (const field of [
    'chats:',
    'id: z.number().int()',
    'title: z.string()',
    'updatedAt:',
    'widgetSession:',
    'source:',
  ]) {
    assert.ok(list.includes(field), `chat list lost ${field}`)
  }
  const create = schemaBody('post_api_chats_create_Response')
  assert.ok(create.includes('chat:') && create.includes('id: z.number().int()'))

  assert.match(SWIFT_MODELS, /object\["chats"\]/)
  assert.match(SWIFT_MODELS, /chat\["widgetSession"\]/)
  assert.match(SWIFT_MODELS, /chat\["source"\]/)
  assert.match(CHAT_CONTROLLER, /'source' => \$chat->getSource\(\),/)
  assert.match(SWIFT_CLIENT, /"\/api\/v1\/chats"/)
})

test('message stream request and SSE envelope are unchanged', () => {
  for (const property of [
    "property: 'message'",
    "property: 'chatId', type: 'string'",
    "property: 'language'",
  ]) {
    assert.ok(STREAM_CONTROLLER.includes(property), `stream body lost ${property}`)
  }
  assert.match(STREAM_CONTROLLER, /path: '\/api\/v1\/messages\/stream'/)
  assert.match(STREAM_CONTROLLER, /'status' => \$status,/)
  assert.match(STREAM_CONTROLLER, /sendSSE\('data', \['chunk' => /)
  assert.match(STREAM_CONTROLLER, /sendSSE\('complete', /)
  assert.match(STREAM_CONTROLLER, /sendSSE\('error', /)
  assert.match(STREAM_CONTROLLER, /sendSSE\('message', \$rateLimitError\)/)

  for (const status of ['"data"', '"complete"', '"error"', '"message"']) {
    assert.ok(SWIFT_PARSER.includes(`case ${status}:`), `parser no longer handles ${status}`)
  }
  assert.match(SWIFT_PARSER, /object\["chunk"\]/)
})

test('refresh, dictation, TTS and runtime config contracts', () => {
  assert.match(AUTH_CONTROLLER, /'accessToken' => \$accessToken,/)
  assert.match(SWIFT_MODELS, /object\["tokens"\]/)
  assert.match(SWIFT_MODELS, /tokens\["accessToken"\]/)
  assert.match(SWIFT_CLIENT, /"refreshToken": session\.refreshToken/)

  assert.match(
    MESSAGE_CONTROLLER,
    /'dictation' === \(string\) \$request->request->get\('purpose'\)/
  )
  assert.match(MESSAGE_CONTROLLER, /\$response\['text'\] = /)
  assert.match(SWIFT_CLIENT, /field\("purpose", "dictation"\)/)

  assert.match(read('synaplan/backend/src/Controller/TtsController.php'), /#\[Route\('\/stream'/)
  assert.match(SWIFT_CLIENT, /"\/api\/v1\/tts\/stream"/)

  assert.ok(API_SCHEMAS.includes('speechToTextAvailable: z.boolean()'))
  assert.match(SWIFT_MODELS, /speech\["speechToTextAvailable"\]/)
})

test('CarPlay copy exists in all five locales', () => {
  const catalog = JSON.parse(read(`${CARPLAY_DIR}/CarPlay.xcstrings`))
  assert.equal(catalog.sourceLanguage, 'en')
  const locales = ['de', 'en', 'es', 'fr', 'tr']
  for (const [key, entry] of Object.entries(catalog.strings)) {
    for (const locale of locales) {
      const unit = entry.localizations?.[locale]?.stringUnit
      assert.ok(
        unit && unit.state === 'translated' && unit.value.trim() !== '',
        `${key} [${locale}]`
      )
    }
  }

  const sources = readdirSync(join(ROOT, CARPLAY_DIR))
    .filter((name) => name.endsWith('.swift'))
    .map((name) => read(`${CARPLAY_DIR}/${name}`))
    .join('\n')
  const used = new Set(
    [...sources.matchAll(/"((?:root|voice|button|alert|error)\.[A-Za-z]+)"/g)].map((m) => m[1])
  )
  for (const key of used) {
    assert.ok(key in catalog.strings, `CarPlay.xcstrings is missing ${key}`)
  }
})

test('CarPlay copy never asks the driver to use the iPhone', () => {
  const catalog = JSON.parse(read(`${CARPLAY_DIR}/CarPlay.xcstrings`))
  const instruction = /\b(sign in to|log in|open|settings|iphone|phone)\b/i
  for (const [key, entry] of Object.entries(catalog.strings)) {
    const english = entry.localizations.en.stringUnit.value
    assert.doesNotMatch(english, instruction, `${key}: "${english}"`)
  }
})
