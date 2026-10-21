# Dashboard

Node.js 22 web application with an authenticated JSON API and accessible report summary UI. The static sign-in shell is public, but report APIs and data require a signed Entra v2 access token with the configured tenant, audience, SPA authorized party, delegated scope, and reader group claim. Tokens are validated with Microsoft's tenant JWKS. Backend Blob reads use `DefaultAzureCredential` and the App Service system-assigned identity.

## Entra setup (operator action)

1. Register a single-tenant application. Add a SPA redirect URI equal to the deployed App Service HTTPS origin. Enable the `groups` optional token claim for the access token.
2. Expose a delegated API scope named `access_as_user`; set `DASHBOARD_AUDIENCE` to the app ID URI (commonly `api://<application-client-id>`). Authorize the SPA to request that scope.
3. Add required settings `DASHBOARD_TENANT_ID`, `DASHBOARD_CLIENT_ID` (SPA client ID), `DASHBOARD_AUDIENCE`, and `DASHBOARD_ALLOWED_GROUP_ID` to the App Service. They contain identifiers, not secrets. The unauthenticated `/config.json` route exposes only the first three public identifiers; it does not expose the allowed group ID.
4. Assign the approved reader group to the app/API role or ensure group membership appears in the access token. Configure group claims without overage ambiguity; missing group claims are denied.
5. Assign the App Service identity `Storage Blob Data Reader` at the report container (Bicep creates this role). Test unauthenticated 401, wrong-group 403, and authorized report read.
6. Publish the application (`npm ci --omit=dev`, then deploy the folder). Set the App Service startup command to `npm start` if required by the host.

There is no client secret. The SPA uses authorization code with PKCE via Microsoft's MSAL browser library, and the backend never trusts browser-provided identity headers. The dashboard loads public, non-secret identifiers from `/config.json`; do not pass them through production query strings.

Reports are capped at 5 MiB each and historical report listings use 50-item Blob pages with continuation tokens. The runbook also writes a `latest.json` pointer so the dashboard can load the latest completed report without scanning all history. The UI shows report timestamps, section statuses, warnings and record counts; record JSON is rendered with `textContent`, not HTML injection. Filters apply to section names, status, warnings, and serialized record values. Exports contain sensitive data and should be handled under policy.
