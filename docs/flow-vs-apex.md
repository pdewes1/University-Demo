# Flow or Apex: the hybrid agent

There are two builds of the Advisor Agent in the org, both active:

| Agent | Built with |
|---|---|
| `Academic_Advisor_Student_Success` (v8) | All actions in Apex |
| `Academic_Advisor_Hybrid` (v2) | Flow for the access check and simple record work; Apex for the rest |

They have the same instructions, topics and action names, so the same Testing Center suites run against both, and the two can be compared directly.

## The rule used

**Flow** for anything an admin should be able to read and change: the access check, creating a record, updating fields, branching on a value.

**Apex** for work Flow handles badly: parsing nested JSON, HTTP callouts with custom headers, calls to the model, free-text processing, and binary note content.

## Which action uses what

| Action | Hybrid agent | Why |
|---|---|---|
| Check student access | **Flow** (`Advisor_Check_Student_Access`), called as a subflow by every flow action | One Get Records, filtered on the student Id **and** `OwnerId = $User.Id`. Another advisor's student is never read into the flow. One shared subflow, so the rule lives in one place, like `StudentAccess` does in Apex |
| Create Student Task | **Flow** (`Advisor_Create_Student_Task`) | One record create with defaults (due in 3 days, Normal priority) |
| Update Student Record | **Flow** (`Advisor_Update_Student_Record`) | A get, an assignment and an update. Same 14 fields as the Apex action; blank inputs keep the current value |
| Find Students | Apex | Pulls a Student ID, email or record Id out of free text, drops filler words, and falls back to word pairs |
| Get Student 360 Data | Apex | Walks nested Data 360 graph JSON, calculates attendance rates and recency windows, and applies the aid allow-list |
| Draft Outreach Email | Apex | Calls the Models API, then fills in the name and booking link after the model responds, so the model never sees either |
| Create Calendly Booking Link | Apex | HTTP callout through a Named Credential with a custom `Authorization` header, URL-encoded prefill, and per-status error messages |
| Log Student Note | Apex | Salesforce doesn't allow it: deploying a flow that creates an Enhanced Note fails with "You can't create ContentNote records in a flow" (tested 2026-10-26). Classic Notes would work in Flow, but they show under Notes & Attachments instead of Notes |

The Apex actions keep their own check (`StudentAccess`), so every action in both agents checks ownership before it touches anything.

## Flow check versus Apex check

| | Apex (`StudentAccess`) | Flow (`Advisor_Check_Student_Access`) |
|---|---|---|
| Ownership | `OwnerId` compared after a query | `OwnerId = $User.Id` in the query filter |
| Another advisor's student | Never returned | Never read into the flow |
| Record visibility and field security | `WITH USER_MODE` | The ownership filter holds whatever context the flow runs in, but the flow doesn't add field-level security. The update flow's fixed inputs stand in for it: nothing outside the 14 fields can change |
| Who can change it | A developer, with a deploy | An admin, in Flow Builder |
| Tests | `AdvisorAgentTests` | `AdvisorFlowTests` |

The trade-off to say out loud: the Flow check is easier for admins to own, and just as strict on ownership. The cost is that it's also easier to edit. That's why it's one shared subflow with its own tests, not a check copied into each flow.

## Editable fields

Both builds allow the same 14 fields: Student Stage, Student Level, Level, Languages, Email, Phone, Mobile Phone, Title, Description and the five mailing-address parts. The first hybrid version allowed only five, because each field is a separate flow input and I kept the list short. That was a shortcut, not a Flow limit, and it's fixed. Owner and Student ID can't change in either build.

The Apex version takes a JSON map and checks it against an allow-list. The flow takes 14 named inputs, so the inputs are the allow-list, and the model never has to write JSON.

## How the flows are tested

`AdvisorFlowTests` runs each flow through `Flow.Interview`, the same entry point the agent uses. 9 tests, all passing ([results](../validation/results/2026-10-26-flow-tests.json)):

- the check flow allows only the advisor's own student, returns nothing about another advisor's student, and refuses blank, malformed and non-student Ids;
- the task flow creates a task with the right owner, student, defaults and priority, refuses another advisor's student with nothing created, and asks for a subject when it's missing;
- the update flow changes only the fields given (including title, description and mailing city), refuses another advisor's student with the record untouched, explains when nothing was given, and reports save errors.

Flow coverage: every element of the check and update flows; every element of the task flow except its error branch. The run reports no Apex coverage, which confirms the flows don't call Apex.

## What to say to the panel

"Anything an admin should own is Flow, including the access check. It's one shared subflow that filters on the record owner, so another advisor's student is never even read. The integrations stay in Apex because they need callouts, JSON parsing and the model. Both sides check ownership before they touch anything, and both are tested."

## About the flow files

The flows were deployed to the org through the Tooling API from one definition in [`tools/build_flows.py`](../tools/build_flows.py), which also writes the `.flow-meta.xml` files in the repo. New versions are created with the `Name-2` convention, because an active flow version can't be overwritten. The repo files weren't retrieved from the org, so before deploying them somewhere else, open the flows in Flow Builder or run `sf project retrieve start -m Flow:Advisor_Check_Student_Access -m Flow:Advisor_Create_Student_Task -m Flow:Advisor_Update_Student_Record` to get Salesforce's own copy.
