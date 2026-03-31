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

// Allowed origins for iframe embedding
const ALLOWED_ORIGINS = [
  'https://admin.wisecool.tn',
  'https://instructor.wisecool.tn',
  'https://app.wisecool.tn',
];

proxy.on('error', (err, req, res) => {
  console.error('[PROXY ERROR]', err.message);
  if (res.writeHead) {
    const origin = req.headers.origin || '';
    const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
    res.writeHead(502, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Credentials': 'true',
      'Content-Security-Policy': `frame-ancestors ${ALLOWED_ORIGINS.join(' ')}`,
    });
    res.end(JSON.stringify({ error: 'Terminal server unavailable' }));
  }
});

// Add headers to proxied responses for CORS and iframe embedding
proxy.on('proxyRes', (proxyRes, req, res) => {
  const origin = req.headers.origin || '';
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];

  proxyRes.headers['access-control-allow-origin'] = allowedOrigin;
  proxyRes.headers['access-control-allow-credentials'] = 'true';
  proxyRes.headers['access-control-allow-methods'] = 'GET, POST, OPTIONS';
  proxyRes.headers['access-control-allow-headers'] = 'X-Terminal-Session, Authorization, Content-Type';
  // Allow iframe embedding from allowed origins
  proxyRes.headers['content-security-policy'] = `frame-ancestors ${ALLOWED_ORIGINS.join(' ')}`;
  // Remove X-Frame-Options if present (CSP frame-ancestors takes precedence)
  delete proxyRes.headers['x-frame-options'];
});

// Validate session token against API using fetch
async function validateSession(token, authHeader) {
  if (!token) {
    return false;
  }

  try {
    const url = `${API_URL}/security/terminal/check-session/`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'X-Terminal-Session': token,
        'Authorization': authHeader || '',
      },
      signal: controller.signal,
    });

    clearTimeout(timeout);

    if (!response.ok) {
      console.log(`[AUTH] API returned ${response.status}`);
      return false;
    }

    const data = await response.json();
    return data.authenticated === true;
  } catch (err) {
    console.error('[AUTH ERROR]', err.message);
    return false;
  }
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

// Helper to get CORS/frame headers
function getCorsHeaders(origin) {
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'X-Terminal-Session, Authorization, Content-Type',
    'Content-Security-Policy': `frame-ancestors ${ALLOWED_ORIGINS.join(' ')}`,
  };
}

// In-memory session store (token -> {authHeader, validUntil})
const sessionStore = new Map();

// Clean up expired sessions every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [key, session] of sessionStore.entries()) {
    if (session.validUntil < now) {
      sessionStore.delete(key);
    }
  }
}, 5 * 60 * 1000);

// HTTP server
const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin || '';
  const corsHeaders = getCorsHeaders(origin);

  // Health check
  if (req.url === '/health') {
    res.writeHead(200, {
      'Content-Type': 'text/plain',
      ...corsHeaders
    });
    res.end('OK');
    return;
  }

  // CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(200, corsHeaders);
    res.end();
    return;
  }

  // Handle HEAD requests - ttyd doesn't support them well
  if (req.method === 'HEAD') {
    res.writeHead(200, {
      'Content-Type': 'text/html',
      ...corsHeaders
    });
    res.end();
    return;
  }

  const token = getToken(req);
  const authHeader = getAuthHeader(req);

  console.log(`[REQUEST] ${req.method} ${req.url} - Token: ${token ? 'present' : 'missing'}`);

  // Check if we have a valid cached session for this token
  let isValid = false;
  const cachedSession = token ? sessionStore.get(token) : null;

  if (cachedSession && cachedSession.validUntil > Date.now()) {
    isValid = true;
    console.log('[AUTH] Using cached session');
  } else {
    // Validate against API
    isValid = await validateSession(token, authHeader);

    // Cache valid sessions for 30 minutes
    if (isValid && token) {
      sessionStore.set(token, {
        authHeader,
        validUntil: Date.now() + 30 * 60 * 1000
      });
    }
  }

  if (!isValid) {
    console.log('[AUTH] Session invalid or expired');
    res.writeHead(401, {
      'Content-Type': 'application/json',
      ...corsHeaders
    });
    res.end(JSON.stringify({
      error: 'Unauthorized',
      message: 'Invalid or expired terminal session'
    }));
    return;
  }

  console.log('[AUTH] Session valid, proxying to ttyd');

  // Set session cookie for subsequent requests (WebSocket, assets)
  const cookieHeader = `terminal_session=${token}; Path=/; HttpOnly; SameSite=None; Secure; Max-Age=1800`;
  res.setHeader('Set-Cookie', cookieHeader);

  proxy.web(req, res);
});

// WebSocket upgrade
server.on('upgrade', async (req, socket, head) => {
  const token = getToken(req);
  const authHeader = getAuthHeader(req);

  console.log(`[UPGRADE] WebSocket - Token: ${token ? 'present' : 'missing'}`);

  // Check cached session first
  let isValid = false;
  const cachedSession = token ? sessionStore.get(token) : null;

  if (cachedSession && cachedSession.validUntil > Date.now()) {
    isValid = true;
    console.log('[AUTH] WebSocket using cached session');
  } else {
    isValid = await validateSession(token, authHeader);
    if (isValid && token) {
      sessionStore.set(token, {
        authHeader,
        validUntil: Date.now() + 30 * 60 * 1000
      });
    }
  }

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
