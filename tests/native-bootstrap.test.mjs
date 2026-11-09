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
    this.styleProps = {}
    this.style = {
      setProperty: (name, value) => {
        this.styleProps[name] = String(value)
      },
    }
    this.textContent = ''
    this.parentNode = null
    this.onMutation = onMutation
    this._classes = new Set()
    this.classList = {
      add: (name) => this._classes.add(name),
      remove: (name) => this._classes.delete(name),
      contains: (name) => this._classes.has(name),
      toggle: (name, force) => {
        if (force === true) this._classes.add(name)
        else if (force === false) this._classes.delete(name)
        else if (this._classes.has(name)) this._classes.delete(name)
        else this._classes.add(name)
        return this._classes.has(name)
      },
    }
  }

  get firstElementChild() {
    return this.children.length > 0 ? this.children[0] : null
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value)
    this.onMutation()
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

  const storage = new Map(Object.entries(options.storage || {}))
  const domReadyListeners = []
  const visibilityListeners = []

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
    location: {
      reload() {},
      protocol: options.protocol || '',
      hostname: options.hostname || '',
      port: options.port || '',
    },
    requestAnimationFrame: (fn) => setTimeoutStub(fn, 0),
    dispatchEvent() {},
    addEventListener() {},
    innerHeight: options.innerHeight || 800,
  }

  const documentStub = {
    readyState: 'loading',
    visibilityState: 'visible',
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
      if (type === 'visibilitychange') visibilityListeners.push(listener)
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
    setVisibility: (state) => {
      documentStub.visibilityState = state
      for (const listener of visibilityListeners.slice()) listener()
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

test('a Capacitor origin without the user-agent marker still publishes the configured server', () => {
  const env = loadBootstrap({
    userAgent: WEB_UA,
    protocol: 'capacitor:',
    hostname: 'localhost',
    storage: { 'synaplan.serverUrl': 'https://chat.example.test/' },
  })

  assert.equal(env.window.__SYNAPLAN_API_BASE_URL__, 'https://chat.example.test')
})

test('an ionic origin without the user-agent marker publishes the configured server', () => {
  const env = loadBootstrap({
    userAgent: WEB_UA,
    protocol: 'ionic:',
    hostname: 'localhost',
    storage: { 'synaplan.serverUrl': 'https://chat.example.test/' },
  })

  assert.equal(env.window.__SYNAPLAN_API_BASE_URL__, 'https://chat.example.test')
})

test('Android https://localhost without a port publishes the configured server', () => {
  const env = loadBootstrap({
    userAgent: WEB_UA,
    protocol: 'https:',
    hostname: 'localhost',
    port: '',
    storage: { 'synaplan.serverUrl': 'https://chat.example.test/' },
  })

  assert.equal(env.window.__SYNAPLAN_API_BASE_URL__, 'https://chat.example.test')
})

test('localhost with a port is not treated as the native shell', () => {
  for (const location of [
    { protocol: 'https:', hostname: 'localhost', port: '5173' },
    { protocol: 'http:', hostname: 'localhost', port: '5173' },
    { protocol: 'http:', hostname: 'localhost', port: '' },
  ]) {
    const env = loadBootstrap({
      userAgent: WEB_UA,
      protocol: location.protocol,
      hostname: location.hostname,
      port: location.port,
      storage: { 'synaplan.serverUrl': 'https://chat.example.test/' },
    })

    assert.equal(
      env.window.__SYNAPLAN_API_BASE_URL__,
      undefined,
      `${location.protocol}//${location.hostname}:${location.port} must stay a no-op`
    )
  }
})

test('the plain web deployment does not publish a server URL', () => {
  const env = loadBootstrap({
    userAgent: WEB_UA,
    storage: { 'synaplan.serverUrl': 'https://chat.example.test' },
  })

  assert.equal(env.window.__SYNAPLAN_API_BASE_URL__, undefined)
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

// ── First launch of a binary: a pending OTA bundle is applied under the splash ──

const OTA_CHECK_MS = 4000
const OTA_APPLY_MS = 12000
const OTA_SEEN_KEY = 'synaplan.ota.nativeSeen'

/**
 * A stand-in for the Capgo updater in `atBackground` mode: `current()` reports
 * the loaded bundle, events are pushed by the test, `reload()` is recorded.
 * `getLatest()` models the update server and does not answer unless told to
 * (a slow server); `next` may be a value or a function read on every poll.
 */
function fakeUpdater({
  bundleId = 'builtin',
  native = '5.7.1',
  next = null,
  reload,
  latest = () => new Promise(() => {}),
} = {}) {
  const listeners = {}
  const reloads = []
  const latestCalls = []
  return {
    reloads,
    latestCalls,
    emit: (name, data) => {
      for (const listener of listeners[name] || []) listener(data || {})
    },
    plugin: {
      current: () => Promise.resolve({ bundle: { id: bundleId }, native }),
      // `next(id)` is the setter in the Capgo API; the pending bundle is read
      // through getNextBundle(). The setter is present to catch a mix-up.
      next: () => Promise.reject(new Error('Next called without id')),
      getNextBundle: () => Promise.resolve(typeof next === 'function' ? next() : next),
      getLatest: () => {
        latestCalls.push(Date.now())
        return latest()
      },
      addListener: (name, listener) => {
        ;(listeners[name] = listeners[name] || []).push(listener)
        return Promise.resolve({ remove() {} })
      },
      reload: () => {
        reloads.push(Date.now())
        return reload ? reload() : new Promise(() => {})
      },
    },
  }
}

function loadFirstLaunch(updaterOptions = {}, options = {}) {
  const updater = fakeUpdater(updaterOptions)
  const env = loadBootstrap({ extraPlugins: { CapacitorUpdater: updater.plugin }, ...options })
  env.fireDomContentLoaded()
  return { env, updater }
}

test('first launch holds the splash past the first paint until the updater answers', async () => {
  const { env, updater } = loadFirstLaunch()
  await env.flushMicrotasks()

  env.paintApp()
  env.advance(0)
  assert.equal(env.hideCalls.length, 0, 'the stale builtin SPA must stay under the splash')
  assert.equal(env.window.localStorage.getItem(OTA_SEEN_KEY), '5.7.1')

  updater.emit('noNeedUpdate')
  assert.equal(env.hideCalls.length, 1)
  assert.equal(updater.reloads.length, 0)
})

test('first launch applies the downloaded bundle before the splash comes down', async () => {
  const { env, updater } = loadFirstLaunch()
  await env.flushMicrotasks()
  env.paintApp()
  env.advance(0)

  updater.emit('download', { percent: 40 })
  env.advance(OTA_CHECK_MS)
  assert.equal(env.hideCalls.length, 0, 'a running download extends the hold')

  updater.emit('updateAvailable', { bundle: { id: 'ota-1' } })
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 1)
  // reload() never settles: the JavaScript context is gone and the new
  // bundle's bootstrap hides the splash after its own first paint.
  env.advance(OTA_APPLY_MS)
  assert.equal(env.hideCalls.length, 0)
})

test('a bundle downloaded before the listener was registered is applied too', async () => {
  const { env, updater } = loadFirstLaunch({ next: { id: 'ota-1' } })
  await env.flushMicrotasks()

  assert.equal(updater.reloads.length, 1)
  assert.equal(env.hideCalls.length, 0)
})

test('a server that is already up to date ends the hold without waiting for the ceiling', async () => {
  const { env, updater } = loadFirstLaunch({
    latest: () =>
      Promise.resolve({ version: '5.7.1', kind: 'up_to_date', error: 'no_new_version_available' }),
  })
  await env.flushMicrotasks()
  assert.equal(updater.latestCalls.length, 1)

  env.paintApp()
  env.advance(0)
  assert.equal(env.hideCalls.length, 1, 'nothing is waiting, so the paint hides as usual')
  assert.equal(updater.reloads.length, 0)
})

test('an unreachable update server ends the hold without waiting for the ceiling', async () => {
  for (const latest of [
    () => Promise.reject(new Error('rate_limit_exceeded')),
    () => Promise.resolve({ version: '', error: 'no_channel' }),
    () => Promise.resolve({ version: '5.9.0', url: 'https://ota.example/b.zip', breaking: true }),
  ]) {
    const { env, updater } = loadFirstLaunch({ latest })
    await env.flushMicrotasks()

    env.paintApp()
    env.advance(0)
    assert.equal(env.hideCalls.length, 1)
    assert.equal(updater.reloads.length, 0)
  }
})

test('a newer bundle on the server extends the hold until it is pending, then applies it', async () => {
  let pending = null
  const { env, updater } = loadFirstLaunch({
    next: () => pending,
    latest: () => Promise.resolve({ version: '5.7.2', url: 'https://ota.example/b.zip' }),
  })
  await env.flushMicrotasks()
  env.paintApp()
  env.advance(0)

  // No `download` event reached us (the native download started before the
  // listener existed); the server's answer alone keeps the hold past the check ceiling.
  env.advance(OTA_CHECK_MS)
  await env.flushMicrotasks()
  assert.equal(env.hideCalls.length, 0)
  assert.equal(updater.reloads.length, 0)

  pending = { id: 'ota-2' }
  env.advance(500)
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 1)
  assert.equal(env.hideCalls.length, 0)
})

test('a newer bundle that never becomes pending releases at the apply ceiling', async () => {
  const { env, updater } = loadFirstLaunch({
    latest: () => Promise.resolve({ version: '5.7.2', url: 'https://ota.example/b.zip' }),
  })
  await env.flushMicrotasks()
  env.paintApp()
  env.advance(0)

  for (let elapsed = 0; elapsed < OTA_APPLY_MS; elapsed += 500) {
    env.advance(500)
    await env.flushMicrotasks()
  }
  assert.equal(env.hideCalls.length, 1)
  assert.equal(updater.reloads.length, 0)
  // Polling stops with the hold.
  const timersBefore = env.pendingDelays().length
  env.advance(5000)
  assert.equal(env.pendingDelays().length, timersBefore)
})

test('a failed reload hands over to the builtin bundle', async () => {
  const { env, updater } = loadFirstLaunch({
    next: { id: 'ota-1' },
    reload: () => Promise.reject(new Error('no index.html')),
  })
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 1)

  env.paintApp()
  env.advance(0)
  assert.equal(env.hideCalls.length, 1)
})

test('first launch gives up on a silent update check after the check ceiling', async () => {
  const { env, updater } = loadFirstLaunch()
  await env.flushMicrotasks()
  env.paintApp()
  env.advance(0)

  env.advance(OTA_CHECK_MS - 1)
  assert.equal(env.hideCalls.length, 0)
  env.advance(1)
  assert.equal(env.hideCalls.length, 1)

  // A download that completes later installs at the next background, as before.
  updater.emit('updateAvailable', { bundle: { id: 'ota-1' } })
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 0)
})

