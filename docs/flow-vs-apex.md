# Flow or Apex: the hybrid agent

There are two builds of the Advisor Agent in the org, both active:

| Agent | Built with |
|---|---|
| `Academic_Advisor_Student_Success` (v8) | All actions in Apex |
| `Academic_Advisor_Hybrid` | Flow where it's the simpler tool, Apex where it isn't |

They have the same instructions, topics and action names, so the same Testing Center suites run against both, and the two can be compared directly.

## The rule used

**Flow** for record work an admin could read and change: create a record, update a few fields, branch on a value.

**Apex** for the guardrail, and for work Flow handles badly: parsing nested JSON, HTTP callouts with custom headers, calls to the model, text processing, and binary note content.

## Which action uses what

| Action | Hybrid agent | Why |
|---|---|---|
| Check student access | **Apex** (`CheckStudentAccessAction`), called as the first step of every flow | The guardrail stays in one tested place: a `USER_MODE` query plus an owner match. A flow can't skip it without visibly removing the first element |
| Create Student Task | **Flow** (`Advisor_Create_Student_Task`) | One record create with defaults (due in 3 days, Normal priority). Exactly what Flow is for |
| Update Student Record | **Flow** (`Advisor_Update_Student_Record`) | A get, an assignment and an update. The flow's inputs *are* the allow-list: stage, level, email, phone, mobile phone. Blank inputs keep the current value |
| Find Students | Apex | Pulls a Student ID, email or record Id out of free text, drops filler words, and falls back to word pairs. That's string processing |
| Get Student 360 Data | Apex | Walks nested Data 360 graph JSON, calculates attendance rates and recency windows, and applies the aid allow-list |
| Draft Outreach Email | Apex | Calls the Models API, then fills in the name and booking link after the model responds, so the model never sees either |
| Create Calendly Booking Link | Apex | HTTP callout through a Named Credential with a custom `Authorization` header, URL-encoded prefill, and per-status error messages |
| Log Student Note | Apex | Enhanced Notes store HTML as binary `Content`. Flow can't set binary content, and the note has to be escaped and linked to the student |

## What changed in moving to Flow

- **Update is narrower.** The Apex version takes a JSON map and checks it against 14 allowed fields. The flow takes five named inputs. That's simpler and safer, but title, description and mailing address can no longer be changed through the agent. The agent says so if asked.
- **No JSON from the model.** The model fills five named inputs instead of writing a JSON object, so there's no parsing step to fail.
- **Errors come from the fault path.** A save error (for example an invalid email) is caught by the flow's fault connector and returned as a message, the same as the Apex `catch` did.

## How the flows are tested

`AdvisorFlowTests` runs each flow through `Flow.Interview`, the same entry point the agent uses. 8 tests, all passing ([results](../validation/results/2026-10-26-flow-tests.json)):

- the access check allows only the advisor's own student, and returns nothing about another advisor's student;
- the task flow creates a task with the right owner, student, defaults and priority, refuses another advisor's student with nothing created, and asks for a subject when it's missing;
- the update flow changes only the fields given, refuses another advisor's student with the record untouched, explains when nothing was given, and reports save errors.

Flow coverage: every element of the update flow; every element of the task flow except its error branch.

## What to say to the panel

"The guardrail and the integrations are Apex, because they need to be tested and they're too complex for Flow. The record work is Flow, so Post's admins can own it. Every flow starts with the same Apex access check, so moving work into Flow doesn't move the security boundary."

## About the flow files

The flows were deployed to the org through the Tooling API from one definition in [`tools/build_flows.py`](../tools/build_flows.py), which also writes the `.flow-meta.xml` files in the repo. Those files weren't retrieved from the org, so before deploying them somewhere else, open the flows in Flow Builder or run `sf project retrieve start -m Flow:Advisor_Create_Student_Task -m Flow:Advisor_Update_Student_Record` to get Salesforce's own copy.
