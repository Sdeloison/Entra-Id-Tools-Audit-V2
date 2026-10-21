'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { createRemoteJWKSet, jwtVerify } = require('jose');
const { DefaultAzureCredential } = require('@azure/identity');
const { BlobServiceClient } = require('@azure/storage-blob');

const PORT = Number(process.env.PORT || 8080);
const tenantId = process.env.DASHBOARD_TENANT_ID;
const clientId = process.env.DASHBOARD_CLIENT_ID;
const audience = process.env.DASHBOARD_AUDIENCE;
const allowedGroupId = process.env.DASHBOARD_ALLOWED_GROUP_ID;
const storageAccount = process.env.AZURE_STORAGE_ACCOUNT;
const containerName = process.env.AZURE_STORAGE_CONTAINER;
const issuer = tenantId ? `https://login.microsoftonline.com/${tenantId}/v2.0` : '';
const jwks = tenantId
  ? createRemoteJWKSet(new URL(`https://login.microsoftonline.com/${tenantId}/discovery/v2.0/keys`))
  : null;

function sendJson(res, status, value) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  });
  res.end(JSON.stringify(value));
}

async function authenticate(req) {
  if (!tenantId || !clientId || !audience || !allowedGroupId || !jwks) {
    const error = new Error('Dashboard authentication is not configured.');
    error.status = 503;
    throw error;
  }
  const authorization = req.headers.authorization || '';
  const authParts = authorization.split(' ');
  if (authParts.length !== 2 || authParts[0] !== 'Bearer' || !authParts[1]) {
    const error = new Error('Authentication required.');
    error.status = 401;
    throw error;
  }
  let payload;
  try {
    ({ payload } = await jwtVerify(authParts[1], jwks, {
      issuer,
      audience,
      algorithms: ['RS256']
    }));
  } catch (cause) {
    const error = new Error('Authentication token is invalid or expired.');
    error.status = cause.code === 'ERR_JWKS_TIMEOUT' ? 503 : 401;
    throw error;
  }
  if (payload.tid !== tenantId || payload.azp !== clientId || payload.ver !== '2.0' ||
      typeof payload.scp !== 'string' || !payload.scp.split(' ').includes('access_as_user')) {
    const error = new Error('Token tenant or client is not authorized.');
    error.status = 403;
    throw error;
  }
  const groups = Array.isArray(payload.groups) ? payload.groups : [];
  if (!groups.includes(allowedGroupId)) {
    const error = new Error('Required dashboard reader group is absent.');
    error.status = 403;
    throw error;
  }
}

function getContainerClient() {
  if (!storageAccount || !containerName) throw new Error('Report storage configuration is missing.');
  const credential = new DefaultAzureCredential();
  const service = new BlobServiceClient(`https://${storageAccount}.blob.core.windows.net`, credential);
  return service.getContainerClient(containerName);
}

async function listReports(continuationToken) {
  if (continuationToken && (typeof continuationToken !== 'string' || continuationToken.length > 4096)) {
    const error = new Error('Invalid report page token.');
    error.status = 400;
    throw error;
  }
  const container = getContainerClient();
  const reports = [];
  const pages = container.listBlobsFlat({ prefix: 'runs/' }).byPage({ continuationToken, maxPageSize: 50 });
  const { value: page } = await pages.next();
  for (const blob of page.segment.blobItems) {
    if (!blob.name.endsWith('.json')) continue;
    reports.push({ name: blob.name, lastModified: blob.properties.lastModified?.toISOString() || null, size: blob.properties.contentLength || 0 });
  }
  return { reports, nextPageToken: page.continuationToken || null };
}