test('a slow download releases the splash at the apply ceiling and is not applied late', async () => {
  const { env, updater } = loadFirstLaunch()
  await env.flushMicrotasks()
  env.paintApp()
  env.advance(0)
  updater.emit('download', { percent: 5 })

  env.advance(OTA_APPLY_MS - 1)
  assert.equal(env.hideCalls.length, 0)
  env.advance(1)
  assert.equal(env.hideCalls.length, 1)

  updater.emit('updateAvailable', { bundle: { id: 'ota-1' } })
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 0)
})

test('the splash ceiling is deferred by a running download and restored when the hold ends', async () => {
  const { env, updater } = loadFirstLaunch()
  await env.flushMicrotasks()
  updater.emit('download', { percent: 10 })

  // The SPA never paints: the ordinary ceiling is deferred by the hold ...
  env.advance(SPLASH_CEILING_MS)
  assert.equal(env.hideCalls.length, 0, 'the hold defers the ceiling')
  // ... and the hold's own ceiling hides.
  env.advance(OTA_APPLY_MS - SPLASH_CEILING_MS)
  assert.equal(env.hideCalls.length, 1)
})

test('without a download the ordinary ceiling hides an SPA that never paints', async () => {
  const { env } = loadFirstLaunch()
  await env.flushMicrotasks()

  env.advance(OTA_CHECK_MS)
  assert.equal(env.hideCalls.length, 0)
  env.advance(SPLASH_CEILING_MS - OTA_CHECK_MS)
  assert.equal(env.hideCalls.length, 1)
})

