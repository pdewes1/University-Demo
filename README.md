# Post University Student Success Agents

Post University wants its advisors to walk into every student conversation already knowing what's going on. Today an advisor opens the CRM for the relationship, Banner for holds, grades and aid, and Canvas for course activity, then pieces it together by hand. That usually happens after a student has already started to slip.

This project designs and validates an **Advisor Agent** in Agentforce. It pulls one trusted view of a student from Data 360 (built from Banner, Canvas and the CRM), tells the advisor what needs attention, and turns that into action: an outreach email with a booking link, a follow-up task and a note. It only ever works on the advisor's own students.

> **Demo scenario.** This is a design and validation exercise. It is not affiliated with or endorsed by the university, and all student data is synthetic. No real student data is used.

![Overview](docs/images/architecture-overview.png)

## The decision

| | |
|---|---|
| **Problem** | Advisors spot disengaged students late, because the signals sit in three systems. |
| **Owner** | Provost's office (advising). The VP of Enrollment owns the phase 2 Admissions Agent. |
| **Recommendation** | Ground an employee agent in a Data 360 data graph over zero-copy Banner and Canvas data. Keep the systems of record where they are, and enforce the advising relationship in the agent's actions. |
| **Measures** (baselines before build) | Advisor prep time per student · days from an engagement drop to outreach · share of flagged students who book a meeting |
| **Path to value** | Pilot with one advising team → add the agent test suite and move Calendly to OAuth → roll out to all advisors → phase 2 Admissions Agent |

## Advisor Agent

`Academic_Advisor_Student_Success` is an Agentforce **employee agent**, live in the Agentforce panel on student records and Home, and in Slack. It never talks to students, and nothing it writes is sent without the advisor.

| Action | What it does | Implementation |
|---|---|---|
| Find Students | Searches the advisor's own students | Standard `queryRecords`, filtered to the running user |
| Get Student 360 Data | Attendance, submissions, enrollments and scores, LMS activity, discussion posts, financial aid status, engagement score | [`Student360DataAction`](force-app/main/default/classes/Student360DataAction.cls) → data graph |
| Draft Student Outreach Email | A warm, specific check-in email based on the 360 summary, with a single-use Calendly link | [`DraftStudentEmailAction`](force-app/main/default/classes/DraftStudentEmailAction.cls) → Models API + Calendly |
| Create Calendly Booking Link | Just the link, pre-filled with the student's name and email | [`CreateCalendlyBookingLinkAction`](force-app/main/default/classes/CreateCalendlyBookingLinkAction.cls) |
| Create Student Task | Follow-up task for the advisor, linked to the student | [`CreateStudentTaskAction`](force-app/main/default/classes/CreateStudentTaskAction.cls) |
| Log Student Note | Advising note on the student record | [`LogStudentNoteAction`](force-app/main/default/classes/LogStudentNoteAction.cls) |
| Update Student Record | Allow-listed fields only, after the advisor confirms | [`UpdateStudentRecordAction`](force-app/main/default/classes/UpdateStudentRecordAction.cls) |

The agent is written in Agent Script: [`agent/Academic_Advisor_Student_Success.agent`](agent/Academic_Advisor_Student_Success.agent).

- **On a student record**, it uses that student without asking.
- **Anywhere else** (Home, another object, Slack), it asks which student you mean or searches for them. It never treats a non-student record Id as a student.

### A typical conversation

Illustrative, based on a real 360 summary for a synthetic student:

