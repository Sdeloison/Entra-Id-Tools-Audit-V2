# Data dictionary and implementation status

## Common report envelope

Each section has `status` (`complete`, `partial`, `not_configured`, or `failed`), `collectedAtUtc`, optional `windowStartUtc`/`windowEndUtc`, `recordCount`, `warnings`, sanitized `errors`, and `records`. Records carry a stable source ID, source, collection timestamp, and `collectionStatus`. Schema changes require a `schemaVersion` increment and backward-compatible readers.

## Status by domain

| Domain / requested information | Status | Source and limits |
|---|---|---|
| Users: object ID, display name, UPN, type, enabled, created; guest indicator | Partial | Graph v1.0 users; source fields available; sign-in activity is a separate bounded sign-in log signal |
| User successful sign-in observation | Partial | Graph v1.0 sign-in logs; `AuditLog.Read.All`, Entra ID P1/P2, tenant retention, lookback and result cap apply. Interactive/non-interactive event types are retained when returned. Not proof of use |
| User sign-in activity (`signInActivity`) | Not collected | The property is not queried. Access requires the user-list permission plus `AuditLog.Read.All` for sign-in activity and an eligible Entra ID P1/P2 license; verify current tenant/user licensing and endpoint requirements before opt-in. Microsoft Graph documents `lastSignInDateTime` as an attempt (including failures); `lastSuccessfulSignInDateTime` is available from December 2023 and is not backfilled. `lastNonInteractiveSignInDateTime` history is documented from May 2020; successful sign-in history from April 2020. Null can mean never signed in, unavailable permissions/data, or history outside those limits; it is not proof of non-use |
| User direct/transitive groups | Partial | Group direct member IDs are collected; no transitive traversal, nesting resolution, dynamic membership evaluation, or owner list |
| User active/eligible directory roles | Not collected | No role assignments or PIM eligible assignments are queried |
| User Azure RBAC roles | Partial / not joined | Subscription-scope ARM role query is separate; principal-to-user joins and management-group coverage are not implemented |
| User Microsoft 365 roles | Not collected | No Microsoft 365 role assignment API query |
| User F&O roles | Not configured | No tenant-approved F&O integration |
| User licenses/service plans/group assignment source | Not collected | License details and group-based source are not queried |
| User enterprise-app assignments/app roles | Not collected | User/group assignment and service-principal grant relationships are not queried |
| User Conditional Access exposure/results | Partial | Policy targets are reported separately; no per-user evaluation or sign-in-result join |
| Group inventory and direct member IDs/types | Partial | Graph v1.0 groups/members; capped group count and 500 direct IDs per group; no nested/transitive traversal, owners, or complete visibility/relationship analysis |
| Group Azure RBAC roles | Partial / not joined | Configured subscription RBAC is separate; assignments are not joined to group IDs |
| Group directory/Microsoft 365 roles | Not collected | No directory role, eligible role, or Microsoft 365 role relationships are queried |
| Group F&O roles and licenses | Not configured / not collected | F&O integration not configured; group license/service plan assignment data is not queried |
| Group Conditional Access includes/excludes | Partial | Policy definitions are available in the Conditional Access section, but direct versus nested group targeting is not resolved |
| Conditional Access policy definitions and targeting | Partial | Graph v1.0 policies; policy target definitions only, not applied/effective per-user policy |
| Conditional Access change history and usage | Not collected | Audit-log change history and sign-in applied-policy results are not queried; applied results need `AuditLog.Read.All` plus a supported Conditional Access read permission and retained sign-in events |
| Enterprise applications/service principals | Partial | Graph v1.0 object inventory only; grants, owners, credentials, role links, app assignments, and usage telemetry are not fully implemented |
| App registrations and requested permissions | Partial | Graph v1.0 object inventory includes requested permissions/declarations; actual grants, owners, credential metadata, service-principal instances, and cross-tenant visibility are not fully collected |
| Azure RBAC assignments | Partial | ARM/Az on configured accessible subscriptions; no assertion of all tenant subscriptions or management-group coverage; assignments are not joined to principals |
| Managed identity/resource inventory | Partial | Azure Resource Graph on configured subscriptions, capped at 1,000 resources per subscription query; role grants, permission grants, and usage telemetry are not joined |
| Directory role assignments/eligible assignments | Not collected | Requires separately validated Graph API/permissions; eligible assignments not implemented |
| M365 role assignments | Not collected | Not implemented |
| Access packages/catalogs/requests | Not configured | Entitlement Management APIs and licensing must be validated/configured |
| Dynamics 365 F&O roles | Not configured | F&O does not expose all role assignments through Microsoft Graph. No general-purpose, built-in supported role-assignment API and least-privilege permission set has been validated for this implementation. Configure only a tenant-approved, documented F&O integration (for example, a supported OData/data entity or service explicitly exposing role assignments) and its dedicated read-only F&O security role; otherwise leave `not_configured`. Do not query the application database directly or infer roles |
| Credential/key metadata | Not collected | Secret values/private material are never collected |
| Managed identity and workload usage | Not collected | Sign-in/activity log join and per-source retention are not implemented |