test('a download failure releases the hold', async () => {
  for (const event of ['downloadFailed', 'updateFailed']) {
    const { env, updater } = loadFirstLaunch()
    await env.flushMicrotasks()
    env.paintApp()
    env.advance(0)
    updater.emit('download', { percent: 50 })

    updater.emit(event)
    assert.equal(env.hideCalls.length, 1, `${event} must hand over to the builtin bundle`)
    assert.equal(updater.reloads.length, 0)
  }
})

test('a later launch of the same binary hides on the first paint as usual', async () => {
  const { env, updater } = loadFirstLaunch({}, { storage: { [OTA_SEEN_KEY]: '5.7.1' } })
  await env.flushMicrotasks()

  env.paintApp()
  env.advance(0)
  assert.equal(env.hideCalls.length, 1)

  updater.emit('updateAvailable', { bundle: { id: 'ota-1' } })
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 0, 'a running launch is never reloaded')
})

test('a native update is a first launch again', async () => {
  const { env, updater } = loadFirstLaunch(
    { native: '5.8.0', next: { id: 'ota-2' } },
    { storage: { [OTA_SEEN_KEY]: '5.7.1' } }
  )
  await env.flushMicrotasks()

  assert.equal(updater.reloads.length, 1)
  assert.equal(env.window.localStorage.getItem(OTA_SEEN_KEY), '5.8.0')
})

