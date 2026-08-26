/*
 * synaplan-native.js — app-owned native bootstrap + Server settings (Epic 3 §3.0)
 *
 * Lives ENTIRELY in the synaplan-apps repo (zero blast radius in the public
 * synaplan submodule). build.sh injects it as the FIRST <script> in the bundled
 * dist/index.html, so it runs before the SPA's deferred ES module.
 *
 * Responsibilities:
 *   1. Resolve the configured server URL synchronously (localStorage) and expose
 *      it to the SPA bootstrap via window.__SYNAPLAN_API_BASE_URL__, which the
 *      submodule reads in main.ts / nativeRuntime.ts (the single seam, §3.1).
 *      Falls back to the build default (window.__SYNAPLAN_API_BASE_URL_DEFAULT__,
 *      stamped by build.sh) → DEFAULT_SERVER_URL on a fresh install.
 *   2. Expose an app-owned control surface via window.SynaplanServer
 *      (get/getDefault/save/reset/open/reload). The user-facing UI to change the
 *      server lives INSIDE the SPA (Settings, and Admin → App server for admins),
 *      which calls this API. There is intentionally NO always-on floating gear
 *      anymore. `save()`/`reset()` only VALIDATE + PERSIST — they deliberately do
 *      NOT reload the WebView themselves, so the SPA gets a chance to run its own
 *      cleanup first (signing the user out of every server, since a server change
 *      always requires a fresh login). The SPA calls the separate `reload()`
 *      method once that cleanup is done.
 *   3. RECOVERY ONLY: auto-open a minimal app-owned overlay when the configured
 *      server is unreachable, so the user can always fix a wrong URL or reset to
 *      the default even when the SPA (and thus its Settings UI) can't load. This
 *      overlay is a self-contained flow that persists + reloads immediately on
 *      its own (see `openOverlay()` below) — it does NOT go through
 *      `window.SynaplanServer.save()/reset()`, so it is unaffected by the
 *      persist/reload split above.
 *   4. Own the native launch screen: hide it as soon as the SPA has painted, with
 *      a hard ceiling as a safety net. The launch screen is configured with
 *      `launchAutoHide: false` and the updater's `autoSplashscreen` is not used,
 *      so this file is the single place that takes it down.
 *
 * Notes:
 *   - The server URL is NOT a secret, and the bootstrap must read it
 *     synchronously before the SPA runs — localStorage (persistent in the
 *     capacitor://localhost / https://localhost WebView origin) is the right
 *     tool. The sensitive Bearer token stays in secure storage (Keychain /
 *     Keystore), keyed per server by the submodule (nativeAuth.ts).
 *   - Plain dependency-free ES5-ish JS on purpose: no build step, no imports, so
 *     it can run before the module SPA and never breaks the "runs first" rule.
 */
