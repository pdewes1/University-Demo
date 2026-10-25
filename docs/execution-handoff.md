# Execution handoff: Advisor Agent

A one-page brief for the implementation team taking this from demo org to production.

## Decision

Build the **Advisor Agent** as an Agentforce employee agent for academic advisors. It is grounded in a Data 360 data graph over Banner and Canvas, which stay in Snowflake with zero copy. It takes action in Salesforce (tasks, notes, record updates) and in Calendly (single-use booking links). The **Admissions Agent** is phase 2.

**Business owner:** Provost's office (advising). **Measure:**

- advisor prep time per student
- days from an engagement drop to outreach
- share of flagged students who book a meeting

## Scope

| In scope (built and validated) | Out of scope / phase 2 |
|---|---|
| Find, review and update the advisor's own students | Admissions Agent |
| Student 360 summary from the data graph (financial aid status only) | Student-facing agent or channel |
| Outreach email drafts (never auto-sent) with a single-use Calendly link | Sending email from Salesforce |
| Create Task and Log Note on the student | Calendly booking write-back (webhook) |
| Agentforce panel (record page and Home) and Slack | Any write-back to Banner or Canvas |

## System interfaces

| From → To | Mechanism | Owner |
|---|---|---|
| Banner, Canvas → Snowflake | Existing university integrations | University IT |
| Snowflake → Data 360 | Direct Access data streams (zero copy), key-pair auth | Data engineering |
| CRM → Data 360 | Salesforce CRM data stream (ingest) | Salesforce team |
| Data 360 → agent | Data graph `Student_360_Graph` via `ConnectApi.CdpQuery.getDataGraphData` in Apex | Salesforce team |
| Agent → LLM | Einstein Models API through the Trust Layer (`sfdc_ai__DefaultGPT4Omni`) | Salesforce team |
| Agent → Calendly | Named Credential `Calendly` → `POST /scheduling_links` | Salesforce team (Calendly admin owns the token) |
| Agent → Slack | Agentforce in Slack connection; Slack users mapped to Salesforce users | Slack admin and Salesforce team |

## Architectural assumptions

1. **Contact owner = assigned advisor.** All access checks use this. Education Cloud advisee or success-team relationships may be the correct production model.
2. **The Canvas user ID is the shared student key** across CRM (`Contact.Student_ID__c`), Banner and Canvas.
3. **Every advisor is a member of one Calendly organization**, so a single org-owner credential can create links on any advisor's meeting type.
4. **A 30-day window of activity is enough** for advising conversations. The engagement score covers all activity.

## Known risks

| Risk | Impact | Mitigation in place / needed |
|---|---|---|
| Data 360 doesn't filter on the advising relationship | One advisor could see another's student | **In place:** `StudentAccess` check runs first in every action. **Needed:** Apex tests that keep it there. |
| Wrong identity merge | One student's data shown as another's | Exact Student ID rule ranks first. **Needed:** review the fuzzy name rules and sample merges. |
| Financial aid amounts copied into Data 360 by the graph | Amounts stored outside Banner even though the agent can't see them | **In place:** Apex allow-list, so advisors and the agent get status only. **Needed:** drop amount fields from the graph projection. |
| Calendly token is over-privileged and person-owned | Leak or a staff change breaks booking | **Needed:** OAuth app on a service account; rotate. |
| Unused single-use links pile up | Calendly clutter, stray bookable links | **Needed:** create the link at send time, or expire links. |
| Data graph refreshes daily | Agent can be up to a day behind | Acceptable for advising; enable incremental refresh if needed. |

## Unknowns

- Volume and cost at real scale: Data 360 credits for federation and graph refresh, plus Agentforce actions per advisor per day.
- Agent behaviour under adversarial prompts (Testing Center suite not yet run).
- Slack link rendering and formatting for email drafts.

## Exit conditions for build

- [ ] Apex tests at 75% or more coverage, including the refusal paths, in CI
- [ ] Agent test suite (Testing Center) passes the persona matrix, adversarial rows included
- [ ] Second advisor tested end to end with their own Agentforce license
- [x] Financial aid visibility decided: advisors see status only (FAFSA, verification, SAP)
- [ ] Calendly moved to OAuth on a service account; personal token revoked
- [ ] Enhanced Notes enabled; notes confirmed as `ContentNote`
- [ ] Baselines captured for the three outcome measures

## Fallbacks

- **Federation too slow:** enable acceleration on the Snowflake streams, or copy only the objects the graph uses.
- **Identity merges unreliable:** drop the fuzzy rules and match on Student ID only.
- **Calendly unavailable:** the email still drafts and asks the student to reply (already built).