> **Advisor (on Priya's record):** What should I know about this student?
>
> **Agent:** She's doing strong work when she submits (94% on graded work), but she missed a recent HIST 210 class, hasn't posted in discussions, and her LMS activity has dropped since mid-September. Her engagement score is 71.6. Financial aid is complete and SAP is met.
>
> **Advisor:** Draft her a check-in email.
>
> **Agent:** *(draft with a single-use booking link)* Want me to log a note and set a follow-up task?

## Architecture

![Architecture](docs/images/architecture-detailed.png)

### What stays where

| System | Owns | How Salesforce uses it |
|---|---|---|
| **Banner SIS** | Student profile, holds, financial aid | Read through Snowflake, zero copy |
| **Canvas LMS** | Enrollments, submissions, attendance, page views, discussions | Read through Snowflake, zero copy |
| **Snowflake** | The university's existing landing zone for Banner and Canvas | Direct Access data streams into Data 360 |
| **Data 360** | Identity resolution, the unified student, the engagement score, the Student 360 data graph | Grounding for the agent |
| **Education Cloud (CRM)** | Students (Contacts), advisor assignment, tasks, notes | System of record for advising work |
| **Agentforce** | Reasoning, action selection, advisor conversation | Employee agent in Lightning and Slack |
| **Calendly** | Advisor calendars, availability, bookings | Single-use links through a Named Credential |
| **Slack** | Where advisors already work | Agentforce in Slack, with users mapped to Salesforce users |

Nothing is written back to Banner, Canvas or Snowflake.

### Trust boundaries

1. **Advising relationship.** Every action calls [`StudentAccess.ownedStudent()`](force-app/main/default/classes/StudentAccess.cls) first: a `WITH USER_MODE` query plus a check that the advisor owns the Contact. This runs **before** any Data 360, LLM or Calendly call. It's needed because Data 360 doesn't know who a student's advisor is (see [validation](validation/README.md)).
2. **Einstein Trust Layer.** All model calls go through it. Student names are kept out of the prompt entirely; the model writes `{FIRST_NAME}` and Apex fills it in, because masking was mangling names.
3. **No unreviewed outreach.** Emails are drafts only. Record updates need the advisor's confirmation and only touch allow-listed fields (owner and student ID can never change).
4. **No invented links.** The Calendly link is created first and inserted by Apex, so the model never writes a URL. `calendly.com` is the only added Trusted URL.
5. **Least data in outreach.** The email prompt bars grades, scores, aid amounts and system names, so the student sees patterns, not numbers.

## Data 360

- **Data streams:** Banner and Canvas tables are **Direct Access** (federated from Snowflake). CRM Contacts are ingested. [Details](data360/data-streams.md)
- **Identity resolution:** an exact match on Party Identification (`Student ID`, `Person Identifier`) ranks first, with fuzzy name plus email or phone as fallbacks. The last run unified **2,777 source profiles into 1,000 students**. [Ruleset](data360/identity-resolution/Student_Default.json)
- **Student Engagement Score:** a calculated insight, 0 to 100. It weights on-time submissions 35%, attendance 30%, LMS page views 20% (capped at 20) and discussion posts 15% (capped at 5). Grades are deliberately excluded: engagement is behaviour, not performance. [SQL](data360/calculated-insights/Student_Engagement_Score.sql)
- **Student 360 data graph:** rooted on the unified individual. It reaches the Canvas and Banner rows through the identity links, and adds the engagement score. Engagement objects are limited to the last 30 days (10 records), and the graph refreshes daily. [Definition](data360/data-graphs/Student_360_Graph.md)

**Identity keys:** `Contact.Student_ID__c` = `UnifiedIndividual.Student_ID__c` = Canvas `user_id` (e.g. `U00002`). Banner joins on `banner_id` (the S-number) through its own Individual.

## Focused technical validation

**The uncertainty:** when the agent grounds on Data 360, does it see only that advisor's students, or every student the running user can see?

**What was found:** Data 360 returns any student to a direct query, so the advising relationship has to be enforced in the actions. All 12 action-level cases behaved as expected:

- own student: allowed;
- another advisor's student: refused before any side effect;
- protected fields: rejected.

A control query showed Data 360 alone would have exposed the other advisor's student.

→ [Method, results and raw outputs](validation/README.md)

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
2. Create the streams listed in [data-streams.md](data360/data-streams.md): Direct Access for Snowflake, ingest for the CRM.
3. Map Individual, Party Identification and Contact Points, then create the [identity ruleset](data360/identity-resolution/Student_Default.json).
4. Create the [engagement score](data360/calculated-insights/Student_Engagement_Score.sql) insight.
5. Build `Student_360_Graph` [as documented](data360/data-graphs/Student_360_Graph.md). Set recency on Submissions, Page Views and Discussion Entries in the UI.

### 3. Salesforce metadata

```sh
sf project deploy start --source-dir force-app --target-org <alias>
```

This deploys:

- the Apex actions;
- the `User.Calendly_Event_Type_URI__c` field;
- the Calendly Trusted URL;
- the two permission sets.

### 4. Calendly

Create the external credential and named credential, then set each advisor's event type URI. Follow [integrations/calendly.md](integrations/calendly.md). Paste the token in Setup, not in code.

### 5. Agent

1. Create a new employee agent in Agentforce Builder and replace its script with [`agent/Academic_Advisor_Student_Success.agent`](agent/Academic_Advisor_Student_Success.agent).
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
│   └── Academic_Advisor_Student_Success.agent   Agent Script (live version 4)
├── force-app/main/default/
│   ├── classes/                                 Apex actions, Calendly client, access check
│   ├── objects/User/fields/                     Calendly_Event_Type_URI__c
│   ├── cspTrustedSites/                         Calendly trusted URL
│   └── permissionsets/                          Agent access, Calendly access
├── data360/
│   ├── data-streams.md
│   ├── identity-resolution/Student_Default.json
│   ├── calculated-insights/Student_Engagement_Score.sql
│   └── data-graphs/Student_360_Graph.md
├── integrations/
│   └── calendly.md
├── validation/
│   ├── README.md                                Uncertainty, method, results
│   ├── persona-question-matrix.csv
│   └── results/2026-10-25-action-guardrails.json
└── docs/
    ├── execution-handoff.md                     One-pager for the build team
    ├── ai-usage.md                              What AI produced and how it was checked
    └── images/
```

## Execution handoff

The build team's one-pager is [docs/execution-handoff.md](docs/execution-handoff.md). It covers scope, interfaces, assumptions, risks, unknowns, owners and exit conditions. The short version:

- **Ready:** the Advisor Agent end to end, the Data 360 model, the Calendly link flow, and action-level access control.
- **Before build:**
  - Apex tests in CI;
  - an agent test suite with adversarial prompts;
  - a second advisor tested with their own license;
  - the Registrar's call on financial aid amounts;
  - Calendly moved to OAuth.
- **Phase 2:** Admissions Agent, Calendly booking write-back, and the student-facing channel (if ever).

## Limitations

- The data is synthetic, so the engagement score makes no predictive claims. The caps (20 views, 5 posts) are tuned to the sample and need rescaling for a real term.
- No Apex test classes yet, so the code can't deploy to production as-is.
- Agent-level prompts have only been spot-checked by hand. The structured results so far are for the actions.
- Contact owner stands in for "assigned advisor".
- AI was used throughout. See [docs/ai-usage.md](docs/ai-usage.md) for what it got wrong and how each piece was verified.