;(function () {
  'use strict'

  // Production default. A build can override this (e.g. a dev/staging device build
  // pointed at a LAN backend) via window.__SYNAPLAN_API_BASE_URL_DEFAULT__, stamped
  // by build.sh from $SYNAPLAN_API_BASE_URL. A user choice in localStorage always
  // wins over this; this is only the "fresh install" fallback.
  var DEFAULT_SERVER_URL = 'https://web.synaplan.com'
  try {
    var buildDefault = window.__SYNAPLAN_API_BASE_URL_DEFAULT__
    if ('string' === typeof buildDefault && '' !== buildDefault.replace(/^\s+|\s+$/g, '')) {
      DEFAULT_SERVER_URL = buildDefault.replace(/^\s+|\s+$/g, '').replace(/\/+$/, '')
    }
  } catch (e) {
    /* keep production default */
  }
  var STORAGE_KEY = 'synaplan.serverUrl'
  var GLOBAL_KEY = '__SYNAPLAN_API_BASE_URL__'
  var PROBE_PATH = '/api/v1/config/runtime'
  var PROBE_TIMEOUT_MS = 8000

  // Only act inside the native shell. The shell appends this UA marker (Epic 2);
  // on the plain web deployment we must be a complete no-op.
  function isNativeShell() {
    try {
      return navigator.userAgent.indexOf('Synaplan Mobile') !== -1
    } catch (e) {
      return false
    }
  }

  // Normalize user input: trim, default to https:// when no scheme is given,
  // keep an explicit http:// (local dev), strip a trailing slash. Returns '' for
  // anything that isn't a usable absolute URL.
  function normalizeUrl(raw) {
    if (!raw) return ''
    var value = String(raw).trim()
    if (value === '') return ''
    if (!/^https?:\/\//i.test(value)) {
      value = 'https://' + value
    }
    try {
      var u = new URL(value)
      if (u.protocol !== 'http:' && u.protocol !== 'https:') return ''
      // Drop trailing slash on the path; keep host/port.
      var out = u.origin + u.pathname.replace(/\/+$/, '')
      return out.replace(/\/+$/, '')
    } catch (e) {
      return ''
    }
  }

  function getStoredUrl() {
    try {
      var v = window.localStorage.getItem(STORAGE_KEY)
      return v ? normalizeUrl(v) : ''
    } catch (e) {
      return ''
    }
  }

  function resolveServerUrl() {
    return getStoredUrl() || DEFAULT_SERVER_URL
  }

  // ── Splash screen ownership (native only) ───────────────────────────────────
  // The launch screen is configured with `launchAutoHide: false`, so it stays up
  // until something hides it — and this file is the only thing that does.
  //
  // The updater's `autoSplashscreen` is deliberately NOT used: it hides from
  // `sendReadyToJs()`, i.e. only after the OTA update check has returned, and on a
  // cold start the plugin never shows the splash itself, so it never arms its own
  // `autoSplashscreenTimeout` either. A slow or unreachable update server then
  // held the launch screen for the whole check (up to `responseTimeout`, 20s) even
  // though the SPA behind it was fully interactive.
  //
  // Ownership is bounded twice over: hide on the SPA's first paint, and hide
  // anyway once SPLASH_MAX_WAIT_MS has elapsed. A failure anywhere in this file
  // or in the SPA can therefore never leave the user stuck on the splash.
  var SPLASH_MAX_WAIT_MS = 5000
  var splashHidden = false
  var splashObserver = null

  function stopSplashObserver() {
    if (!splashObserver) return
    try {
      splashObserver.disconnect()
    } catch (e) {
      /* ignore */
    }
    splashObserver = null
  }

  function hideSplash() {
    if (splashHidden) return
    splashHidden = true
    stopSplashObserver()
    try {
      var plugins = window.Capacitor && window.Capacitor.Plugins
      var splash = plugins && plugins.SplashScreen
      if (!splash || typeof splash.hide !== 'function') return
      splash.hide({ fadeOutDuration: 200 })
    } catch (e) {
      /* best-effort: a missing plugin must never keep the app from running */
    }
  }

  // The SPA mounts into #app, so its first element child is the first frame the
  // user could actually see. One rAF defers the fade-out until that frame is on
  // screen — hiding earlier would flash the empty page.
  function initSplashPaintWatch() {
    try {
      var isPainted = function () {
        var root = document.getElementById('app')
        return !!(root && root.firstElementChild)
      }
      var hideAfterPaint = function () {
        stopSplashObserver()
        if ('function' === typeof window.requestAnimationFrame) {
          window.requestAnimationFrame(hideSplash)
        } else {
          hideSplash()
        }
      }
      if (isPainted()) {
        hideAfterPaint()
        return
      }
      if ('function' !== typeof MutationObserver) return
      splashObserver = new MutationObserver(function () {
        if (isPainted()) hideAfterPaint()
      })
      splashObserver.observe(document.documentElement, { childList: true, subtree: true })
    } catch (e) {
      /* the SPLASH_MAX_WAIT_MS ceiling below stays as the guarantee */
    }
  }

  // ── 1. Synchronous bootstrap: expose the resolved server to the SPA ─────────
  if (isNativeShell()) {
    // FIRST, before any other native initialization: arm the ceiling. Everything
    // below may throw; the launch screen must come down regardless.
    try {
      setTimeout(hideSplash, SPLASH_MAX_WAIT_MS)
    } catch (e) {
      /* ignore */
    }
    try {
      window[GLOBAL_KEY] = resolveServerUrl()
    } catch (e) {
      /* leave SPA to fall back to its compiled default */
    }
  }

  // Validate a candidate server by probing its PUBLIC runtime-config endpoint.
  // Resolves with {ok:true} only for a reachable Synaplan server (200 + JSON
  // object). No auth, no cookies — this is the same public endpoint the app
  // reads for branding.
  function probeServer(url) {
    var controller = typeof AbortController !== 'undefined' ? new AbortController() : null
    var timer = setTimeout(function () {
      if (controller) controller.abort()
    }, PROBE_TIMEOUT_MS)

    return fetch(url + PROBE_PATH, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      signal: controller ? controller.signal : undefined,
    })
      .then(function (res) {
        if (!res.ok) return { ok: false, error: 'HTTP ' + res.status }
        return res
          .json()
          .then(function (body) {
            if (body && typeof body === 'object') return { ok: true }
            return { ok: false, error: 'Not a Synaplan server (unexpected response).' }
          })
          .catch(function () {
            return { ok: false, error: 'Not a Synaplan server (invalid JSON).' }
          })
      })
      .catch(function (err) {
        var msg =
          err && err.name === 'AbortError'
            ? 'Server did not respond in time.'
            : 'Server unreachable.'
        return { ok: false, error: msg }
      })
      .then(function (result) {
        clearTimeout(timer)
        return result
      })
  }

  // Persist a validated server. Callers that go through `window.SynaplanServer`
  // (the SPA) are responsible for reloading themselves (see the API object
  // below) once their own cleanup has run; the vanilla recovery overlay below
  // reloads immediately since it has no SPA-side state to clean up.
  function saveServer(url) {
    try {
      window.localStorage.setItem(STORAGE_KEY, url)
    } catch (e) {
      /* non-fatal: in-memory global is already set for this session */
    }
  }

  function resetServer() {
    try {
      window.localStorage.removeItem(STORAGE_KEY)
    } catch (e) {
      /* ignore */
    }
  }

  function reload() {
    try {
      window.location.reload()
    } catch (e) {
      /* ignore */
    }
  }

  // ── Lock the viewport: the native app must NEVER zoom ───────────────────────
  // iOS auto-zooms when focusing an input whose font-size < 16px, and pinch-zoom
  // is undesirable in a native shell. The submodule's index.html viewport meta
  // intentionally allows zoom on the plain web deployment, so we override it ONLY
  // inside the native shell (zero blast radius in the public submodule) by adding
  // maximum-scale=1 + user-scalable=no. WKWebView and the Android WebView both
  // honor a viewport meta updated after DOMContentLoaded.
  // `interactive-widget=overlays-content`: on Android the soft keyboard OVERLAYS
  // the content (the layout viewport keeps full height) to match iOS's
  // Keyboard.resize = 'none'. The SPA floats the chat composer above the keyboard
  // via the --keyboard-inset-height var (see initKeyboardInsetBridge below), so
  // the page never shrinks on either platform.
  var LOCKED_VIEWPORT =
    'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, ' +
    'viewport-fit=cover, interactive-widget=overlays-content'

  function enforceNoZoomViewport() {
    try {
      var metas = document.querySelectorAll('meta[name="viewport"]')
      if (!metas || metas.length === 0) {
        var head = document.head || document.getElementsByTagName('head')[0]
        if (!head) return
        var meta = document.createElement('meta')
        meta.setAttribute('name', 'viewport')
        meta.setAttribute('content', LOCKED_VIEWPORT)
        head.appendChild(meta)
        return
      }
      for (var i = 0; i < metas.length; i++) {
        if (metas[i].getAttribute('content') !== LOCKED_VIEWPORT) {
          metas[i].setAttribute('content', LOCKED_VIEWPORT)
        }
      }
    } catch (e) {
      /* best-effort: never block the app */
    }
  }

  // ── 2/3. App-owned Server settings overlay (vanilla DOM, isolated styles) ───
  // Used only as the RECOVERY surface (auto-opened on an unreachable server) and
  // when the SPA explicitly calls window.SynaplanServer.open(). The primary,
  // user-facing way to change the server lives in the SPA (Admin → App server).
  var OVERLAY_ID = 'synaplan-server-overlay'

  function el(tag, attrs, text) {
    var node = document.createElement(tag)
    if (attrs) {
      for (var k in attrs) {
        if (Object.prototype.hasOwnProperty.call(attrs, k)) node.setAttribute(k, attrs[k])
      }
    }
    if (text != null) node.textContent = text
    return node
  }

  function closeOverlay() {
    var existing = document.getElementById(OVERLAY_ID)
    if (existing && existing.parentNode) existing.parentNode.removeChild(existing)
  }

  function openOverlay(opts) {
    opts = opts || {}
    closeOverlay()

    // The overlay hangs off <body>, not off #app, so the paint watch above never
    // sees it. Without this the recovery flow would sit invisibly behind the
    // launch screen whenever the configured server is unreachable.
    hideSplash()

    var current = resolveServerUrl()

    var root = el('div', { id: OVERLAY_ID })
    root.setAttribute(
      'style',
      'position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,.55);' +
        'display:flex;align-items:center;justify-content:center;padding:24px;' +
        'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;'
    )

    var card = el('div')
    card.setAttribute(
      'style',
      'background:#fff;color:#111;max-width:420px;width:100%;border-radius:14px;' +
        'box-shadow:0 12px 40px rgba(0,0,0,.3);padding:22px;box-sizing:border-box;'
    )

    card.appendChild(
      (function () {
        var h = el('div', null, 'Server')
        h.setAttribute('style', 'font-size:18px;font-weight:700;margin:0 0 4px;')
        return h
      })()
    )
    card.appendChild(
      (function () {
        var p = el(
          'div',
          null,
          'Choose which Synaplan server this app connects to. The default is ' +
            DEFAULT_SERVER_URL +
            '.'
        )
        p.setAttribute('style', 'font-size:13px;color:#555;margin:0 0 14px;line-height:1.4;')
        return p
      })()
    )

    if (opts.message) {
      var banner = el('div', null, opts.message)
      banner.setAttribute(
        'style',
        'background:#fee2e2;color:#991b1b;border:1px solid #fecaca;border-radius:8px;' +
          'padding:9px 11px;font-size:13px;margin:0 0 14px;'
      )
      card.appendChild(banner)
    }

    var input = el('input', {
      type: 'url',
      inputmode: 'url',
      autocapitalize: 'off',
      autocorrect: 'off',
      spellcheck: 'false',
      placeholder: DEFAULT_SERVER_URL,
      value: current,
    })
    input.setAttribute(
      'style',
      'width:100%;box-sizing:border-box;padding:11px 12px;font-size:15px;border:1px solid #cbd5e1;' +
        'border-radius:9px;outline:none;margin:0 0 6px;'
    )
    card.appendChild(input)

    var status = el('div', null, '')
    status.setAttribute('style', 'min-height:18px;font-size:12.5px;margin:0 0 14px;color:#555;')
    card.appendChild(status)

    function setStatus(text, kind) {
      status.textContent = text || ''
      status.style.color = kind === 'error' ? '#b91c1c' : kind === 'ok' ? '#15803d' : '#555'
    }

    var row = el('div')
    row.setAttribute('style', 'display:flex;gap:10px;justify-content:flex-end;flex-wrap:wrap;')

    var resetBtn = el('button', { type: 'button' }, 'Reset to default')
    resetBtn.setAttribute(
      'style',
      'margin-right:auto;padding:10px 12px;font-size:14px;border:none;background:transparent;' +
        'color:#475569;cursor:pointer;border-radius:9px;'
    )

    var cancelBtn = el('button', { type: 'button' }, 'Cancel')
    cancelBtn.setAttribute(
      'style',
      'padding:10px 14px;font-size:14px;border:1px solid #cbd5e1;background:#fff;color:#111;' +
        'cursor:pointer;border-radius:9px;'
    )

    var saveBtn = el('button', { type: 'button' }, 'Save')
    saveBtn.setAttribute(
      'style',
      'padding:10px 18px;font-size:14px;border:none;background:#003fc7;color:#fff;cursor:pointer;' +
        'border-radius:9px;font-weight:600;'
    )

    // Cancel is hidden when the overlay was auto-opened on an unreachable server
    // (there is nothing usable to go back to).
    if (opts.dismissable === false) {
      cancelBtn.style.display = 'none'
    }

    function busy(on) {
      saveBtn.disabled = on
      resetBtn.disabled = on
      saveBtn.style.opacity = on ? '0.6' : '1'
    }

    saveBtn.addEventListener('click', function () {
      var normalized = normalizeUrl(input.value)
      if (!normalized) {
        setStatus('Please enter a valid URL (e.g. https://web.synaplan.com).', 'error')
        return
      }
      busy(true)
      setStatus('Checking server…', 'info')
      probeServer(normalized).then(function (result) {
        if (result.ok) {
          setStatus('Connected. Reloading…', 'ok')
          saveServer(normalized)
          reload()
        } else {
          busy(false)
          setStatus(result.error || 'Could not reach that server.', 'error')
        }
      })
    })

    resetBtn.addEventListener('click', function () {
      busy(true)
      setStatus('Resetting…', 'info')
      resetServer()
      reload()
    })

    cancelBtn.addEventListener('click', function () {
      closeOverlay()
    })

    row.appendChild(resetBtn)
    row.appendChild(cancelBtn)
    row.appendChild(saveBtn)
    card.appendChild(row)
    root.appendChild(card)
    document.body.appendChild(root)

    setTimeout(function () {
      try {
        input.focus()
      } catch (e) {
        /* ignore */
      }
    }, 50)
  }

  // Epic 10.1: visible environment indicator for non-prod builds. build.sh stamps
  // window.__SYNAPLAN_ENV__ (+ version/build) into the bundle; prod shows nothing.
  function mountEnvBadge() {
    try {
      var env = window.__SYNAPLAN_ENV__
      if (!env || env === 'prod') return
      if (document.getElementById('synaplan-env-badge')) return
      var version = window.__SYNAPLAN_APP_VERSION__ || ''
      var build = window.__SYNAPLAN_BUILD__ || ''
      var label = String(env).toUpperCase()
      if (version) label += ' \u00b7 ' + version + (build ? ' (' + build + ')' : '')
      var badge = el('div', { id: 'synaplan-env-badge' }, label)
      badge.setAttribute(
        'style',
        'position:fixed;top:env(safe-area-inset-top,0px);left:50%;transform:translateX(-50%);' +
          'z-index:2147483645;background:#b91c1c;color:#fff;font:600 11px/1.5 -apple-system,' +
          'BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;padding:2px 12px;' +
          'border-radius:0 0 9px 9px;letter-spacing:.4px;opacity:.92;pointer-events:none;' +
          'max-width:90vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;'
      )
      document.body.appendChild(badge)
    } catch (e) {
      /* badge is best-effort; never block the app */
    }
  }

  // Public API consumed by the SPA's Settings / "Admin → App server" UI
  // (synaplan submodule, native-only) and available for debugging.
  //
  // `save()`/`reset()` ONLY validate + persist — they never reload on their
  // own. This gives the SPA a window to run its own cleanup (sign the user out
  // of every server) before the WebView reloads against the new URL. The SPA
  // MUST call `reload()` itself once that cleanup has finished; if it doesn't,
  // the new server simply won't be used until the next natural reload.
  window.SynaplanServer = {
    get: resolveServerUrl,
    getDefault: function () {
      return DEFAULT_SERVER_URL
    },
    open: function () {
      openOverlay({ dismissable: true })
    },
    save: function (url) {
      var n = normalizeUrl(url)
      if (!n) return Promise.resolve({ ok: false, error: 'invalid url' })
      return probeServer(n).then(function (r) {
        if (r.ok) {
          saveServer(n)
        }
        return r
      })
    },
    reset: function () {
      resetServer()
    },
    reload: function () {
      reload()
    },
  }

  // ── Haptics bridge (Taptic Engine on iOS, vibration on Android) ─────────────
  // Wraps the Capacitor Haptics plugin so the SPA can fire a single impact
  // WITHOUT importing @capacitor/* into the public submodule (it stays
  // Capacitor-free; the SPA calls this via services/api/nativeHaptics.ts). Every
  // call is guarded: a missing plugin / non-native context is a silent no-op so
  // haptics can never break an interaction.
  function hapticImpact(style) {
    try {
      var plugins = window.Capacitor && window.Capacitor.Plugins
      var haptics = plugins && plugins.Haptics
      if (!haptics || typeof haptics.impact !== 'function') return
      var map = { light: 'LIGHT', medium: 'MEDIUM', heavy: 'HEAVY' }
      var impactStyle = map[String(style || 'light').toLowerCase()] || 'LIGHT'
      haptics.impact({ style: impactStyle })
    } catch (e) {
      /* best-effort: never throw into the SPA */
    }
  }

  window.SynaplanHaptics = {
    impact: function (style) {
      hapticImpact(style)
    },
  }

  // ── Keyboard inset bridge (float the composer above the keyboard) ───────────
  // With Keyboard.resize = 'none' the WebView keeps its full height, so the
  // page never shrinks. We publish the keyboard height as the CSS variable
  // `--keyboard-inset-height` on <html>; the SPA (style.css .chat-composer-sticky)
  // translates the chat composer up by that amount. `keyboardWillShow` fires at
  // the START of the iOS keyboard animation WITH the final height, so a matching
  // CSS transition slides the composer up in sync — no lag. Every call is
  // guarded so a missing plugin / non-native context is a silent no-op.
  function setKeyboardInset(px) {
    try {
      var height = typeof px === 'number' && px > 0 ? Math.round(px) : 0
      document.documentElement.style.setProperty('--keyboard-inset-height', height + 'px')
      // Notify the SPA so keyboard-aware views (chat) can re-pin their scroll to
      // the bottom once the inset-driven padding has been applied. Fired for both
      // show (height > 0) and hide (height === 0).
      window.dispatchEvent(
        new CustomEvent('synaplan:keyboardinset', { detail: { height: height } })
      )
    } catch (e) {
      /* best-effort: never throw into the SPA */
    }
  }

  function initKeyboardInsetBridge() {
    try {
      var plugins = window.Capacitor && window.Capacitor.Plugins
      var keyboard = plugins && plugins.Keyboard
      if (!keyboard || typeof keyboard.addListener !== 'function') return
      keyboard.addListener('keyboardWillShow', function (info) {
        setKeyboardInset(info && info.keyboardHeight)
      })
      // Re-assert the inset once the keyboard is FULLY shown. WKWebView can reset
      // the scroll position during the slide-in animation, so any scroll-assist
      // that runs on `keyboardWillShow` (animation start) gets undone. Firing the
      // inset event again here gives the SPA a correctly-timed signal to scroll a
      // focused input clear of the keyboard (keyboardScrollAssist.ts).
      keyboard.addListener('keyboardDidShow', function (info) {
        setKeyboardInset(info && info.keyboardHeight)
      })
      keyboard.addListener('keyboardWillHide', function () {
        setKeyboardInset(0)
      })
    } catch (e) {
      /* best-effort: the composer simply keeps its default bottom position */
    }
  }

  // ── Mount UI + connectivity self-check (native only) ────────────────────────
  if (isNativeShell()) {
    var onReady = function () {
      initSplashPaintWatch()
      enforceNoZoomViewport()
      initKeyboardInsetBridge()
      mountEnvBadge()
      // Self-check: if the configured server is unreachable, auto-open the
      // recovery overlay so the user can fix it — the SPA (and the in-app Admin
      // server panel) would otherwise be stuck on a white screen.
      probeServer(resolveServerUrl()).then(function (result) {
        if (!result.ok && !document.getElementById(OVERLAY_ID)) {
          openOverlay({
            dismissable: false,
            message:
              'Can\u2019t reach ' +
              resolveServerUrl() +
              '. Check the address or reset to the default server.',
          })
        }
      })
    }
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', onReady)
    } else {
      onReady()
    }
  }
})()