Successful sign-in events can be bounded by time range and maximum count; no observed event in the window is not equivalent to `unused`. Access to Microsoft Entra activity reports requires an eligible P1/P2 tenant and `AuditLog.Read.All`; Graph's sign-in API documents that as its least-privileged application permission. If sign-in Conditional Access details are later collected, add a supported CA read permission (for example, `Policy.Read.All`) as well. Report section status explains unavailable APIs, permission failures, configured-scope limits, and truncation.

References: [signInActivity resource](https://learn.microsoft.com/en-us/graph/api/resources/signinactivity?view=graph-rest-1.0), [list users](https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0), [list sign-in logs and least-privileged permission](https://learn.microsoft.com/en-us/graph/api/signin-list?view=graph-rest-1.0), and [analyze activity logs with Microsoft Graph](https://learn.microsoft.com/en-us/entra/identity/monitoring-health/howto-analyze-activity-logs-with-microsoft-graph).

## Workload and managed-identity field-level status

| Object / field group | Status | API, scope, permission, or telemetry prerequisite |
|---|---|---|
| Managed identity type, principal/client IDs, attached Azure resource IDs/type/subscription/resource group/location | Partial | Azure Resource Graph within configured subscriptions; Azure Reader on each scope; capped at 1,000 resources per subscription per query. User-assigned identity resource IDs and service-assigned attachments are reported separately |
| Managed identity Azure RBAC roles, inherited status, broad scopes | Partial / not joined | Azure RBAC section queries configured subscription scopes; assignments are not joined to each identity, management groups/out-of-scope subscriptions may be absent |
| Managed identity Graph/API application roles | Not collected | Requires Graph service-principal app-role assignment APIs and permissions; grants are not evidence that permissions were exercised |
| Managed identity Entra directory active/eligible roles | Not collected | Requires separately validated role-management API/permission; eligible assignment support is not implemented |
| Managed identity usage / sign-ins | Not collected | Would require service-principal sign-in logs, `AuditLog.Read.All`, a configured lookback, and tenant retention/licensing; missing data cannot establish non-use |
| Enterprise application object fields and publisher metadata | Partial | Graph v1.0 `/servicePrincipals`, `Application.Read.All`; owner relationships and credential metadata not collected |
| Enterprise application app-role assignments / delegated grants | Not collected | Requires service-principal app-role assignment and OAuth2 permission-grant APIs; actual grants must remain distinct from requested permissions |
| Enterprise application Entra/Azure role assignments | Not collected / separate partial | Directory roles require role-management API permissions; Azure RBAC is collected separately and not joined by principal |
| Enterprise application user/group assignments, assignment-required state, Conditional Access workload policies | Not collected | Graph assignment APIs and workload-identity Conditional Access support have not been implemented |
| Enterprise application credentials and sign-in usage | Not collected | Metadata-only credential access and bounded service-principal sign-in logs need validated permissions/retention; no secret/private-key material is requested |
| App registration object fields, requested permissions, declared app roles/scopes | Partial | Graph v1.0 `/applications`, `Application.Read.All`; requested API permissions are not proof of consent |
| App registration service principal instances, actual grants, directory/Azure roles | Not collected / separate partial | Tenant service principal discovery and grant/role APIs are not joined to application objects; cross-tenant instances may not be visible |
| App registration owners, credential metadata, sign-in usage | Not collected | Owner/credential metadata and bounded service-principal sign-in logs require additional collection and permission/retention validation |

Usage evidence prerequisites above are not interchangeable: user sign-in logs use Graph `AuditLog.Read.All`, service-principal sign-in logs use the same Graph audit-log permission, and managed identity usage must be identified from managed-identity sign-in events and relevant Azure logs. All are bounded by the selected lookback, tenant licensing, and source retention; no event in a window cannot establish that an identity is unused.
