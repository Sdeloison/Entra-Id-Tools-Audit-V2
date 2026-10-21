# Operations

## Running and monitoring

- Run only after confirming Graph grants, Azure Reader scopes, storage container role, and configured limits.
- `scripts/Invoke-ManualAudit.ps1` starts a runbook job; the runbook itself authenticates to Graph/ARM with its managed identity.
- Reports are JSON blobs under `runs/YYYY/MM/DD/`. Each report includes a schema version, run ID, UTC timestamp, configured window, section envelope, record count, warnings, and sanitized errors.
- Inspect Graph/ARM connection statuses and every section before interpreting records. The runbook attempts Graph and ARM authentication independently and continues independent sections. `partial`, `not_configured`, and `failed` are not empty successful results.

## Boundaries and telemetry

Default lookback is 30 days; Graph result count is capped at 5,000 and group member expansion at 500 groups. Increase only after assessing throttling, personal-data exposure, job duration, and report size. Sign-in logs are not full history; retention and license affect visibility. Graph requests retry throttling and transient server failures but collection does not checkpoint between pages; rerun after failure. A missing/no event result never proves an account or identity is unused.

The initial collector does not join Conditional Access results from sign-ins, does not resolve nested group graph traversal, and does not collect F&O, access-package requests, role eligibility, credential values, or secrets. Credential material is never requested.

## Retention and response

Set a storage lifecycle policy according to organizational requirements (not provisioned by default). Restrict report reader group membership; audit Blob access; protect exports; delete data only under approved retention/legal-hold rules. A report contains sensitive personal and security information.

For errors, use the per-section sanitized error code/type and the Automation job's platform diagnostics. Do not enable verbose token logging. Review throttling and permissions before increasing retries or limits. Consult [troubleshooting](troubleshooting.md).
