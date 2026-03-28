/**
 * Secure Terminal Proxy
 * Validates session tokens against wisecool-api before allowing terminal access
 */

const http = require('http');
const httpProxy = require('http-proxy');
const https = require('https');

const TTYD_HOST = process.env.TTYD_HOST || '172.20.0.1';
const TTYD_PORT = process.env.TTYD_PORT || 7681;
const API_URL = process.env.API_URL || 'https://api.wisecool.tn/v1/api';
const PORT = process.env.PORT || 3001;

// Create proxy
const proxy = httpProxy.createProxyServer({
  target: `http://${TTYD_HOST}:${TTYD_PORT}`,
  ws: true,
  changeOrigin: true,
});

proxy.on('error', (err, req, res) => {
  console.error('[PROXY ERROR]', err.message);
  if (res.writeHead) {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Terminal server unavailable' }));
  }
});

// Validate session token against API
async function validateSession(token, authHeader) {
  return new Promise((resolve) => {
    if (!token) {
      resolve(false);
      return;
    }

    const url = new URL(`${API_URL}/security/terminal/check-session/`);

    const options = {
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname,
      method: 'GET',
      headers: {
        'X-Terminal-Session': token,
        'Authorization': authHeader || '',
      },
      rejectUnauthorized: false, // For internal requests
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve(json.authenticated === true);
        } catch {
          resolve(false);
        }
      });
    });

    req.on('error', (err) => {
      console.error('[AUTH ERROR]', err.message);
      resolve(false);
    });

    req.setTimeout(5000, () => {
      req.destroy();
      resolve(false);
    });

    req.end();
  });
}

// Extract token from URL query or cookie
function getToken(req) {
  // Check query string
  const url = new URL(req.url, `http://${req.headers.host}`);
  const queryToken = url.searchParams.get('token');
  if (queryToken) return queryToken;

  // Check cookie
  const cookies = req.headers.cookie || '';
  const match = cookies.match(/terminal_session=([^;]+)/);
  if (match) return match[1];

  // Check header
  return req.headers['x-terminal-session'];
}

function getAuthHeader(req) {
  // Check query string for auth token
  const url = new URL(req.url, `http://${req.headers.host}`);
  const authToken = url.searchParams.get('auth');
  if (authToken) return `Bearer ${authToken}`;

  return req.headers['authorization'];
}

// HTTP server
const server = http.createServer(async (req, res) => {
  // Health check
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK');
    return;
  }

  // CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(200, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'X-Terminal-Session, Authorization, Content-Type',
    });
    res.end();
    return;
  }

  const token = getToken(req);
  const authHeader = getAuthHeader(req);

  console.log(`[REQUEST] ${req.method} ${req.url} - Token: ${token ? 'present' : 'missing'}`);

  const isValid = await validateSession(token, authHeader);

  if (!isValid) {
    console.log('[AUTH] Session invalid or expired');
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      error: 'Unauthorized',
      message: 'Invalid or expired terminal session'
    }));
    return;
  }

  console.log('[AUTH] Session valid, proxying to ttyd');
  proxy.web(req, res);
});

// WebSocket upgrade
server.on('upgrade', async (req, socket, head) => {
  const token = getToken(req);
  const authHeader = getAuthHeader(req);

  console.log(`[UPGRADE] WebSocket - Token: ${token ? 'present' : 'missing'}`);

  const isValid = await validateSession(token, authHeader);

  if (!isValid) {
    console.log('[AUTH] WebSocket session invalid');
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }

  console.log('[AUTH] WebSocket session valid, upgrading');
  proxy.ws(req, socket, head);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[TERMINAL PROXY] Running on port ${PORT}`);
  console.log(`[TERMINAL PROXY] Proxying to ttyd at ${TTYD_HOST}:${TTYD_PORT}`);
  console.log(`[TERMINAL PROXY] Validating sessions against ${API_URL}`);
});