test('a launch on an OTA bundle is never held, but remembers the native version', async () => {
  const { env, updater } = loadFirstLaunch({ bundleId: 'ota-1' })
  await env.flushMicrotasks()

  env.paintApp()
  env.advance(0)
  assert.equal(env.hideCalls.length, 1)
  assert.equal(env.window.localStorage.getItem(OTA_SEEN_KEY), '5.7.1')
  updater.emit('updateAvailable', { bundle: { id: 'ota-2' } })
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 0)
})

test('a ready bundle reported before current() answers is applied only once confirmed', async () => {
  let resolveCurrent
  const updater = fakeUpdater()
  updater.plugin.current = () =>
    new Promise((resolve) => {
      resolveCurrent = resolve
    })
  const env = loadBootstrap({ extraPlugins: { CapacitorUpdater: updater.plugin } })
  env.fireDomContentLoaded()

  updater.emit('updateAvailable', { bundle: { id: 'ota-1' } })
  assert.equal(updater.reloads.length, 0)

  resolveCurrent({ bundle: { id: 'builtin' }, native: '5.7.1' })
  await env.flushMicrotasks()
  assert.equal(updater.reloads.length, 1)
})

test('a failing current() hands over to the builtin bundle', async () => {
  const updater = fakeUpdater()
  updater.plugin.current = () => Promise.reject(new Error('bridge'))
  const env = loadBootstrap({ extraPlugins: { CapacitorUpdater: updater.plugin } })
  env.fireDomContentLoaded()
  await env.flushMicrotasks()

  env.paintApp()
  env.advance(0)
  assert.equal(env.hideCalls.length, 1)
})

test('a shell without the updater plugin hides on the first paint', () => {
  const env = loadBootstrap()
  env.fireDomContentLoaded()
  env.paintApp()
  env.advance(0)
  assert.equal(env.hideCalls.length, 1)
  assert.equal(env.window.localStorage.getItem(OTA_SEEN_KEY), null)
})

