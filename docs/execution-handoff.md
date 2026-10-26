# Execution handoff: Advisor Agent

A one-page brief for the implementation team taking this from demo org to production.

## Decision

Build the **Advisor Agent** as an Agentforce employee agent for academic advisors, to help the university keep more students enrolled through to graduation. Advisors find disengaged students late because the signals sit in Canvas, Banner and the CRM. The agent brings those signals together and shortens the time from an engagement drop to outreach.

It is grounded in a Data 360 data graph over Banner and Canvas, which stay in Snowflake with zero copy. It takes action in Salesforce (tasks, notes, record updates) and in Calendly (single-use booking links). The **Admissions Agent** is phase 2.

**Business owner:** Provost's office (advising).

**University goal (lagging):** term-to-term persistence, attrition rate, graduation rate.

**Pilot measures** (baselines captured before launch):

- advisor prep time per student
- days from an engagement drop to outreach
- share of flagged students who book a meeting

**Guardrails:** advisor edits per draft, access refusals, zero financial aid amounts exposed.

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
| Banner → CRM (nightly automation) | Nightly upsert of new and changed students into Contacts, keyed on Student ID: name, email, stage, level, and the assigned advisor as Contact owner. The search and access check depend on it. Demo org: loaded once | University IT |
| Snowflake → Data 360 | Direct Access data streams (zero copy), key-pair auth | Data engineering |
| CRM → Data 360 | Salesforce CRM data stream (ingest) | Salesforce team |
| Data 360 → agent | Data graph `Student_360_Graph` via `ConnectApi.CdpQuery.getDataGraphData` in Apex | Salesforce team |
| CRM → agent | Live `WITH USER_MODE` queries on Task, Event and Note for last advising contact and overdue follow-ups (not through the daily graph refresh) | Salesforce team |
| Agent → LLM | Einstein Models API through the Trust Layer (`sfdc_ai__DefaultGPT4Omni`). The Trust Layer also covers the agent's own reasoning calls; it isn't drawn on the diagrams | Salesforce team |
| Agent → Calendly | Named Credential `Calendly` → `POST /scheduling_links` | Salesforce team (Calendly admin owns the token) |
| Agent → Slack | Agentforce in Slack connection; Slack users mapped to Salesforce users | Slack admin and Salesforce team |

## Architectural assumptions

1. **Contact owner = assigned advisor.** All access checks use this, and it is the only advisor assignment: the Canvas `ADVISOR` column was removed from Data 360 because it disagreed with the CRM. Education Cloud advisee or success-team relationships may be the correct production model.
2. **The Canvas user ID is the shared student key** across CRM (`Contact.Student_ID__c`), Banner and Canvas.
3. **Every advisor is a member of one Calendly organization**, so a single org-owner credential can create links on any advisor's meeting type.
4. **A 30-day window of activity is enough** for advising conversations. The engagement score covers all activity.

## Known risks

| Risk | Impact | Mitigation in place / needed |
|---|---|---|
| Data 360 doesn't filter on the advising relationship | One advisor could see another's student | **In place:** `StudentAccess` check runs first in every action, and Apex tests assert each action refuses another advisor's student. **Needed:** run them in CI. |
| Wrong identity merge | One student's data shown as another's | Exact Student ID rule ranks first. **Needed:** review the fuzzy name rules and sample merges. |
| Calendly token is over-privileged and person-owned | Leak or a staff change breaks booking | **Needed:** OAuth app on a service account; rotate. |
| Unused single-use links pile up | Calendly clutter, stray bookable links | **Needed:** create the link at send time, or expire links. |
| Data graph refreshes daily | Agent can be up to a day behind | Acceptable for advising; enable incremental refresh if needed. CRM activity (tasks, notes) is read live, not from the graph. |
| Student search is a name-word heuristic | Misspellings find nothing; unusual phrasing could miss a student | Owner filter is enforced regardless. **Needed:** consider SOSL or fuzzy matching, still owner-filtered. |
| Nightly Banner → CRM load fails or lags | New students missing; advisor changes not reflected, so the wrong advisor passes the owner check | **Needed:** monitor the job, and alert on failure (see [operations](operations.md)). |
| Testing Center results count against data storage | The 5 MB dev org filled after three runs and blocked agent publishing | Delete runs after exporting them. A production org has far more storage. |

## Unknowns

- Real volume and cost. The [cost model](cost-model.md) estimates $31k a year to run for 40 advisors at list price; confirm scale, contracted rates and how Direct Access reads are billed.
- Agent behaviour beyond the four Testing Center runs (195 cases, latest 19/20 on v8). Record updates and multi-turn conversations are still untested there. See [validation](../validation/README.md).
- Slack link rendering and formatting for email drafts.

## Exit conditions for build

- [ ] Apex tests at 75% or more coverage, including the refusal paths, in CI. **Written and passing:** 21 tests, about 86% coverage; CI still to wire up
- [ ] Agent test suite (Testing Center) passes the persona matrix, adversarial rows included. Built and run four times (latest 19/20); make it a gate on every agent change
- [ ] Second advisor tested end to end with their own Agentforce license
- [x] Financial aid visibility decided: advisors see status only (FAFSA, verification, SAP). Amount fields dropped from the data graph
- [ ] Calendly moved to OAuth on a service account; personal token revoked
- [ ] Enhanced Notes enabled; notes confirmed as `ContentNote`
- [ ] Baselines captured for the three pilot measures, plus last term's persistence for the advising team in the pilot
- [ ] Calendly booking events written back to the CRM, so bookings can be measured

- [ ] Old `Academic_Advisor_Agent` flow deleted from the org

## Fallbacks

- **Federation too slow:** enable acceleration on the Snowflake streams, or copy only the objects the graph uses.
- **Identity merges unreliable:** drop the fuzzy rules and match on Student ID only.
- **Calendly unavailable:** the email still drafts and asks the student to reply (already built).
