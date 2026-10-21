# Repository instructions

- Preserve read-only collection. Never add tenant-object mutations, permission grants, remediation, or policy changes to audit execution.
- Prefer managed identity and Azure RBAC; never add credentials, tokens, tenant reports, or real tenant identifiers to source control.
- Represent incomplete collection with explicit coverage status and sanitized errors; never replace failed collection with an empty successful result.
- Bound Graph and ARM calls, honor paging and throttling, and document licensing, permissions, retention, and configured-scope limits.
- Run Pester, PSScriptAnalyzer, Bicep build, and dashboard tests for relevant changes. Do not deploy Azure resources or grant consent in CI.
