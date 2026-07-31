#!/usr/bin/env node
/**
 * Dev shell for simulator live reload.
 *
 * The WebView can be pointed at the Vite dev server (SYNAPLAN_DEV_SERVER), which
 * makes a change visible on reload instead of after a full Vue build, `cap sync`
 * and native build. Vite serves the submodule's own index.html though, so the
 * app-owned bootstrap that `build.sh` injects into the bundled index.html is
 * missing — and with it `window.__SYNAPLAN_API_BASE_URL__` and the in-app server
 * switcher.
 *
 * This proxy sits in front of Vite, serves the two bootstrap files, and injects
 * them into every HTML document. It lives here on purpose: the public submodule
 * stays untouched, so no pin has to move to develop locally.
 *
 * Usage:
 *   (cd synaplan/frontend && npm run dev -- --host)
 *   SYNAPLAN_API_BASE_URL=http://192.168.1.20:8000 npm run dev:shell
 *   SYNAPLAN_ENV=dev SYNAPLAN_DEV_SERVER=http://192.168.1.20:5174 npx cap sync ios
 */
import { createServer, request as httpRequest } from 'node:http'
import { connect } from 'node:net'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { ROOT, appVersion, buildNumber } from './release-lib.mjs'

const target = new URL(process.env.SYNAPLAN_VITE_URL || 'http://127.0.0.1:5173')
const port = Number(process.env.SYNAPLAN_DEV_SHELL_PORT || 5174)
const host = process.env.SYNAPLAN_DEV_SHELL_HOST || '0.0.0.0'

const BOOTSTRAP_PATHS = ['/synaplan-env.js', '/synaplan-native.js']
const INJECTION =
  '\n    <script src="/synaplan-env.js"></script>' +
  '\n    <script src="/synaplan-native.js"></script>'

// Same stamping as build.sh, so the dev session behaves like a dev device build.
function environmentScript() {
  const appEnv = process.env.SYNAPLAN_ENV?.trim() || 'dev'
  const apiBaseUrl = process.env.SYNAPLAN_API_BASE_URL?.trim()
  const lines = [
    `window.__SYNAPLAN_ENV__ = ${JSON.stringify(appEnv)};`,
    `window.__SYNAPLAN_APP_VERSION__ = ${JSON.stringify(appVersion())};`,
    `window.__SYNAPLAN_BUILD__ = ${JSON.stringify(buildNumber())};`,
  ]
  if (apiBaseUrl) {
    lines.push(`window.__SYNAPLAN_API_BASE_URL_DEFAULT__ = ${JSON.stringify(apiBaseUrl)};`)
  }
  return `${lines.join('\n')}\n`
}

function serveBootstrap(path, response) {
  const body =
    path === '/synaplan-env.js'
      ? environmentScript()
      : readFileSync(join(ROOT, 'app', 'synaplan-native.js'), 'utf8')
  response.writeHead(200, {
    'content-type': 'application/javascript; charset=utf-8',
    'cache-control': 'no-store',
  })
  response.end(body)
}

const server = createServer((clientRequest, clientResponse) => {
  const path = clientRequest.url ?? '/'
  if (BOOTSTRAP_PATHS.includes(path.split('?')[0])) {
    serveBootstrap(path.split('?')[0], clientResponse)
    return
  }

  const upstream = httpRequest(
    {
      hostname: target.hostname,
      port: target.port,
      method: clientRequest.method,
      path,
      headers: { ...clientRequest.headers, host: target.host },
    },
    (upstreamResponse) => {
      const isHtml = /text\/html/i.test(upstreamResponse.headers['content-type'] ?? '')
      if (!isHtml) {
        clientResponse.writeHead(upstreamResponse.statusCode ?? 502, upstreamResponse.headers)
        upstreamResponse.pipe(clientResponse)
        return
      }
      const chunks = []
      upstreamResponse.on('data', (chunk) => chunks.push(chunk))
      upstreamResponse.on('end', () => {
        const html = Buffer.concat(chunks)
          .toString('utf8')
          .replace(/(<head[^>]*>)/i, `$1${INJECTION}`)
        const headers = { ...upstreamResponse.headers }
        delete headers['content-length']
        clientResponse.writeHead(upstreamResponse.statusCode ?? 200, headers)
        clientResponse.end(html)
      })
    }
  )

  upstream.on('error', (error) => {
    clientResponse.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
    clientResponse.end(`Vite dev server unreachable at ${target.origin}: ${error.message}\n`)
  })
  clientRequest.pipe(upstream)
})

// Hot module replacement uses a WebSocket against the page origin, so the
// upgrade has to reach Vite untouched or every save would need a manual reload.
server.on('upgrade', (clientRequest, clientSocket, head) => {
  const upstreamSocket = connect(Number(target.port), target.hostname, () => {
    const headers = Object.entries({ ...clientRequest.headers, host: target.host })
      .map(([key, value]) => `${key}: ${value}\r\n`)
      .join('')
    upstreamSocket.write(`GET ${clientRequest.url} HTTP/1.1\r\n${headers}\r\n`)
    if (head?.length) upstreamSocket.write(head)
    upstreamSocket.pipe(clientSocket)
    clientSocket.pipe(upstreamSocket)
  })
  upstreamSocket.on('error', () => clientSocket.destroy())
  clientSocket.on('error', () => upstreamSocket.destroy())
})

server.listen(port, host, () => {
  console.log(`[dev-shell] serving ${target.origin} with the app bootstrap on port ${port}`)
  console.log(`[dev-shell] point the app at it: SYNAPLAN_DEV_SERVER=http://<your-lan-ip>:${port}`)
})
