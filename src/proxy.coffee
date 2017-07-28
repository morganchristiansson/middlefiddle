net       = require('net')
_         = require('underscore')
tls       = require('tls')
http      = require('http')
{HttpProxy} = require('./http_proxy')
certGenerator = require('./cert_generator')
log = require("./logger")

STATES =
  UNCONNECTED: 0,
  CONNECTING : 1,
  CONNECTED : 2

exports.createProxy = (middlewares...) ->
  proxy = new exports.Proxy(middlewares)
  return proxy

# Handles both HTTP and HTTPS connections
class exports.Proxy extends HttpProxy

  hijackSsl: (headers, c) ->
    log.info 'SSL'
    match = headers.match("CONNECT +([^:]+):([0-9]+).*")
    host = match[1]
    port = match[2]
    certGenerator.build host, (tlsContext) =>
      pair = tls.createSecurePair(tlsContext, true, false, false)
      pair.on 'error', (err) ->
        console.log err
      httpServer = new http.Server
      httpServer.on 'request', @handle
      cleartext = pipe(pair, c)
      http._connectionListener.call(this, cleartext)
      @httpAllowHalfOpen = false;
      c.write("HTTP/1.0 200 Connection established\r\nProxy-agent: MiddleFiddle\r\n\r\n")

  hijackHttp: (headers, c) ->
    log.info 'HTTP'
    httpServer = new http.Server
    httpServer.on 'request', @handle
    http._connectionListener.call(this, c)
    @httpAllowHalfOpen = false;
    log.info 'HTTP\'d'

  listen: (port) ->
    tlsServer = net.createServer (c) =>
      headers = ''
      data = []
      state = STATES.CONNECTING
      log.info("CONNECT")
      c.on 'data', (data) =>
        log.info("DATA")
        if (state != STATES.CONNECTED)
          headers += data.toString()
          if headers.match("\r\n\r\n")
            state = STATES.CONNECTED
            log.info("CONNECTED")
            if (headers.match(/^CONNECT/))
              @hijackSsl(headers, c)
            else
              @hijackHttp(headers, c)
    tlsServer.listen(port)
    log.info("LISTENING")


pipe = (pair, socket) ->
  pair.encrypted.pipe(socket)
  socket.pipe(pair.encrypted)

  pair.fd = socket.fd
  cleartext = pair.cleartext
  cleartext.socket = socket
  cleartext.encrypted = pair.encrypted
  cleartext.authorized = false

  onerror = (e) ->
    if cleartext._controlReleased
      cleartext.emit('error', e)

  onclose = () ->
    socket.removeListener('error', onerror)
    socket.removeListener('close', onclose)
    socket.removeListener('timeout', ontimeout)

  ontimeout = () ->
    cleartext.emit('timeout')

  socket.on 'error', onerror
  socket.on 'close', onclose
  socket.on 'timeout', ontimeout

  return cleartext
