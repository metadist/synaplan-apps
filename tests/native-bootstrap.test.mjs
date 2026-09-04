/*
 * Behavioral gate for the app-owned native bootstrap (app/synaplan-native.js).
 *
 * The bootstrap is the ONLY owner of the native launch screen: `launchAutoHide`
 * is false and the updater's `autoSplashscreen` is deliberately unused, because
 * that option hides the splash only after the OTA update check has returned. On a
 * cold start the plugin never arms its own timeout, so a slow update server left
 * the launch screen up for the whole check (~20s) while the SPA behind it was
 * already interactive.
 *
 * These tests run the real bootstrap source in a `node:vm` context against a
 * hand-rolled DOM stub (no jsdom, no new dependency) and pin the two guarantees
 * that keep that regression from coming back: hide on the SPA's first paint, and
 * hide at the ceiling no matter what else fails.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { runInNewContext } from 'node:vm'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SOURCE = readFileSync(join(ROOT, 'app', 'synaplan-native.js'), 'utf-8')

// The shell appends this token to the WebView user agent; the bootstrap must be a
// complete no-op without it (plain web deployment).
const NATIVE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) Safari Synaplan Mobile V4.0'
const WEB_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) Safari'

const SPLASH_CEILING_MS = 5000
const OVERLAY_ID = 'synaplan-server-overlay'

class StubElement {
  constructor(tagName, onMutation) {
    this.tagName = String(tagName).toUpperCase()
    this.children = []
    this.attributes = {}
    this.style = { setProperty() {} }
    this.textContent = ''
    this.parentNode = null
    this.onMutation = onMutation
  }

  get firstElementChild() {
    return this.children.length > 0 ? this.children[0] : null
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value)
  }

  getAttribute(name) {
    return name in this.attributes ? this.attributes[name] : null
  }

  appendChild(child) {
    child.parentNode = this
    this.children.push(child)
    this.onMutation()
    return child
  }

  removeChild(child) {
    const index = this.children.indexOf(child)
    if (index >= 0) this.children.splice(index, 1)
    child.parentNode = null
    this.onMutation()
    return child
  }

  addEventListener() {}
  removeEventListener() {}
  focus() {}

  querySelectorAll() {
    return []
  }
}

function findById(node, id) {
  if (node.attributes && node.attributes.id === id) return node
  for (const child of node.children) {
    const hit = findById(child, id)
    if (hit) return hit
  }
  return null
}

/**
 * Builds a minimal browser-ish environment with a controllable clock and loads
 * the bootstrap into it. `requestAnimationFrame` is modelled as a 0ms timer, so
 * `advance(0)` flushes a pending frame.
 */
