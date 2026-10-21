# Architecture

## Components and flow

```text
Azure Automation PowerShell 7.2 (UAMI)
  ├─ Microsoft Graph v1.0 (application permissions; read-only)
  ├─ ARM/Azure Resource Manager (read-only RBAC on configured subscriptions)
  └─ Blob Storage (write only to audit container; Entra data-plane RBAC)
          │ versioned JSON, private container, run-partitioned names
          ▼
App Service dashboard (system-assigned identity; Blob Data Reader)
  ├─ Browser signs in with Entra SPA authorization-code + PKCE (no client secret)
  ├─ Node API validates issuer, signature, audience, expiry, and allowed group
  └─ Browser receives report data only through authenticated API routes
```

Azure resources are defined in `infra/main.bicep`. The collector uses a user-assigned managed identity so Graph app-role grants can be reviewed independently from the Automation account. The dashboard has a distinct system-assigned identity and has no collector permissions. The report container is private, shared-key access is disabled, and blobs are accessed with Entra data-plane RBAC. Azure Resource Graph is used with a per-subscription limit for managed-identity resource discovery. The requested PowerShell 7.2 runtime is out of support; deployment documentation requires explicit runtime association and records a migration risk.

The storage endpoint is currently reachable over HTTPS from Azure service networks; data access still requires Entra authorization and the container is not anonymous. A private endpoint requires VNet integration for App Service and a network-connected Hybrid Runbook Worker for Automation; that optional network extension is not provisioned here. Do not describe this starter deployment as network-isolated.

## Design decisions

- **Read-only collection:** collection modules only call Graph GET operations and Azure read/list operations. Uploading the report is the sole write operation, scoped to the report container.
- **Coverage overclaims avoided:** sections separately report `complete`, `partial`, `not_configured`, or `failed`; missing permissions and unsupported integrations are not represented as empty successful data.
- **Bounded data:** `maxGraphRecords`, lookback window, and group expansion limits cap collection. Historical dashboard listings use 50-item pages; a private `latest.json` pointer avoids scanning unbounded report history. Report payloads contain identity/security personal data; retention and access must be controlled by the operator.
- **Token handling:** runbooks acquire Graph and ARM tokens through managed identity. Dashboard browser authentication uses a public SPA registration and PKCE; backend validates bearer access tokens and accesses Blob Storage through managed identity. No token is logged or persisted.
- **Dashboard deployment:** the reader group ID, tenant ID, SPA client ID, API audience, and app URL are explicit settings. Tenant app registrations and consent are separately configured by an authorized operator; deployment does not create credentials or grant consent.
- **Dashboard access:** the static shell is an unauthenticated sign-in surface only; every report API route and report read requires a validated delegated token and configured reader-group claim. No report content is available anonymously.
- **Scheduling:** deployment creates the Automation account but does not schedule or start a job. Import/publish the runbook and enable a schedule only after a successful manual run.

## Limitations

This repository is a starter implementation, not a claim of complete tenant entitlement analysis. App role grants, delegated grants, credential metadata, eligible role assignments, effective Conditional Access results, access-package requests, F&O roles, and usage telemetry are either partial or explicit placeholders. The exact status is in [data dictionary](data-dictionary.md). Azure scope coverage is limited to operator-configured subscriptions and accessible ARM resources.
