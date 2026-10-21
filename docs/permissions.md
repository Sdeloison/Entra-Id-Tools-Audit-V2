# Permissions and consent

Use the least-privileged supported permissions for each required data source and confirm them against current Microsoft Graph documentation before use. Permissions below describe the intended scopes; tenant configuration, licensing, and endpoint availability can further limit results. Do not grant write permissions to the collector.

| Collector operation | API / resource | Runtime permission or role | Status / notes |
|---|---|---|---|
| User inventory and group inventory | Graph v1.0 `/users`, `/groups` | Graph application `User.Read.All`, `Group.Read.All` | User/group properties only; personal data minimized |
| Group direct member IDs | Graph v1.0 `/groups/{id}/members` | `GroupMember.Read.All` | Bounded to configured group limit; nested/transitive expansion not implemented |
| Conditional Access policies | Graph v1.0 `/identity/conditionalAccess/policies` | `Policy.Read.All` | Policy targeting only; targeting is not effective policy evaluation |
| Service principals and application objects | Graph v1.0 `/servicePrincipals`, `/applications` | `Application.Read.All` | Inventory only; grants and credential metadata are not claimed as collected |
| Sign-in log events (bounded lookback) | Graph v1.0 `/auditLogs/signIns` | `AuditLog.Read.All` | Tenant licensing and retention apply; limited by configured maximum records |
| User `signInActivity` field (not currently queried) | Graph v1.0 `/users?$select=signInActivity` | Validate user-list least privilege (`User.Read.All`) and the field-specific Graph requirements before enabling | The property has historical and backfill limits; null is not proof of non-use. This collector currently uses bounded sign-in log events instead |
| Managed identity resource discovery | Azure Resource Graph on configured subscriptions | Azure `Reader` on each configured subscription | ARM resource visibility only; does not collect identity usage or Graph grants |
| Directory role assignments | Graph `/roleManagement/directory/roleAssignments` | `RoleManagement.Read.Directory` | Not currently collected; eligible assignments not collected |
| Azure RBAC assignments/resources | ARM via Az PowerShell | `Reader` on each configured subscription | Does not imply visibility of every tenant subscription or management group |
| Report upload | Blob data plane | `Storage Blob Data Contributor` on report container only | Only collector write permission; no storage account key |
| Dashboard report read | Blob data plane | `Storage Blob Data Reader` on report container only | Separate dashboard identity |
| Dashboard access | Entra SPA registration | Reader group membership claim and token audience | No backend client secret; group claims must be configured and tested |
| Access packages | Graph Identity Governance | Not configured | Requires supported endpoint, API permission and entitlement-management licensing verification |
| Dynamics 365 F&O | F&O-specific supported integration | Not configured | No generic built-in role-assignment API/least-privilege permission set is asserted here. Configure a tenant-approved supported OData/data entity or service exposing these assignments and an F&O read-only security role; Graph does not expose all F&O role assignments |

## Runtime identity bootstrap

1. Deploy resources and obtain the automation user-assigned managed identity principal ID.
2. An authorized Entra administrator verifies each Graph permission above against current endpoint docs and the tenant's licensing.
3. Review requested app roles, approve them, and use `scripts/Grant-GraphPermissions.ps1 -WhatIf` to inspect the intended assignment. Only then explicitly use `-Apply` and confirm.
4. Assign Azure `Reader` only on subscriptions selected in configuration. Assign `Storage Blob Data Contributor` only on the report container.
5. Assign dashboard `Storage Blob Data Reader` only on that container. Do not give the dashboard collector permissions.

`Grant-GraphPermissions.ps1` is a privileged bootstrap tool; it is never called by CI or the runbook. It uses administrative Graph scopes to create grants only when the operator supplies `-Apply`. The collector must not receive `Directory.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `AppRoleAssignment.ReadWrite.All`, or tenant-object write permissions.

The Graph sign-in logs API documents `AuditLog.Read.All` as its least-privileged application permission. Microsoft Entra activity log analysis also requires an eligible P1/P2 tenant; sign-in event data is bounded by tenant retention. Applied Conditional Access details additionally require an appropriate Conditional Access read permission such as `Policy.Read.All`. These prerequisites do not make policy targeting an effective-policy evaluation.

## Review checklist before admin consent

- Confirm publisher, source, requested permission names, documented endpoint requirements, and tenant-wide effects.
- Confirm collector managed identity object ID and that it is not the dashboard identity.
- Verify no Graph application permission has a write suffix or is broader than required.
- Confirm data retention, report readers, configured subscription scope, licensing, and sign-in log retention.
- Record approval and consent time; periodically review and remove grants no longer needed.
