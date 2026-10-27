# Technical details

The deeper material behind the [README](../README.md): the decision in full, the code behind each action, what stays where and the trust boundaries, Data 360, validation, setup, repository layout, the execution handoff and limitations.

- [Decision summary](#decision-summary)
- [Actions and implementation](#actions-and-implementation)
- [Student record page](#student-record-page)
- [Advisor home page](#advisor-home-page)
- [Architecture details](#architecture-details)
- [Data 360](#data-360)
- [Focused technical validation](#focused-technical-validation)
- [Setup](#setup)
- [Repository structure](#repository-structure)
- [Execution handoff](#execution-handoff)
- [Limitations](#limitations)

## Decision summary

| | |
|---|---|
| **Problem** | Advisors spot disengaged students late, because the signals sit in three systems. That costs prep time, delays outreach, and loses students who could have been kept. |
| **Owner** | Provost's office (advising). The VP of Enrollment owns the phase 2 Admissions Agent. |
| **Recommendation** | Build an Agentforce agent for advisors, grounded in a Data 360 data graph over Banner and Canvas. The Banner and Canvas streams stay in Snowflake (zero copy); the graph keeps a daily copy of only the fields the agent needs. Keep each system of record where it is. Check in the agent's actions that the student belongs to the advisor. |
| **Success for the pilot** | Compared with baselines taken before launch: lower prep time per student, fewer days from an engagement drop to outreach, and a higher share of flagged students booking a meeting, with no guardrail breaches. |
| **Investment** | Running cost grows with how much advisors use the agent, not with the number of students. Keeping a small number of extra students enrolled covers the first year, before counting advisor time saved. [Costs and savings](cost-model.md) |
| **Path to value** | Take baselines → pilot with one advising team → run the agent test suite and move Calendly to OAuth → roll out to all advisors and track persistence → phase 2 Admissions Agent |

### Assumptions that would change this

- **Outreach timing matters for retention.** If faster outreach doesn't raise bookings, the agent saves advisors time but doesn't move persistence. The pilot tests this directly.
- **The engagement score flags the right students.** Before rollout, compare who it flags with who actually withdrew last term.
- **Bookings can be measured.** The demo creates booking links but doesn't record whether a meeting was booked. The pilot needs Calendly's booking events written back to the CRM, which is planned for phase 2.

## Actions and implementation

The [README](../README.md#advisor-agent) describes what the agent does. This is the code behind each action in the all-Apex build, `Academic_Advisor_Student_Success`.

| Action | What it does | Implementation |
|---|---|---|
| Find Students | Searches the advisor's own students by name, Student ID, email or record Id | [`FindStudentsAction`](../force-app/main/default/classes/FindStudentsAction.cls): owner filter in the SOQL, so other advisors' students never reach the agent |
| Get Student 360 Data | Last advising contact and overdue follow-ups (live from the CRM), plus attendance, submissions, enrollments and scores, LMS activity, discussion posts, financial aid status (no amounts) and engagement score | [`Student360DataAction`](../force-app/main/default/classes/Student360DataAction.cls) → data graph, with [`StudentAdvisingActivity`](../force-app/main/default/classes/StudentAdvisingActivity.cls) for CRM activity |
| Draft Student Outreach Email | A warm, specific check-in email based on the 360 summary, with a single-use Calendly link | [`DraftStudentEmailAction`](../force-app/main/default/classes/DraftStudentEmailAction.cls) → Models API + Calendly |
| Create Calendly Booking Link | Just the link, pre-filled with the student's name and email | [`CreateCalendlyBookingLinkAction`](../force-app/main/default/classes/CreateCalendlyBookingLinkAction.cls) |
| Create Student Task | Follow-up task for the advisor, linked to the student | [`CreateStudentTaskAction`](../force-app/main/default/classes/CreateStudentTaskAction.cls) |
| Log Student Note | Advising note on the student record | [`LogStudentNoteAction`](../force-app/main/default/classes/LogStudentNoteAction.cls) |
| Update Student Record | Allow-listed fields only, after the advisor confirms | [`UpdateStudentRecordAction`](../force-app/main/default/classes/UpdateStudentRecordAction.cls) |

The agent is written in Agent Script: [`agent/Academic_Advisor_Student_Success.agent`](../agent/Academic_Advisor_Student_Success.agent).

**A second build, Flow plus Apex.** `Academic_Advisor_Hybrid` is the same agent with the access check and simple record work moved into Flow: [Create Student Task](../force-app/main/default/flows/Advisor_Create_Student_Task.flow-meta.xml) and [Update Student Record](../force-app/main/default/flows/Advisor_Update_Student_Record.flow-meta.xml) (same 14 fields). Both call one shared check flow first, [Check Student Access](../force-app/main/default/flows/Advisor_Check_Student_Access.flow-meta.xml), which only reads the student if the running advisor owns them. The search, Data 360, Calendly, email and notes stay in Apex. Both agents are active. [Why each action is where it is](flow-vs-apex.md) · [How to test it against the original](../validation/README.md#running-the-hybrid-suite-and-comparing-it-with-the-original-agent)

**A third build, standard actions first.** `Academic_Advisor_Standard` uses the standard **Query Records** action to find students and the standard **Update Record** action to change them. Contact sharing is Private, so both only reach the advisor's own students, and the [`Advisors_Keep_Student_ID_and_Owner`](../force-app/main/default/objects/Contact/Contact.object-meta.xml) validation rule stops advisors from changing the Student ID or owner. Tasks stay in Flow, because there's no standard create-record action for this agent type. Reviews use the **Student Briefing** Prompt Builder template and the email uses **Email Outreach**. Data 360, Calendly and notes stay in Apex, because there's no standard action that does what they do. Demo it as an advisor user: an admin's View All Data bypasses sharing. [Agent Script](../agent/Academic_Advisor_Standard.agent) · [Why](flow-vs-apex.md#the-standard-actions-build)

- **On a student record**, it uses that student without asking.
- **Anywhere else** (Home, another object, Slack), it asks which student you mean or searches for them. It never treats a non-student record Id as a student.

## Student record page

**What's in the org:**

| Piece | What it is |
|---|---|
| [`Student_Record_Page`](../force-app/main/default/flexipages/Student_Record_Page.flexipage-meta.xml) | Lightning record page for Contact: highlights, the Student 360 card, then tabs for *Data 360* (all six Data 360 lists together), *Related* and *Details* (the default tab). Activity and Notes & Attachments are on the right. |
| [`student360Card`](../force-app/main/default/lwc/student360Card) | Lightning web component: engagement gauge, what-to-watch flags, courses, six metric tiles, financial aid status. |
| [`Student360CardController`](../force-app/main/default/classes/Student360CardController.cls) | Apex controller. Reads the `Student_360_Graph` data graph by the student's unified profile, the same way the agent's Get Student 360 Data action does, and reads advising contact and overdue follow-ups live from the CRM. |
| [`Contact Layout`](../force-app/main/default/layouts/Contact-Contact%20Layout.layout-meta.xml) | Feeds the *Related* tab. The Data 360 lists and Notes & Attachments were moved off it to the page, so nothing shows twice. |
| [`Contact.object-meta.xml`](../force-app/main/default/objects/Contact/Contact.object-meta.xml) | Makes the page the org-default desktop View page for Contact when deployed with `sf project deploy`, and assigns the `Student_Compact` compact layout to the highlights panel. |
| [Student profile fields](../force-app/main/default/objects/Contact/fields) | Program, modality, enrollment intensity, start and expected graduation terms, preferred name and contact method, first-generation, military-affiliated and transfer flags, employer. |

**Student profile fields.** The Details tab is grouped the way an advisor reads a student: *Student Information*, *Program and Enrollment*, *Contact Information*, *Work*, then the description. The highlights panel shows Student ID, program, stage, modality, expected graduation, preferred contact method and mobile number.

| Field | Source in production | Advisors can edit |
|---|---|---|
| Program, Modality, Enrollment Intensity, Start Term, Expected Graduation, Transfer Student | Banner | No (read-only) |
| First Generation, Military Affiliated | Admissions, self-reported | No (read-only) |
| Preferred Name, Preferred Contact Method, Employer | The student, through their advisor | Yes |

Field access is set on the System Administrator and Academic Advisor profiles in the demo org. The Academic Advisor profile also needs Apex class access to `Student360CardController` (the Student 360 card) and the agent's action classes (`Student360DataAction`, `CreateCalendlyBookingLinkAction`, `DraftStudentEmailAction`, `FindStudentsAction`, `LogStudentNoteAction`, `UpdateStudentRecordAction`), and `AdvisorCaseloadController` for the [home page](#advisor-home-page). Without it, advisors get "You do not have access to the Apex class" on the student page. Profiles aren't in this repo, so set the same field-level security and class access after deploying elsewhere. GPA and credits earned are deliberately not on the record: the agent is tested to say those aren't available rather than guess.

**Demo data.** [`StudentProfileSeeder`](../force-app/main/default/classes/StudentProfileSeeder.cls) fills those fields for every student, plus a mobile number, job title, languages and a one-line description. Program, modality, enrollment intensity and terms follow each student's Canvas profile in Data 360 (major, campus, enrollment status and class year, read with `ConnectApi.CdpQuery`), so the record and the Student 360 data the agent reads agree. A student's Canvas major maps to the BS/BA program, or to the master's program for graduate students. Everything else comes from the Student ID, so a rerun gives the same result, and it includes working adults and first-generation, military-affiliated and transfer students, to match the [assumptions](../README.md#assumptions) about Post's students. Priya Cooper and Aisha Allen get fixed profiles that fit the demo script and still match Canvas. Level and stage come from Banner and aren't changed, so a few students can still differ from Canvas there (for example, on leave in the CRM but full-time in Canvas). It only fills blank fields unless told to overwrite, and it never changes Student ID, owner, stage or level that are already set. Run it as an invocable action:

```sh
POST /services/data/v67.0/actions/custom/apex/StudentProfileSeeder   {"inputs":[{"overwrite":false}]}
```

Tests: [`StudentProfileSeederTests`](../force-app/main/default/classes/StudentProfileSeederTests.cls), 3 tests, all passing, 96% coverage.

**The Data 360 tab.** The six lists are Dynamic Related List – Single components, newest first unless noted. Submissions, page views and discussion posts are **engagement** data. A Data 360 related list on engagement data shows only the last 7 days unless it has a filter, so each of those three has a "date is not blank" filter (`submitted_at__c|NOT_EQUAL|` and so on) to show the full history. Attendance, enrollment and aid aren't engagement data and need no filter.

**Columns:**

| Data 360 object | Columns |
|---|---|
| Canvas Enrollment | Course, term, state, current score, final grade (by course) |
| Canvas Attendance | Class date, course, section, status |
| Canvas Submissions | Submitted at, course, assignment, state, score, points possible |
| Canvas Page Views | Time, course, event type, duration, device |
| Canvas Discussion Entries | Posted at, course, topic, entry type, word count |
| Banner Financial Aid Summary | Aid year, FAFSA status, FAFSA received date, verification status, academic progress. Status fields only, no amounts |

Banner stores the aid year as a code, the two-digit start and end years, so `2627` is the 2026–27 aid year. The card shows it as *2026–27*. The related list shows the raw code.

**The engagement score.** A calculated insight is keyed on the unified individual, not the Contact, so it can't be a related list. The card reads it from the data graph instead and shows it as the gauge.

**Flag rules:**
- **Low engagement score:** engagement band below 50.
- **Attendance:** flagged below 80%, otherwise any absence is flagged.
- **Assignments:** any missing assignment is flagged, otherwise any late one.
- **No discussion posts.**
- **Little LMS activity:** fewer than 5 page views.
- **FAFSA not received.**
- **Aid verification pending.**
- **Academic progress:** anything other than *Met*.
- **No advising contact:** none recorded, or none in more than 30 days.
- **Overdue follow-ups.**

The engagement bands are *On track* (75 and up), *Watch* (50 to 74) and *At risk* (below 50). These follow the signals the agent is told to call out. Tune the thresholds once real terms of data exist.

**Access.** The card shows data only if the running user can see the Contact (`WITH USER_MODE`), the same rule as the Data 360 related lists on the page. Contact sharing is **Private**, so an advisor sees only the students they own, and only those students' Data 360 data. Checked with `UserRecordAccess` in the demo org: Advisor Jacqueline has no access to Priya Cooper and full access to her own two students. There are no sharing rules or manual shares on Contact. System administrators (View All Data) still see every student. That's by design, so demo the privacy as an advisor user, not as the admin.

**Tests.** [`Student360CardControllerTests`](../force-app/main/default/classes/Student360CardControllerTests.cls): 7 tests, all passing, 85% coverage. They cover graph parsing, the flags and bands, aid-year formatting, CRM activity, and the no-profile and no-access paths. [Results](../validation/results/2026-10-26-student360card-tests.json)

**Activating the page.** The page is deployed but has to be activated. Either deploy `Contact.object-meta.xml`, or open *Student Record Page* in Lightning App Builder, click **Activation**, and choose **Assign as Org Default** (desktop).

## Advisor home page

[`Advisor_Home`](../force-app/main/default/flexipages/Advisor_Home.flexipage-meta.xml) replaces the standard home page for the Academic Advisor profile in the Sales app (the override is in [`standard__LightningSales.app-meta.xml`](../force-app/main/default/applications/standard__LightningSales.app-meta.xml)). It answers the question the agent can't: *which of my students should I worry about this week?*

- **My Caseload** ([`advisorCaseload`](../force-app/main/default/lwc/advisorCaseload) and [`AdvisorCaseloadController`](../force-app/main/default/classes/AdvisorCaseloadController.cls)). It shows five tiles: students, how many need attention, overdue follow-ups, no contact in 30 days, and aid to follow up. Below them are filters (Needs attention, Watch, All, On leave) and the students ranked by priority. Each row has the engagement score, attendance, last Canvas login, last contact, follow-ups, aid status and flags. Names open the Student record.
- **Open Tasks** list view, **Recent Records**, **Assistant**, and a short note pointing advisors to the Advisor Agent.

**How it reads the data.** The agent and the record card read one student at a time from the data graph. The caseload instead runs two Data 360 SQL queries (`ConnectApi.CdpQuery.queryAnsiSqlV2`) for the whole caseload, in chunks of 500 Student IDs:
1. One row per student: Canvas user (last login), Banner aid status, and the engagement calculated insight joined through `UnifiedIndividual__dlm`.
2. Attendance and missing-submission counts, combined with `UNION ALL`.

Follow-ups and last contact come from the CRM (tasks, events, Enhanced Notes), aggregated per student. For Advisor Paul's 8 students that's 4 queries. The admin's 836 students load in about 6 seconds with 240 ms of Apex CPU.

**Priority.** The rule is a simple weighting, so an advisor can see why a student is near the top:

| Signal | Points |
|---|---|
| Engagement below 50 | 3 |
| Two or more absences (attendance below 80%) | 2 |
| Any missing assignment | 2 |
| Academic progress not *Met* | 2 |
| Overdue follow-up | 2 |
| One absence (attendance below 80%) | 1 |
| No Canvas login in 21+ days | 1 |
| FAFSA not received | 1 |
| Aid verification pending | 1 |

Three or more points means **Needs attention**, one or two means **Watch**, and none means **On track**. Students on leave aren't flagged for engagement, attendance or Canvas activity, but aid and academic progress still count. "No contact in 30 days" is a tile, not a flag, so it doesn't push every new student up the list. For Advisor Paul the ranking puts three students at the top:
- **Omar Martin:** engagement 0.
- **Sofia Anderson:** two absences, no FAFSA, no Canvas login since September.
- **Brian Campbell:** a missing assignment and aid verification pending.

**Access.** Students are read `WITH USER_MODE` and filtered to `OwnerId` = the running user. Data 360 is queried only for those Student IDs, so another advisor's students never appear, not even for an admin with View All Data. Aid is status only. The Academic Advisor profile needs Apex class access to `AdvisorCaseloadController`. If Data 360 can't be reached, the list still loads with CRM activity and says so.

**Tests.** [`AdvisorCaseloadControllerTests`](../force-app/main/default/classes/AdvisorCaseloadControllerTests.cls): 4 tests, all passing, 82% coverage. They cover ranking, flags and status, preferred names, the on-leave rules, KPI counts, other advisors' students staying out, an empty caseload and the Data 360 fallback. The Data 360 SQL can't run in tests, so it's checked against the org instead.

**Deploying the component through the Tooling API.** Include the `js-meta.xml` as a `LightningComponentResource`. Without it, the bundle's targets aren't registered and the page save fails with "doesn't implement any of the region's allowed interfaces."

## Architecture details

The diagram is in the [README](../README.md#architecture).

### What stays where

| System | Owns | How Salesforce uses it |
|---|---|---|
| **Banner SIS** | Student profile, holds, financial aid | Read through Snowflake, zero copy. A nightly automation also loads students into the CRM (below) |
| **Canvas LMS** | Enrollments, submissions, attendance, page views, discussions | Read through Snowflake, zero copy |
| **Snowflake** | The university's existing landing zone for Banner and Canvas | Direct Access data streams into Data 360 |
| **Data 360** | Identity resolution, the unified student, the engagement score, the Student 360 data graph | Grounding for the agent |
| **Education Cloud (CRM)** | Students (Contacts), advisor assignment, tasks, notes | System of record for advising work |
| **Agentforce** | Reasoning, action selection, advisor conversation | Employee agent in Lightning and Slack |
| **Calendly** | Advisor calendars, availability, bookings | Single-use links through a Named Credential |
| **Slack** | Where advisors already work | Agentforce in Slack, with users mapped to Salesforce users |

Nothing is written back to Banner, Canvas or Snowflake.

**Nightly automation (Banner → CRM).** The diagram's arrow from Banner to the CRM is the student load: each night, new and changed students are upserted into Education Cloud as Contacts, keyed on Student ID, with name, email, stage and level, and the assigned advisor as the Contact owner. It's what makes the CRM search and the owner check work, so it's a production dependency owned by University IT. In the demo org the Contacts were loaded once from the synthetic data instead.

**Einstein Trust Layer.** It isn't drawn on the diagrams, but it sits between the agent and the model on every call: the agent's own reasoning and the email draft. See trust boundary 2.

### Trust boundaries

1. **Advising relationship.** Every action that takes a student calls [`StudentAccess.ownedStudent()`](../force-app/main/default/classes/StudentAccess.cls) first: a `WITH USER_MODE` query plus a check that the advisor owns the Contact. This runs **before** any Data 360, LLM or Calendly call. The search ([`FindStudentsAction`](../force-app/main/default/classes/FindStudentsAction.cls)) has the owner filter in its SOQL, so other advisors' students never reach the agent at all. Both are needed because Data 360 doesn't know who a student's advisor is (see [validation](../validation/README.md)).
2. **Einstein Trust Layer.** All model calls go through it. Student names are kept out of the prompt entirely; the model writes `{FIRST_NAME}` and Apex fills it in, because masking was mangling names.
3. **No unreviewed outreach.** Emails are drafts only. Record updates need the advisor's confirmation and only touch allow-listed fields (owner and student ID can never change).
4. **No invented links.** The Calendly link is created first and inserted by Apex, so the model never writes a URL. `calendly.com` is the only added Trusted URL.
5. **Financial aid is status only.** Advisors see FAFSA, verification and satisfactory-academic-progress status. Award amounts, need, cost of attendance, Pell and the aid index aren't in the data graph at all, and an Apex allow-list strips anything else before the agent sees the data. If asked, the agent refers the student to the financial aid office.
6. **Least data in outreach.** The email prompt bars grades, scores, aid details and system names, so the student sees patterns, not numbers.

## Data 360

- **Data streams:** Banner and Canvas tables are **Direct Access** (federated from Snowflake). CRM Contacts are ingested. [Details](../data360/data-streams.md)
- **Identity resolution:** an exact match on Party Identification (`Student ID`, `Person Identifier`) ranks first, with fuzzy name plus email or phone as fallbacks. The last run unified **2,777 source profiles into 1,000 students**. [Ruleset](../data360/identity-resolution/Student_Default.json)
- **Student Engagement Score:** a calculated insight, 0 to 100. It weights on-time submissions 35%, attendance 30%, LMS page views 20% (capped at 20) and discussion posts 15% (capped at 5). Grades are deliberately excluded: engagement is behaviour, not performance. [SQL](../data360/calculated-insights/Student_Engagement_Score.sql)
- **Student 360 data graph:** rooted on the unified individual. It reaches the Canvas and Banner rows through the identity links, and adds the engagement score. Engagement objects are limited to the last 30 days (10 records), and the graph refreshes daily. [Definition](../data360/data-graphs/Student_360_Graph.md)

**Identity keys:** `Contact.Student_ID__c` = `UnifiedIndividual.Student_ID__c` = Canvas `user_id` (e.g. `U00002`). Banner joins on `banner_id` (the S-number) through its own Individual.

## Focused technical validation

**The uncertainty:** when the agent grounds on Data 360, does it see only that advisor's students, or every student the running user can see?

**What was found:** Data 360 returns any student to a direct query, so the advising relationship has to be enforced in the actions. All 13 action-level cases behaved as expected:

- own student: allowed;
- another advisor's student: refused before any side effect;
- protected fields: rejected;
- financial aid amounts: never reach the agent (now also dropped from the graph).

A control query showed Data 360 alone would have exposed the other advisor's student.

**Then the agent itself was tested** in Testing Center, four runs on four agent versions:

| Run | Agent | Cases | Responses passed | What it changed |
|---|---|---|---|---|
| 1 | v5 | 75 | 63 | Found that the standard Query Records search returned other advisors' students to the agent. Replaced with an owner-filtered Apex search |
| 2 | v7 | 80 | 75 | Every other-advisor case passed. Found a GPA estimate and an ignored harsh-email request |
| 3 | v8 | 20 | 19 | Retests passed. Found the name-plus-Student-ID search bug |
| 4 | v8 | 20 | 19 | Retests passed. Found extra words breaking the search |

Each fix is in the [validation write-up](../validation/README.md), along with the raw exports.

**And the code has tests.** [`AdvisorAgentTests`](../force-app/main/default/classes/AdvisorAgentTests.cls): 21 Apex tests, all passing, about 86% coverage (494 of 572 lines). They cover the refusal path of every action, the owner-filtered search, the aid allow-list, the advising-activity summary and the Calendly calls (mocked). The Models API call and the live Data 360 read can't run inside Apex tests. [Results](../validation/results/2026-10-26-apex-tests.json)

The hybrid agent's flows have their own tests: [`AdvisorFlowTests`](../force-app/main/default/classes/AdvisorFlowTests.cls) runs each flow through `Flow.Interview`. 9 tests, all passing, including the check flow on its own; another advisor's student is refused with nothing written. [Results](../validation/results/2026-10-26-flow-tests.json)

→ [Method, results and raw outputs](../validation/README.md)

## Setup

### Prerequisites

- A Salesforce org with Education Cloud, Data 360 and Agentforce (one Agentforce license per advisor)
- A Snowflake account, with a role that can create a database, schema and integration user
- A Calendly Teams or Enterprise organization that all advisors belong to
- Salesforce CLI (`sf`), plus Data Loader for CRM data
- Optional: a Slack workspace where you are an admin

### 1. Data

1. Load the Banner and Canvas tables into Snowflake (Snowsight → **Add Data**).
2. Create an integration user and role with read access, using key-pair authentication:
   ```sh
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
   ```
   ```sql
   ALTER USER DATA360_USER SET RSA_PUBLIC_KEY='<public key without header and footer>';
   ```
3. Load CRM Contacts with `Student_ID__c` set to the Canvas `user_id`.

### 2. Data 360

1. Create the Snowflake connection (Data Cloud Setup → External Integrations → Snowflake).
2. Create the streams listed in [data-streams.md](../data360/data-streams.md): Direct Access for Snowflake, ingest for the CRM.
3. Map Individual, Party Identification and Contact Points, then create the [identity ruleset](../data360/identity-resolution/Student_Default.json).
4. Create the [engagement score](../data360/calculated-insights/Student_Engagement_Score.sql) insight.
5. Build `Student_360_Graph` from [its definition](../data360/data-graphs/Student_360_Graph.json) with the Data 360 `d360_data_graph_create` tool, or in the UI [as documented](../data360/data-graphs/Student_360_Graph.md).

### 3. Salesforce metadata

```sh
sf project deploy start --source-dir force-app --target-org <alias>
```

This deploys:

- the Apex actions;
- the `User.Calendly_Event_Type_URI__c` field;
- the Calendly Trusted URL;
- the two permission sets;
- the Student Record Page, the `student360Card` component and its controller, the Contact layout with Data 360 related-list columns, and the Contact page override that makes the page the default;
- the student profile fields on Contact and the `Student_Compact` compact layout.

Then set field-level security for the profile fields (see [Student record page](#student-record-page)) and, for demo data, run `StudentProfileSeeder`.

### 4. Calendly

Create the external credential and named credential, then set each advisor's event type URI. Follow [integrations/calendly.md](../integrations/calendly.md). Paste the token in Setup, not in code.

### 5. Agent

1. Create a new employee agent in Agentforce Builder and replace its script with [`agent/Academic_Advisor_Student_Success.agent`](../agent/Academic_Advisor_Student_Success.agent).
   For the Flow + Apex build, deploy the three flows in `force-app/main/default/flows/` first, check flow first (they ship as Active), then use [`agent/Academic_Advisor_Hybrid.agent`](../agent/Academic_Advisor_Hybrid.agent).
   For the standard-actions build, deploy the task flow and the Contact object (Private sharing and the validation rule), then use [`agent/Academic_Advisor_Standard.agent`](../agent/Academic_Advisor_Standard.agent).
2. Publish and activate it.
3. Grant it in **Academic Advisor Agent Access**, then assign each advisor:
   - Academic Advisor Agent Access;
   - Calendly Access;
   - Access Agentforce Default Agent.
4. Optional: add the Slack connection in Agentforce Studio, map users in Slack (Admin → Salesforce → Users), and install the agent (Admin → Manage Agentforce).
5. Optional: turn on Enhanced Notes (Setup → Notes Settings). The note action switches to it automatically.

## Repository structure

```
.
├── README.md
├── sfdx-project.json
├── agent/
│   ├── Academic_Advisor_Student_Success.agent   Agent Script, all-Apex build (live version 9)
│   ├── Academic_Advisor_Hybrid.agent            Agent Script, Flow + Apex build (live version 3)
│   └── Academic_Advisor_Standard.agent          Agent Script, standard-actions build (live version 1)
├── force-app/main/default/
│   ├── genAiPromptTemplates/                    Student Briefing and Email Outreach prompt templates (standard build)
│   ├── classes/                                 Apex actions, owner-filtered search, Calendly client, access check, demo-data seeder, tests
│   ├── flows/                                   Access-check, task and record-update flows for the hybrid agent
│   ├── lwc/student360Card/                      Student 360 card for the student record page
│   ├── flexipages/                              Student Record Page
│   ├── layouts/                                 Contact layout with Data 360 related-list columns
│   ├── objects/                                 Calendly_Event_Type_URI__c on User; Contact profile fields, compact layout, page override, Private sharing, validation rule
│   ├── cspTrustedSites/                         Calendly trusted URL
│   └── permissionsets/                          Agent access, Calendly access
├── data360/
│   ├── data-streams.md
│   ├── identity-resolution/Student_Default.json
│   ├── calculated-insights/Student_Engagement_Score.sql
│   └── data-graphs/Student_360_Graph.json, .md  Graph definition and notes
├── integrations/
│   └── calendly.md
├── tools/build_flows.py                         Generates the hybrid agent's flows
├── tests/                                       Testing Center suites for all three agents, their generator, and a run comparison script
├── validation/
│   ├── README.md                                Uncertainty, method, results for actions and four agent runs
│   ├── persona-question-matrix.csv
│   └── results/                                 Action guardrail outputs, Testing Center exports (runs 1-4), Apex test results
└── docs/
    ├── execution-handoff.md                     One-pager for the build team
    ├── ai-usage.md                              What AI produced and how it was checked
    ├── cost-model.md                            What drives cost, where the savings come from
    ├── operations.md                            Observability, release gates, runbook
    ├── demo-script.md                           Exact demo prompts and backup recording
    ├── changed-constraints.md                   What changes if a system or requirement changes
    ├── flow-vs-apex.md                          Which actions are Flow, which are Apex, and why
    ├── technical-details.md                     Everything technical moved out of the README
    └── images/
```

## Execution handoff

The build team's one-pager is [docs/execution-handoff.md](execution-handoff.md). It covers scope, interfaces, assumptions, risks, unknowns, owners and exit conditions. The short version:

- **Ready:** the Advisor Agent end to end, the Data 360 model, the Calendly link flow, and action-level access control.
- **Before build:**
  - the Apex tests (written, 21 passing) wired into CI;
  - the Testing Center suite re-run on every agent change;
  - a second advisor tested with their own license;
  - Calendly moved to OAuth.
- **Phase 2:** Admissions Agent, Calendly booking write-back, and the student-facing channel (if ever).

## Limitations

- The data is synthetic, so the engagement score makes no predictive claims. The caps (20 views, 5 posts) are tuned to the sample and need rescaling for a real term.
- Apex coverage is about 86%, above the 75% deploy minimum, but the Models API call and the live Data 360 read are only tested end to end, not in Apex. The original agent's flow (`Academic_Advisor_Agent`) is still in the demo org and has no tests; delete it before deploying.
- Record updates and multi-turn conversations aren't covered by the Testing Center runs (the update's confirmation step doesn't run there, and the CSV upload is single-turn). Check them in the agent panel.
- The student search matches name words, not fuzzy spellings, so a misspelled name finds nothing.
- Contact owner stands in for "assigned advisor".
- Cost and savings are described qualitatively until the pilot measures real usage. See [costs and savings](cost-model.md).
- AI was used throughout. See [docs/ai-usage.md](ai-usage.md) for what it got wrong and how each piece was verified.
