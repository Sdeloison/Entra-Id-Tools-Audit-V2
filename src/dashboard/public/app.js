/* global msal */
'use strict';

const message = document.getElementById('message');
const list = document.getElementById('report-list');
const sectionsElement = document.getElementById('sections');
let scope = '';
let msalApp = null;
let selectedReport = null;
let nextPageToken = null;
const previousPageTokens = [];

async function initializeAuth() {
  if (!window.msal) throw new Error('Microsoft authentication library failed to load.');
  const response = await fetch('/config.json', { cache: 'no-store' });
  if (!response.ok) throw new Error('Dashboard configuration is unavailable.');
  const config = await response.json();
  const tenantId = config.tenantId || '';
  const clientId = config.clientId || '';
  const audience = config.audience || '';
  if (!tenantId || !clientId || !audience) throw new Error('Dashboard Entra settings are not configured.');
  scope = `${audience.replace(/\/$/, '')}/access_as_user`;
  msalApp = new msal.PublicClientApplication({
    auth: { clientId, authority: `https://login.microsoftonline.com/${tenantId}`, redirectUri: window.location.origin },
    cache: { cacheLocation: 'sessionStorage', storeAuthStateInCookie: false }
  });
  await msalApp.initialize();
  await msalApp.handleRedirectPromise();
}

async function accessToken() {
  if (!msalApp) await initializeAuth();
  const account = msalApp?.getAllAccounts()[0];
  if (!account || !scope) throw new Error('Dashboard sign-in configuration is missing.');
  try {
    return (await msalApp.acquireTokenSilent({ account, scopes: [scope] })).accessToken;
  } catch {
    return (await msalApp.acquireTokenPopup({ account, scopes: [scope] })).accessToken;
  }
}

async function api(path) {
  const token = await accessToken();
  const response = await fetch(path, { headers: { authorization: `Bearer ${token}` }, cache: 'no-store' });
  if (!response.ok) throw new Error(`Dashboard request failed (${response.status}).`);
  return response.json();
}

function renderReport(report) {
  sectionsElement.replaceChildren();
  const query = document.getElementById('search').value.toLocaleLowerCase();
  const status = document.getElementById('status-filter').value;
  const sections = Object.entries(report.sections || {}).filter(([name, section]) => {
    const searchable = `${name} ${section.status} ${(section.warnings || []).join(' ')} ${JSON.stringify(section.records || [])}`;
    return (!status || section.status === status) && (!query || searchable.toLocaleLowerCase().includes(query));
  });
  const summary = document.getElementById('summary');
  summary.replaceChildren();
  for (const [label, value] of [['Run completed (UTC)', report.completedAtUtc], ['Window start (UTC)', report.windowStartUtc], ['Window end (UTC)', report.windowEndUtc], ['Sections shown', String(sections.length)]]) {
    const card = document.createElement('div');
    card.className = 'card';
    const strong = document.createElement('strong');
    strong.textContent = label;
    const valueElement = document.createElement('div');
    valueElement.textContent = value || 'Not available';
    card.append(strong, valueElement);
    summary.append(card);
  }
  for (const [name, section] of sections) {
    const article = document.createElement('article');
    article.className = 'section';
    const heading = document.createElement('h3');
    heading.textContent = name;
    const statusElement = document.createElement('p');
    statusElement.className = 'status';
    statusElement.textContent = `Status: ${section.status}; records: ${section.recordCount}; collected: ${section.collectedAtUtc || 'unknown'}`;
    const warning = document.createElement('pre');
    const warnings = (section.warnings || []).slice();
    for (const error of section.errors || []) warnings.push(`${error.code}: ${error.message}`);
    warning.textContent = warnings.join('\n') || 'No warnings or errors.';
    const recordsButton = document.createElement('button');
    recordsButton.type = 'button';
    recordsButton.textContent = `View records (${section.recordCount || 0})`;
    const records = document.createElement('pre');
    records.hidden = true;
    recordsButton.addEventListener('click', () => {
      records.hidden = !records.hidden;
      records.textContent = records.hidden ? '' : JSON.stringify((section.records || []).slice(0, 100), null, 2);
      if (!records.hidden && (section.records || []).length > 100) {
        records.textContent += `\n\nShowing first 100 of ${section.records.length} records. Export the report for the complete section.`;
      }
    });
    article.append(heading, statusElement, warning, recordsButton, records);
    sectionsElement.append(article);
  }
}

async function loadReports() {
  try {
    await loadReportPage();
    const latest = await api('/api/latest');
    const option = document.createElement('option');
    option.value = `latest:${latest.runId}`;
    option.textContent = `Latest completed report — ${latest.completedAtUtc || 'unknown time'}`;
    list.prepend(option);
    list.value = option.value;
    selectedReport = latest;
    renderReport(latest);
    document.getElementById('download').disabled = false;
    message.textContent = 'Latest completed report loaded. Review section coverage and warnings before drawing conclusions.';
  } catch (error) {
    message.textContent = error.message;
  }
}

async function loadReportPage(token) {
  try {
    const result = await api(`/api/reports${token ? `?continuation=${encodeURIComponent(token)}` : ''}`);
    list.replaceChildren();
    nextPageToken = result.nextPageToken;
    document.getElementById('previous-page').disabled = previousPageTokens.length === 0;
    document.getElementById('next-page').disabled = !nextPageToken;
    for (const report of result.reports) {
      const option = document.createElement('option');
      option.value = report.name;
      option.textContent = `${report.lastModified || 'Unknown time'} — ${report.name}`;
      list.append(option);
    }
    if (result.reports.length === 0) message.textContent = 'No reports are available on this page.';
  } catch (error) {
    message.textContent = error.message;
  }
}

async function loadSelected() {
  if (!list.value) return;
  if (list.value.startsWith('latest:')) return;
  try {
    selectedReport = await api(`/api/report?name=${encodeURIComponent(list.value)}`);
    renderReport(selectedReport);
    document.getElementById('download').disabled = false;
    message.textContent = 'Report loaded. Review section coverage and warnings before drawing conclusions.';
  } catch (error) {
    message.textContent = error.message;
  }
}

document.getElementById('sign-in').addEventListener('click', async () => {
  try {
    if (!msalApp) await initializeAuth();
    await msalApp.loginPopup({ scopes: [scope] });
    document.getElementById('sign-in').hidden = true;
    document.getElementById('sign-out').hidden = false;
    await loadReports();
  } catch (error) { message.textContent = error.message; }
});
document.getElementById('sign-out').addEventListener('click', () => msalApp?.logoutPopup());
list.addEventListener('change', loadSelected);
document.getElementById('next-page').addEventListener('click', async () => {
  if (!nextPageToken) return;
  previousPageTokens.push(nextPageToken);
  await loadReportPage(nextPageToken);
});
document.getElementById('previous-page').addEventListener('click', async () => {
  if (previousPageTokens.length < 2) {
    previousPageTokens.length = 0;
    await loadReportPage();
    return;
  }
  previousPageTokens.pop();
  await loadReportPage(previousPageTokens[previousPageTokens.length - 1]);
});
document.getElementById('search').addEventListener('input', () => selectedReport && renderReport(selectedReport));
document.getElementById('status-filter').addEventListener('change', () => selectedReport && renderReport(selectedReport));
document.getElementById('download').addEventListener('click', () => {
  if (!selectedReport) return;
  const url = URL.createObjectURL(new Blob([JSON.stringify(selectedReport, null, 2)], { type: 'application/json' }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `${selectedReport.runId || 'audit-report'}.json`;
  anchor.click();
  URL.revokeObjectURL(url);
});
