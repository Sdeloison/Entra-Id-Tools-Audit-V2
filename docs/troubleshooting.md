# Troubleshooting

| Symptom | Check |
|---|---|
| Graph connection or 403 | Confirm the Automation UAMI, admin-consented application permissions, endpoint permission requirements, and token audience. Permission failures should appear as section errors, not empty success. |
| Sign-in logs unavailable | Confirm `AuditLog.Read.All`, tenant licensing, retention, lookback, and query maximum. This section can fail independently from user inventory. |
| Azure resources/RBAC missing | Confirm the exact subscription IDs and Reader role at each scope. The collector cannot see subscriptions not configured or authorized. |
| Blob upload denied | Confirm Automation identity `Storage Blob Data Contributor` at the report container; shared-key access is disabled. |
| Dashboard gives 401/403 | Verify SPA redirect URI, tenant/client/audience settings, token audience, group claim configuration, and allowed reader group ID. Group overage without a group claim is denied by design. |
| No dashboard reports | Confirm dashboard identity `Storage Blob Data Reader`, container name, and reports exist under `runs/`. |
| Truncated records | Review `maxGraphRecords`, `maxGroupsForMemberships`, warnings, job duration, and throttling. Raise caps deliberately; do not remove bounds. |

Never troubleshoot by logging access tokens, exporting credentials, enabling anonymous blobs, or granting broad write permissions.