async function readReport(name) {
  if (typeof name !== 'string' || !/^runs\/\d{4}\/\d{2}\/\d{2}\/[0-9TZ-]+-[0-9a-f-]+\.json$/i.test(name)) {
    const error = new Error('Invalid report identifier.');
    error.status = 400;
    throw error;
  }
  const container = getContainerClient();
  const blob = container.getBlobClient(name);
  const download = await blob.download();
  const chunks = [];
  let length = 0;
  for await (const chunk of download.readableStreamBody) {
    length += chunk.length;
    if (length > 5 * 1024 * 1024) {
      const error = new Error('Report exceeds the dashboard size limit.');
      error.status = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

async function readLatestReport() {
  const pointer = await readReportPointer();
  return readReport(pointer.blobName);
}

async function readReportPointer() {
  const container = getContainerClient();
  const download = await container.getBlobClient('latest.json').download();
  const chunks = [];
  let length = 0;
  for await (const chunk of download.readableStreamBody) {
    length += chunk.length;
    if (length > 16384) {
      const error = new Error('Report pointer exceeds the size limit.');
      error.status = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  const pointer = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (typeof pointer.blobName !== 'string' || !/^runs\/\d{4}\/\d{2}\/\d{2}\/[0-9TZ-]+-[0-9a-f-]+\.json$/i.test(pointer.blobName)) {
    throw new Error('Report pointer is invalid.');
  }
  return pointer;
}

const publicDir = path.join(__dirname, 'public');
const server = http.createServer(async (req, res) => {
  res.setHeader('x-content-type-options', 'nosniff');
  res.setHeader('x-frame-options', 'DENY');
  res.setHeader('referrer-policy', 'no-referrer');
  res.setHeader('strict-transport-security', 'max-age=31536000; includeSubDomains');
  res.setHeader('content-security-policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self' https://login.microsoftonline.com; frame-ancestors 'none'; base-uri 'none'");
  try {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    if (req.method === 'GET' && url.pathname === '/config.json') {
      return sendJson(res, 200, { tenantId, clientId, audience });
    }
    if (url.pathname.startsWith('/api/')) await authenticate(req);
    if (req.method === 'GET' && url.pathname === '/api/reports') {
      return sendJson(res, 200, await listReports(url.searchParams.get('continuation') || undefined));
    }
    if (req.method === 'GET' && url.pathname === '/api/latest') {
      return sendJson(res, 200, await readLatestReport());
    }
    if (req.method === 'GET' && url.pathname === '/api/report') {
      return sendJson(res, 200, await readReport(url.searchParams.get('name')));
    }
    if (req.method === 'GET' && url.pathname === '/healthz') {
      return sendJson(res, 200, { status: 'ok' });
    }
    if (req.method === 'GET' && url.pathname === '/vendor/msal-browser.min.js') {
      const vendorFile = path.join(__dirname, 'node_modules', '@azure', 'msal-browser', 'lib', 'msal-browser.min.js');
      const body = fs.readFileSync(vendorFile);
      res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'public, max-age=3600' });
      return res.end(body);
    }
    const requestedPath = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    const filePath = path.resolve(publicDir, requestedPath);
    if (!filePath.startsWith(`${publicDir}${path.sep}`) && filePath !== path.join(publicDir, 'index.html')) {
      return sendJson(res, 400, { error: 'Invalid path.' });
    }
    if (req.method !== 'GET') return sendJson(res, 405, { error: 'Method not allowed.' });
    const body = fs.readFileSync(filePath);
    const extension = path.extname(filePath);
    const contentType = {
      '.html': 'text/html; charset=utf-8',
      '.js': 'text/javascript; charset=utf-8',
      '.css': 'text/css; charset=utf-8'
    }[extension] || 'application/octet-stream';
    res.writeHead(200, { 'content-type': contentType, 'cache-control': 'no-store' });
    return res.end(body);
  } catch (error) {
    const status = Number.isInteger(error.status) ? error.status : (error.code === 'RestError' ? 503 : 500);
    return sendJson(res, status, { error: status >= 500 ? 'Request could not be completed.' : error.message });
  }
});

if (require.main === module) server.listen(PORT, '0.0.0.0');

module.exports = { authenticate, listReports, readLatestReport, readReport, server };