test('Shortcuts and Camera bridges are exposed on the native shell', () => {
  const env = loadBootstrap()
  assert.equal(typeof env.window.SynaplanShortcuts.consumePending, 'function')
  assert.equal(typeof env.window.SynaplanShortcuts.subscribe, 'function')
  assert.equal(typeof env.window.SynaplanCamera.isAvailable, 'function')
  assert.equal(typeof env.window.SynaplanCamera.capturePhoto, 'function')
  assert.equal(env.window.SynaplanCamera.isAvailable(), false)
  assert.equal(typeof env.window.SynaplanLiveVoice.isAvailable, 'function')
  assert.equal(env.window.SynaplanLiveVoice.isAvailable(), false)
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

test('live voice is available only when this binary registered the plugin', () => {
  const missing = loadBootstrap()
  assert.equal(missing.window.SynaplanLiveVoice.isAvailable(), false)

  const present = loadBootstrap({
    extraPlugins: {
      SynaplanLiveVoice: {
        isAvailable: () => Promise.resolve({ available: true }),
      },
    },
  })
  assert.equal(present.window.SynaplanLiveVoice.isAvailable(), true)

  const web = loadBootstrap({ userAgent: WEB_UA })
  assert.equal(web.window.SynaplanLiveVoice.isAvailable(), false)
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

test('keyboard inset ignores IME height already taken by a shrunk Android layout viewport', () => {
  const listeners = {}
  const env = loadBootstrap({
    extraPlugins: {
      Keyboard: {
        addListener(name, fn) {
          listeners[name] = fn
        },
      },
    },
  })
  env.fireDomContentLoaded()
  assert.equal(typeof listeners.keyboardWillShow, 'function')
  assert.equal(typeof listeners.keyboardDidShow, 'function')

  // iOS overlay: innerHeight stays put, so the full IME height is published.
  listeners.keyboardWillShow({ keyboardHeight: 400 })
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '400px')
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-open'), true)

  // Remainder after a partial shrink (IME includes system bars the WebView never
  // had) must not keep translating — that leftover is the small Samsung gap.
  env.window.innerHeight = 440
  listeners.keyboardDidShow({ keyboardHeight: 400 })
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '0px')
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-open'), true)

  listeners.keyboardWillHide()
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '0px')
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-open'), false)
})

test('keyboard inset keeps the overlay height when Samsung only pans the visual viewport', () => {
  const listeners = {}
  const env = loadBootstrap({
    extraPlugins: {
      Keyboard: {
        addListener(name, fn) {
          listeners[name] = fn
        },
      },
    },
  })
  env.fireDomContentLoaded()
  env.window.visualViewport = { offsetTop: 360, height: 440, addEventListener() {} }
  const events = []
  env.window.dispatchEvent = (event) => {
    events.push(event)
  }

  listeners.keyboardWillShow({ keyboardHeight: 400 })
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '400px')
  assert.equal(events.at(-1).detail.height, 400)
  assert.equal(events.at(-1).detail.keyboardHeight, 400)
  const style = env.document.getElementById('synaplan-keyboard-open-style')
  assert.equal(style.textContent.includes('scroll-margin-bottom'), true)
  assert.equal(style.textContent.includes('.chat-composer-sticky textarea'), true)

  // A real shrink still drops the CSS lift, but the SPA keeps the IME height.
  env.window.visualViewport = { offsetTop: 0, height: 800, addEventListener() {} }
  env.window.innerHeight = 440
  listeners.keyboardDidShow({ keyboardHeight: 400 })
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '0px')
  assert.equal(events.at(-1).detail.height, 0)
  assert.equal(events.at(-1).detail.keyboardHeight, 400)
})

test('chat keyboard dock follows live keyboard frames instead of easing to the final height', () => {
  const listeners = {}
  const enabled = []
  const env = loadBootstrap({
    extraPlugins: {
      Keyboard: {
        addListener(name, fn) {
          listeners[name] = fn
        },
      },
      SynaplanKeyboardDock: {
        setEnabled(options) {
          enabled.push(options.enabled)
          return Promise.resolve()
        },
      },
    },
  })
  env.fireDomContentLoaded()
  const events = []
  env.window.dispatchEvent = (event) => {
    events.push(event)
  }

  env.window.SynaplanChatKeyboard.setDocked(true)
  assert.deepEqual(enabled, [true])
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-dock'), true)

  // The show event carries the final height. Publishing it would jump the chat
  // to the top while the keyboard is still moving.
  listeners.keyboardWillShow({ keyboardHeight: 400 })
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], undefined)
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-open'), true)
  assert.equal(events.length, 0)

  env.window.__synaplanKeyboardFrame(120)
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '120px')
  assert.equal(events.length, 0)
  env.window.__synaplanKeyboardFrame(400)
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '400px')

  listeners.keyboardDidShow({ keyboardHeight: 400 })
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '400px')
  assert.equal(events.length, 0)

  env.window.SynaplanChatKeyboard.setDocked(false)
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '400px')
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-dock'), true)

  listeners.keyboardWillHide()
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '400px')
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-dock'), true)

  env.window.__synaplanKeyboardFrame(40)
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '40px')

  listeners.keyboardDidHide()
  assert.equal(env.document.documentElement.classList.contains('synaplan-keyboard-dock'), false)
  assert.equal(env.document.documentElement.styleProps['--keyboard-inset-height'], '0px')
})

