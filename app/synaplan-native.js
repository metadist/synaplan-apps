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
 *      Falls back to DEFAULT_SERVER_URL on a fresh install.
 *   2. Provide a native "Server" settings surface (app-owned overlay, NOT the
 *      SPA): show current server, edit, validate-by-probe, Save, Reset.
 *   3. Auto-open that surface when the configured server is unreachable, so the
 *      user can always fix a wrong URL even if the SPA can't load.
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

  var DEFAULT_SERVER_URL = 'https://web.synaplan.com'
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

  // ── 1. Synchronous bootstrap: expose the resolved server to the SPA ─────────
  if (isNativeShell()) {
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
        var msg = err && err.name === 'AbortError' ? 'Server did not respond in time.' : 'Server unreachable.'
        return { ok: false, error: msg }
      })
      .then(function (result) {
        clearTimeout(timer)
        return result
      })
  }

  // Persist a validated server and reload so main.ts re-bootstraps against it
  // (new API base URL, branding re-fetch, per-server token scope). Switching
  // servers clears the previous server's in-memory auth simply by reloading;
  // its token stays in secure storage under that server's scope for later.
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

  // ── 2/3. App-owned Server settings overlay (vanilla DOM, isolated styles) ───
  var OVERLAY_ID = 'synaplan-server-overlay'
  var GEAR_ID = 'synaplan-server-gear'

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
          'Choose which Synaplan server this app connects to. The default is ' + DEFAULT_SERVER_URL + '.'
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

  // Discreet, persistent gear affordance so the Server settings are always
  // reachable (even mid-session). Bottom-leading, low-profile.
  function mountGear() {
    if (document.getElementById(GEAR_ID)) return
    var gear = el('button', { id: GEAR_ID, type: 'button', 'aria-label': 'Server settings' }, '\u2699')
    gear.setAttribute(
      'style',
      'position:fixed;left:calc(env(safe-area-inset-left,0px) + 10px);' +
        'bottom:calc(env(safe-area-inset-bottom,0px) + 10px);z-index:2147483646;' +
        'width:34px;height:34px;border-radius:50%;border:none;cursor:pointer;' +
        'background:rgba(0,0,0,.35);color:#fff;font-size:17px;line-height:34px;text-align:center;' +
        'padding:0;opacity:.55;'
    )
    gear.addEventListener('click', function () {
      openOverlay({ dismissable: true })
    })
    document.body.appendChild(gear)
  }

  // Public API for debugging / future native triggers.
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
          reload()
        }
        return r
      })
    },
    reset: function () {
      resetServer()
      reload()
    },
  }

  // ── Mount UI + connectivity self-check (native only) ────────────────────────
  if (isNativeShell()) {
    var onReady = function () {
      mountGear()
      // Self-check: if the configured server is unreachable, auto-open the
      // settings so the user can fix it — the SPA would otherwise be stuck.
      probeServer(resolveServerUrl()).then(function (result) {
        if (!result.ok && !document.getElementById(OVERLAY_ID)) {
          openOverlay({
            dismissable: false,
            message:
              'Can\u2019t reach ' + resolveServerUrl() + '. Check the address or reset to the default server.',
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
