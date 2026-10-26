# Panel prep: if a constraint changes

Short answers for "what if we changed X?" Each says what changes, what doesn't, and how long it would take. The design point behind all of them: the systems of record stay where they are, and the access check lives in Apex actions, so most changes touch one layer only.

## Snowflake is replaced by Databricks (or BigQuery, Redshift)

- **Changes:** the Data 360 data streams. Data 360 has zero-copy connectors for Databricks, BigQuery and Redshift as well as Snowflake, so the streams are recreated against the new source and remapped to the same DMOs.
- **Doesn't change:** the DMOs, identity resolution, the engagement score, the data graph, every Apex action and the agent. They all read Data 360 objects, not Snowflake.
- **Effort:** days, mostly connector setup, auth and remapping. Check that the new connector supports Direct Access for these tables; if not, ingest only the graph's objects.

## Slack is replaced by Microsoft Teams

- **Changes:** the channel. Agentforce can be deployed to Teams; the Slack user mapping becomes a Teams-to-Salesforce user mapping.
- **Doesn't change:** the agent, its actions and the access check. They run as the mapped Salesforce user either way, so an advisor still only sees their own students.
- **Check:** how Teams renders the email draft and the Calendly link (the same open question as Slack today).

## Students need to talk to an agent directly

- **Answer:** a separate service agent, not this one. This agent is an employee agent that reads across an advisor's caseload, and it drafts but never sends. A student-facing agent would run as the student, see only that student's own record, and need its own guardrails: no aid details, escalation to a person, crisis language routed to support.
- **Reusable:** the Calendly link action, and the Data 360 graph read with a self-only access check in place of `StudentAccess`.
- **Effort:** a new agent and a new access model. Treat it as phase 3, after the advisor pilot shows what students respond to.

## Ten times the students, or every advisor at once

- **Access and correctness:** no change. The owner filter and per-student check don't depend on volume.
- **Search:** capped at 25 results per search; fine for caseloads of a few hundred.
- **Cost:** agent actions scale with use, not with students. See the [cost model](cost-model.md) sensitivity table: twice the usage takes year 1 from $55k to $75k.
- **Data 360:** more rows per refresh. Consider incremental graph refresh, and accelerating the busiest Snowflake streams.

## Assigned advisor comes from Education Cloud, not Contact owner

- **Changes:** one method, `StudentAccess.ownedStudent()`, and the owner clause in `FindStudentsAction`. Both would check the advisee or success-team relationship instead of `OwnerId`.
- **Doesn't change:** anything else; every action already goes through those two places. The Apex tests' refusal cases would be updated to create the relationship records.

## Financial aid wants to share amounts with advisors

- **Changes:** add the fields back to the data graph and to the allow-list in `Student360DataAction`. Both were removed on purpose, so it's a deliberate two-step change, and the test `financialAidIsReducedToStatusOnly` must be updated with it.
- **Ask first:** whether FERPA and the aid office's policy allow advisors to see amounts. The current answer is status only.

## Calendly is replaced by Microsoft Bookings or Salesforce Scheduler

- **Changes:** `CalendlyService` and the booking-link action. The agent action keeps the same name and inputs, so the agent script doesn't change.
- **Salesforce Scheduler** would also give booking write-back for free, which closes the "can't measure bookings" gap.

## The model provider changes, or the university wants its own LLM

- **Changes:** the model name in `DraftStudentEmailAction` (one constant), or a BYO model registered in Einstein Studio.
- **Doesn't change:** the Trust Layer still sits in front of it, and names and links are still filled in by Apex after the model responds.

## Banner moves to a different SIS (Workday Student, Colleague)

- **Changes:** the Banner source table, the stream, and the Banner DMO mapping. The nightly automation that loads students into the CRM moves to the new SIS.
- **Doesn't change:** the graph shape, as long as the new SIS provides a Student ID that matches `Contact.Student_ID__c`.