test('CarPlay session bridge pushes the server and UI language on load and when hidden', async () => {
  const calls = []
  const env = loadBootstrap({
    storage: { 'synaplan.serverUrl': 'https://chat.example.test/', language: 'de' },
    extraPlugins: {
      SynaplanCarSession: {
        update(payload) {
          calls.push(payload)
          return Promise.resolve()
        },
      },
    },
  })
  env.fireDomContentLoaded()
  await env.flushMicrotasks()

  assert.equal(calls.length, 1)
  assert.equal(calls[0].serverUrl, 'https://chat.example.test')
  assert.equal(calls[0].language, 'de')
  // Tokens never cross the bridge; the native store reads the Keychain itself.
  assert.deepEqual(Object.keys(calls[0]).sort(), ['language', 'serverUrl'])

  env.setVisibility('visible')
  await env.flushMicrotasks()
  assert.equal(calls.length, 1)

  env.window.localStorage.setItem('language', 'tr')
  env.setVisibility('hidden')
  await env.flushMicrotasks()
  assert.equal(calls.length, 2)
  assert.equal(calls[1].language, 'tr')
})

test('CarPlay session bridge follows a language the SPA settles after load', async () => {
  const calls = []
  const env = loadBootstrap({
    extraPlugins: {
      SynaplanCarSession: {
        update(payload) {
          calls.push(payload)
          return Promise.resolve()
        },
      },
    },
  })
  env.fireDomContentLoaded()
  await env.flushMicrotasks()
  assert.equal(calls.length, 1)
  assert.equal(calls[0].language, '')

  // Sign-in applies the account language while the phone scene stays visible.
  env.window.localStorage.setItem('language', 'de')
  env.document.documentElement.setAttribute('lang', 'de')
  await env.flushMicrotasks()
  assert.equal(calls.length, 2)
  assert.equal(calls[1].language, 'de')

  env.document.documentElement.setAttribute('lang', 'de')
  env.document.body.appendChild(env.document.createElement('div'))
  await env.flushMicrotasks()
  assert.equal(calls.length, 2, 'an unchanged language is not pushed again')
})

test('CarPlay session bridge tolerates a missing or failing plugin', async () => {
  const missing = loadBootstrap()
  missing.fireDomContentLoaded()
  missing.setVisibility('hidden')
  await missing.flushMicrotasks()

  const failing = loadBootstrap({
    extraPlugins: {
      SynaplanCarSession: {
        update: () => Promise.reject(new Error('not implemented')),
      },
    },
  })
  failing.fireDomContentLoaded()
  failing.setVisibility('hidden')
  await failing.flushMicrotasks()
  assert.match(failing.viewportContent(), /user-scalable=no/)
})

test('app info reports the installed binary and the bundled Synaplan release', async () => {
  const env = loadBootstrap({
    extraPlugins: { App: { getInfo: () => Promise.resolve({ version: '5.3.1', build: '214' }) } },
  })
  env.window.__SYNAPLAN_APP_VERSION__ = '4.0.4'
  env.window.__SYNAPLAN_WEB_VERSION__ = '5.4.0'
  const versions = await env.window.SynaplanAppInfo.getVersions()
  assert.deepEqual({ ...versions }, { app: '5.3.1', build: '214', web: '5.4.0' })
})

test('app info resolves empty when the App plugin is missing or fails', async () => {
  const missing = loadBootstrap()
  missing.window.__SYNAPLAN_WEB_VERSION__ = '5.4.0'
  assert.deepEqual(
    { ...(await missing.window.SynaplanAppInfo.getVersions()) },
    {
      app: '',
      build: '',
      web: '5.4.0',
    }
  )

  const failing = loadBootstrap({
    extraPlugins: { App: { getInfo: () => Promise.reject(new Error('unavailable')) } },
  })
  assert.deepEqual(
    { ...(await failing.window.SynaplanAppInfo.getVersions()) },
    {
      app: '',
      build: '',
      web: '',
    }
  )
})
