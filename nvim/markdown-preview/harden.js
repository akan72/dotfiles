'use strict'
// Preloaded (node --require) before markdown-preview.nvim's server. The server
// listens on 127.0.0.1, but browsers let any website open WebSockets to it and
// DNS rebinding can make it look same-origin. Accept only requests addressed to
// this server by its own localhost host and origin, and serve only image files
// from /_local_image_, so web pages cannot read previews or local files.
const http = require('http')
const Module = require('module')

const IMAGE = /\.(png|jpe?g|gif|svg|webp|bmp|ico|avif)$/i

function local(req) {
  const port = req.socket && req.socket.localPort
  const hosts = [`127.0.0.1:${port}`, `localhost:${port}`]
  if (!hosts.includes(req.headers.host)) return false
  // Browsers mark requests a foreign page starts, even without Origin/Referer.
  if (req.headers['sec-fetch-site'] === 'cross-site') return false
  const origin = req.headers.origin
  if (origin !== undefined && !hosts.some((host) => origin === `http://${host}`)) return false
  const referer = req.headers.referer
  if (referer !== undefined && !hosts.some((host) => referer.startsWith(`http://${host}/`))) return false
  return true
}

function safePath(req) {
  const url = req.url
  let path
  try {
    path = decodeURIComponent(decodeURIComponent((url || '').replace(/[?#].*$/, '')))
  } catch (_) {
    return false
  }
  // Images load from the preview page, which always sends its own Referer.
  if (path.startsWith('/_local_image_')) return IMAGE.test(path) && req.headers.referer !== undefined
  return !path.split(/[\\/]/).includes('..')
}

const createServer = http.createServer
http.createServer = function (...args) {
  const handler = args.find((arg) => typeof arg === 'function')
  const rest = args.filter((arg) => arg !== handler)
  return createServer.call(http, ...rest, (req, res) => {
    if (!local(req) || !safePath(req)) {
      res.writeHead(403, { 'content-type': 'text/plain' })
      return res.end('Forbidden\n')
    }
    if (req.url.startsWith('/_local_image_')) {
      // A local SVG opened directly must never run script on the preview origin.
      res.setHeader('content-security-policy', "sandbox; default-src 'none'; style-src 'unsafe-inline'")
      res.setHeader('x-content-type-options', 'nosniff')
    }
    return handler(req, res)
  })
}

const load = Module._load
Module._load = function (request, ...rest) {
  const exported = load.call(this, request, ...rest)
  if (request === 'socket.io' && !exported.dotfilesHardened) {
    const check = exported.prototype.checkRequest
    exported.prototype.checkRequest = function (req, fn) {
      if (!local(req)) return fn(null, false)
      return check.call(this, req, fn)
    }
    exported.dotfilesHardened = true
  }
  return exported
}
