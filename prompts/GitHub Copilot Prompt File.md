---
mode: ask
description: Plan a software solution by defining its architecture, where it runs, authentication, and target environment.
---

# Solution planning

Help me plan a software solution. Start by understanding the goal, users, constraints, and existing project context. Inspect the workspace before making assumptions. Ask focused questions when a decision materially affects the design; otherwise state a reasonable assumption and continue.

## 1. Plan

- Summarize the problem, intended users, and desired outcomes.
- Identify functional requirements, non-functional requirements, constraints, and open questions.
- Break the work into milestones and actionable implementation steps.
- Call out risks, dependencies, and decisions that need confirmation.

## 2. Architecture

Recommend a suitable architecture and explain why it fits the requirements. Cover the relevant components, data flow, storage, APIs or integrations, deployment shape, observability, and scaling needs. Prefer the simplest design that meets the stated requirements. Identify alternatives and trade-offs where they matter.

## 3. Select where the solution runs

Evaluate these placement options against the requirements:

- **Workspace:** runs as part of the existing development workspace or project environment.
- **Local:** runs on a developer's or user's machine.
- **Full cloud:** application services and required data services run in the cloud.

Recommend one, explain the trade-offs (availability, privacy, latency, cost, operations, and offline use), and describe any hybrid arrangement if needed. Do not assume “workspace” means a production hosting target; clarify what it means for this project.

## 4. Authentication and authorization

Determine whether the solution needs sign-in, service-to-service identity, or both. Recommend an approach for the selected environment. Cover identity provider, sign-in flow, roles or permissions, secret and token storage, least privilege, local development credentials, and any user or service onboarding. Never put credentials or secrets in source code, prompt output, or committed configuration. If authentication is unnecessary, explain why.

## 5. Select the environment

Evaluate the applicable target environment(s):

- **Azure:** Azure hosting and managed services.
- **Local:** local development or local execution.
- **GitHub:** GitHub-based source control and automation, such as GitHub Actions; distinguish CI/CD from application hosting.

Recommend an environment or combination, and map each component to it. Explain deployment, configuration, secret management, networking, monitoring, and expected operational ownership at a high level. Avoid assuming that GitHub itself hosts the application.

## Deliverable

Present the result in this order:

1. Goal and assumptions
2. Requirements and open questions
3. Recommended architecture (include a concise text diagram when useful)
4. Placement decision: workspace, local, or full cloud
5. Environment decision: Azure, local, GitHub, or a combination
6. Authentication and authorization design
7. Milestones, risks, and next decisions

Keep recommendations tied to the requirements. Separate confirmed facts from assumptions, and do not start implementing until I ask you to proceed.
