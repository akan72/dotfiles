'use strict'
// Preloaded (node --require) before markdown-preview.nvim's server. The server
// listens on 127.0.0.1, but browsers let any website send requests and open
// WebSockets to it, and DNS rebinding can make it look same-origin. Every HTTP
// request and WebSocket upgrade passes these checks before the plugin or
// engine.io sees it, so web pages cannot read previews or local files.
const http = require('http')

const IMAGE = /\.(png|jpe?g|gif|svg|webp|bmp|ico|avif)$/i

function allowed(req) {
  const port = req.socket && req.socket.localPort
  const hosts = [`127.0.0.1:${port}`, `localhost:${port}`]
  if (!hosts.includes(req.headers.host)) return false
  // Browsers mark requests a foreign page starts, even without Origin/Referer.
  if (req.headers['sec-fetch-site'] === 'cross-site') return false
  const { origin, referer } = req.headers
  const ownOrigin = origin !== undefined && hosts.some((host) => origin === `http://${host}`)
  const ownReferer = referer !== undefined && hosts.some((host) => referer.startsWith(`http://${host}/`))
  if (origin !== undefined && !ownOrigin) return false
  if (referer !== undefined && !ownReferer) return false
  const raw = req.url || ''
  let path
  try {
    path = decodeURIComponent(decodeURIComponent(raw.replace(/[?#].*$/, '')))
  } catch (_) {
    return false
  }
  if (path.split(/[\\/]/).includes('..')) return false
  if (path.startsWith('/socket.io/')) {
    // Fail closed: the preview page always identifies itself, and JSONP polling
    // (the j/jsonp query) is how a foreign <script> tag would read the data.
    if (/[?&](j|jsonp)=/.test(raw)) return false
    return ownOrigin || ownReferer
  }
  // Images load from the preview page, which always sends its own Referer.
  if (path.startsWith('/_local_image_')) return IMAGE.test(path) && ownReferer
  return true
}

const createServer = http.createServer
http.createServer = function (...args) {
  const server = createServer.apply(http, args)
  const emit = server.emit
  server.emit = function (event, req, target, ...rest) {
    if (event === 'request' && !allowed(req)) {
      target.writeHead(403, { 'content-type': 'text/plain' })
      target.end('Forbidden\n')
      return true
    }
    if (event === 'upgrade' && !allowed(req)) {
      target.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n')
      return true
    }
    if (event === 'request' && (req.url || '').startsWith('/_local_image_')) {
      // A local SVG opened directly must never run script on the preview origin.
      target.setHeader('content-security-policy', "sandbox; default-src 'none'; style-src 'unsafe-inline'")
      target.setHeader('x-content-type-options', 'nosniff')
    }
    return emit.call(this, event, req, target, ...rest)
  }
  return server
}