function loadBootstrap(options = {}) {
  const userAgent = 'userAgent' in options ? options.userAgent : NATIVE_UA
  // Default: a probe that never settles, so the recovery overlay stays out of the
  // way of the splash assertions.
  const fetchImpl = options.fetch || (() => new Promise(() => {}))

  const mutationListeners = []
  const notifyMutation = () => {
    for (const listener of mutationListeners.slice()) listener()
  }
  const make = (tagName) => new StubElement(tagName, notifyMutation)

  // Wired up directly instead of via appendChild so the initial tree does not
  // emit mutations before the bootstrap even runs.
  const documentElement = make('html')
  const head = make('head')
  const body = make('body')
  const appRoot = make('div')
  appRoot.setAttribute('id', 'app')
  documentElement.children.push(head, body)
  head.parentNode = documentElement
  body.parentNode = documentElement
  body.children.push(appRoot)
  appRoot.parentNode = body

  let clock = 0
  let nextTimerId = 1
  const timers = new Map()

  const setTimeoutStub = (fn, delay) => {
    const id = nextTimerId++
    const ms = Number(delay) || 0
    timers.set(id, { at: clock + ms, delay: ms, fn })
    return id
  }
  const clearTimeoutStub = (id) => {
    timers.delete(id)
  }
  const advance = (ms) => {
    const target = clock + ms
    for (;;) {
      let dueId = null
      let due = null
      for (const [id, timer] of timers) {
        if (timer.at <= target && (due === null || timer.at < due.at)) {
          dueId = id
          due = timer
        }
      }
      if (due === null) break
      timers.delete(dueId)
      clock = due.at
      due.fn()
    }
    clock = target
  }

  class StubMutationObserver {
    constructor(callback) {
      if (options.breakMutationObserver === true) {
        throw new Error('MutationObserver unavailable')
      }
      this.callback = callback
      this.listener = () => this.callback([], this)
    }

    observe() {
      mutationListeners.push(this.listener)
    }

    disconnect() {
      const index = mutationListeners.indexOf(this.listener)
      if (index >= 0) mutationListeners.splice(index, 1)
    }
  }

  class StubAbortController {
    constructor() {
      this.signal = { aborted: false }
    }

    abort() {
      this.signal.aborted = true
    }
  }

  const hideCalls = []
  const splashScreen = {
    hide(opts) {
      hideCalls.push(opts || {})
      return Promise.resolve()
    },
  }

  const storage = new Map()
  const domReadyListeners = []

  const windowStub = {
    navigator: { userAgent },
    localStorage: {
      getItem: (key) => (storage.has(key) ? storage.get(key) : null),
      setItem: (key, value) => storage.set(key, String(value)),
      removeItem: (key) => storage.delete(key),
    },
    Capacitor: {
      Plugins: Object.assign(
        options.withoutSplashPlugin === true ? {} : { SplashScreen: splashScreen },
        options.extraPlugins || {}
      ),
    },
    location: { reload() {} },
    requestAnimationFrame: (fn) => setTimeoutStub(fn, 0),
    dispatchEvent() {},
    addEventListener() {},
  }

  const documentStub = {
    readyState: 'loading',
    documentElement,
    head,
    body,
    createElement: (tagName) => make(tagName),
    getElementById: (id) => findById(documentElement, id),
    querySelectorAll: (selector) => {
      if (selector !== 'meta[name="viewport"]') return []
      return head.children.filter(
        (child) => child.tagName === 'META' && child.getAttribute('name') === 'viewport'
      )
    },
    addEventListener: (type, listener) => {
      if (type === 'DOMContentLoaded') domReadyListeners.push(listener)
    },
    removeEventListener() {},
  }

  runInNewContext(SOURCE, {
    window: windowStub,
    navigator: windowStub.navigator,
    document: documentStub,
    setTimeout: setTimeoutStub,
    clearTimeout: clearTimeoutStub,
    MutationObserver: StubMutationObserver,
    AbortController: StubAbortController,
    CustomEvent: class {
      constructor(type, init) {
        this.type = type
        this.detail = init && init.detail
      }
    },
    URL,
    fetch: fetchImpl,
    Promise,
    console,
  })

  return {
    hideCalls,
    document: documentStub,
    window: windowStub,
    advance,
    pendingDelays: () => [...timers.values()].map((timer) => timer.delay).sort((a, b) => a - b),
    domReadyListenerCount: () => domReadyListeners.length,
    fireDomContentLoaded: () => {
      documentStub.readyState = 'interactive'
      for (const listener of domReadyListeners.slice()) listener()
    },
    // What the SPA does at the end of bootstrap: mount its root into #app.
    paintApp: () => appRoot.appendChild(make('div')),
    viewportContent: () => {
      const metas = documentStub.querySelectorAll('meta[name="viewport"]')
      return metas.length > 0 ? metas[0].getAttribute('content') : null
    },
    flushMicrotasks: async () => {
      for (let i = 0; i < 10; i += 1) {
        await new Promise((resolve) => setImmediate(resolve))
      }
    },
  }
}

test('splash ceiling is armed synchronously, before any DOM-ready initialization', () => {
  const env = loadBootstrap()

  // Only the ceiling exists at this point — the server probe and everything else
  // runs on DOMContentLoaded, so a failure there cannot swallow the guarantee.
  assert.deepEqual(env.pendingDelays(), [SPLASH_CEILING_MS])
  assert.equal(env.domReadyListenerCount(), 1)
  assert.equal(env.hideCalls.length, 0)
})

test('splash is hidden on the first paint of the SPA', () => {
  const env = loadBootstrap()
  env.fireDomContentLoaded()
  assert.equal(env.hideCalls.length, 0)

  env.paintApp()
  // One frame of grace so the painted frame is on screen before the fade-out.
  assert.equal(env.hideCalls.length, 0)
  env.advance(0)

  assert.equal(env.hideCalls.length, 1)
  assert.equal(env.hideCalls[0].fadeOutDuration, 200)
})

test('splash is hidden at the ceiling when the SPA never paints', () => {
  const env = loadBootstrap()
  env.fireDomContentLoaded()

  env.advance(SPLASH_CEILING_MS - 1)
  assert.equal(env.hideCalls.length, 0)

  env.advance(1)
  assert.equal(env.hideCalls.length, 1)
})

