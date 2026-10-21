# Threat model

## Protected assets

Tenant identity inventory, sign-in observations, role assignments, policy definitions, report storage, automation identity, dashboard identity, and reader access.

## Threats and controls

| Threat | Controls |
|---|---|
| Unauthorized report access | Private container, shared-key access disabled, separate dashboard reader identity, authenticated dashboard API with signature/issuer/audience/group validation |
| Collector privilege escalation or tenant modification | Managed identity; read-only Graph/ARM collection permissions; no write operations in the runbook; privileged grants are separate operator workflow |
| Secret/token leakage | No secrets in source or browser; no token logging; report errors sanitized; managed identities for cloud resources |
| Overcollection / privacy exposure | Requested property selection, bounded lookback/page/result limits, minimal member identifiers, controlled retention and exports |
| Misleading audit conclusions | Explicit status, warnings, time windows, source and limitations; no “unused” conclusion from absent telemetry |
| CI supply-chain abuse | Pinned checkout action, read-only contents permission, no deployment credentials, tests only |
| Storage network exposure | TLS, private container, Entra RBAC, no account keys; public endpoint is currently enabled and network isolation is a documented limitation |

## Residual risks

The public Storage endpoint is not network-private; access requires Entra data-plane authorization. For network isolation, deploy private endpoints, private DNS, App Service VNet integration, and an Automation Hybrid Runbook Worker in that network. Dashboard group claims can be omitted for overage/large memberships; missing group claim denies access. Operators must verify deployed EasyAuth/token configuration, report retention, consent, and scope boundaries.