test('splash is hidden at the ceiling even when the paint watch cannot be installed', () => {
  const env = loadBootstrap({ breakMutationObserver: true })
  env.fireDomContentLoaded()

  env.advance(SPLASH_CEILING_MS)
  assert.equal(env.hideCalls.length, 1)
  // A failing paint watch must not take the rest of the bootstrap with it.
  assert.match(env.viewportContent(), /user-scalable=no/)
})

test('splash is hidden when the recovery overlay opens for an unreachable server', async () => {
  const env = loadBootstrap({ fetch: () => Promise.reject(new Error('offline')) })
  env.fireDomContentLoaded()
  await env.flushMicrotasks()

  assert.ok(env.document.getElementById(OVERLAY_ID), 'recovery overlay should be mounted')
  assert.equal(env.hideCalls.length, 1)

  // Idempotent: the ceiling firing afterwards must not hide a second time.
  env.advance(SPLASH_CEILING_MS)
  assert.equal(env.hideCalls.length, 1)
})

test('splash handling is a no-op on the plain web deployment', () => {
  const env = loadBootstrap({ userAgent: WEB_UA })

  assert.deepEqual(env.pendingDelays(), [])
  assert.equal(env.domReadyListenerCount(), 0)

  env.fireDomContentLoaded()
  env.paintApp()
  env.advance(60000)
  assert.equal(env.hideCalls.length, 0)
})

test('a shell without the SplashScreen plugin is tolerated', () => {
  const env = loadBootstrap({ withoutSplashPlugin: true })
  env.fireDomContentLoaded()

  env.paintApp()
  env.advance(SPLASH_CEILING_MS)
  assert.equal(env.hideCalls.length, 0)
})

test('Shortcuts and Camera bridges are exposed on the native shell', () => {
  const env = loadBootstrap()
  assert.equal(typeof env.window.SynaplanShortcuts.consumePending, 'function')
  assert.equal(typeof env.window.SynaplanShortcuts.subscribe, 'function')
  assert.equal(typeof env.window.SynaplanCamera.isAvailable, 'function')
  assert.equal(typeof env.window.SynaplanCamera.capturePhoto, 'function')
  assert.equal(env.window.SynaplanCamera.isAvailable(), false)
})

test('consumePending returns the native store action and skips a later duplicate token', async () => {
  const env = loadBootstrap({
    extraPlugins: {
      SynaplanShortcuts: {
        consumePendingAction: () => Promise.resolve({ action: 'dictate', token: 't-1' }),
        addListener() {},
      },
    },
  })
  env.fireDomContentLoaded()

  const first = await env.window.SynaplanShortcuts.consumePending()
  assert.equal(first.length, 1)
  assert.equal(first[0].action, 'dictate')
  assert.equal(first[0].token, 't-1')

  const second = await env.window.SynaplanShortcuts.consumePending()
  assert.equal(second.length, 0)
})

test('subscribe flushes buffered plugin events and consumePending de-duplicates them', async () => {
  let listener = null
  const env = loadBootstrap({
    extraPlugins: {
      SynaplanShortcuts: {
        consumePendingAction: () => Promise.resolve({ action: 'dictate', token: 't-live' }),
        addListener(_name, fn) {
          listener = fn
        },
      },
    },
  })
  env.fireDomContentLoaded()
  assert.equal(typeof listener, 'function')

  listener({ action: 'dictate', token: 't-live' })

  const seen = []
  env.window.SynaplanShortcuts.subscribe((payload) => {
    seen.push(payload)
  })
  assert.equal(seen.length, 1)
  assert.equal(seen[0].action, 'dictate')
  assert.equal(seen[0].token, 't-live')

  const pending = await env.window.SynaplanShortcuts.consumePending()
  assert.equal(pending.length, 0)
})

test('capturePhoto falls back to the photo library when the camera is unavailable', async () => {
  const sources = []
  const env = loadBootstrap({
    extraPlugins: {
      Camera: {
        getPhoto(opts) {
          sources.push(opts.source)
          if (opts.source === 'CAMERA') {
            return Promise.reject(new Error('no camera'))
          }
          return Promise.resolve({
            dataUrl: 'data:image/jpeg;base64,abc',
            format: 'jpeg',
          })
        },
      },
    },
  })

  assert.equal(env.window.SynaplanCamera.isAvailable(), true)
  const photo = await env.window.SynaplanCamera.capturePhoto()
  assert.deepEqual(sources, ['CAMERA', 'PHOTOS'])
  assert.equal(photo.mimeType, 'image/jpeg')
  assert.match(photo.fileName, /^photo-\d+\.jpg$/)
  assert.equal(photo.dataUrl, 'data:image/jpeg;base64,abc')
})
