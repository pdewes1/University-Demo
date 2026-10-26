# Flow or Apex: the hybrid agent

There are two builds of the Advisor Agent in the org, both active:

| Agent | Built with |
|---|---|
| `Academic_Advisor_Student_Success` (v8) | All actions in Apex |
| `Academic_Advisor_Hybrid` (v2) | Flow for the access check and simple record work; Apex for the rest |

They have the same instructions, topics and action names, so the same Testing Center suites run against both, and the two can be compared directly.

## The rule used

**Flow** for anything an admin should be able to read and change: the access check, creating a record, updating fields, branching on a value.

**Apex** for work Flow handles badly or can't do at all: parsing nested JSON, HTTP callouts with custom headers, calls to the model, free-text processing, and Enhanced Notes (which flows can't create).

The question for each action was: *could a Post admin read this in Flow Builder and safely change it?* If yes, Flow. If the logic would turn into a wall of formulas and loops, or the platform blocks it, Apex.

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

## Action by action

### Check student access: Flow

**What it does.** Confirms the student belongs to the advisor before any other step reads or writes anything.

**Why Flow.** It's a single lookup: get the Contact where the Id matches *and* the owner is the running user. If nothing comes back, refuse. That fits in four elements an admin can read at a glance. The ownership condition is in the lookup's filter, so another advisor's student is never even loaded into the flow.

**Why a subflow.** Every flow action calls the same `Advisor_Check_Student_Access`, so the rule exists in one place. If Post later decides "assigned advisor" means an Education Cloud advising relationship, not Contact owner, an admin changes one flow and every action follows.

**What would push it back to Apex.** If the rule needed record-level sharing *and* field-level security enforced (Apex's `WITH USER_MODE`), or became a multi-object check such as success teams with date ranges.

### Create Student Task: Flow

**What it does.** Creates a follow-up task on the student, assigned to the advisor.

**Why Flow.** It's one record create with three defaults: due in three days, Normal priority, Not Started. This is exactly the work Flow was built for, and it's the action admins are most likely to want to adjust, for example a different default due date or a task record type.

**What would push it back to Apex.** Nothing likely. Bulk task creation across many students would still be fine in Flow.

### Update Student Record: Flow

**What it does.** Changes allowed fields on the student, after the advisor confirms in the conversation.

**Why Flow.** It's get the record, set the fields that were given, save. Each of the 14 allowed fields is a named input, so the input list *is* the allow-list. An admin can see exactly what the agent can change, and adding or removing a field is one input and one assignment. It also means the model fills in named fields instead of writing a JSON object, which removes a parsing step that can fail.

**The trade-off.** Fourteen inputs make the flow wider than the Apex version, which takes one JSON map. The Apex version also enforces field-level security through `USER_MODE`; the flow relies on its fixed input list instead.

**What would push it back to Apex.** Dynamic rules, such as "this field is editable only when the stage is X", or an allow-list long enough that Flow Builder becomes hard to read.

### Find Students: Apex

**What it does.** Searches the advisor's own students from whatever the advisor typed: "Aisha Chen U00974", "pull up priya cooper's record", an email or a record Id.

**Why Apex.** It's text processing. The action splits the text into words, recognizes Student IDs, emails and record Ids anywhere in it, drops filler words and possessives, builds a query with a variable number of name conditions, and falls back to word pairs if the full match finds nothing. Flow has no loop-over-words or regular expressions, and can't build a query with a varying number of conditions. Each fix from Testing Center runs 3 and 4 was a few lines of Apex; in Flow, each would have been a new branch.

**What would move it to Flow.** If search were only ever an exact Student ID or email, a single Get Records would do.

### Get Student 360 Data: Apex

**What it does.** Reads the Student 360 data graph from Data 360 and the CRM's advising activity, and turns them into a plain-language summary.

**Why Apex.** The data graph comes back as nested JSON, several levels deep: the unified student, then identity links, then Canvas and Banner records under each. The action walks that tree, counts attendance and works out the rate, averages graded work, totals page-view minutes, applies the financial aid allow-list so amounts never reach the agent, and adds the last advising contact and overdue follow-ups. Flow can't parse arbitrary nested JSON, and the arithmetic over nested collections would be dozens of loops and assignments.

**What would move it to Flow.** Probably nothing: this is the core data shaping.

### Draft Student Outreach Email: Apex

**What it does.** Writes a supportive check-in email from the 360 summary, with a single-use booking link.

**Why Apex.** Two reasons:

- **The model never sees the student's name or the link.** The action builds the prompt itself, calls the Models API, and only after the response fills in `{FIRST_NAME}` and the real booking URL. Flow could call a Prompt Builder template, but the template approach was tried first and dropped: record inputs came through empty, and Trust Layer masking garbled names ("Hi Cooper").
- **It chains steps with error handling.** It checks access, creates the Calendly link, calls the model and replaces placeholders, and gives a clear message if any step fails.

**What would move it to Flow.** A Prompt Builder template that reliably takes the summary as input, plus a way to fill in the name and link after generation.

### Create Calendly Booking Link: Apex

**What it does.** Creates a single-use Calendly link for that student, pre-filled with their name and email.

**Why Apex.** It's an HTTP callout. It goes through a Named Credential, but Calendly rejected the credential's standard header fields, so the action sends a custom `Authorization` header. It also builds the request body, URL-encodes the name and email onto the link, and turns Calendly's error codes into advisor-friendly messages (expired token, advisor not in the organization, rate limited). Flow's HTTP callout action needs an External Service registration and handles custom auth headers and per-status errors poorly.

**What would move it to Flow.** A Calendly OAuth connection that works with standard Named Credential auth, and an External Service built from Calendly's API spec.

### Log Student Note: Apex

**What it does.** Logs an advising note on the student.

**Why Apex.** Salesforce won't allow it in Flow. Deploying a flow that creates an Enhanced Note (`ContentNote`) fails with "You can't create ContentNote records in a flow." (tested on 2026-10-26). The Apex action also escapes the text as HTML and keeps line breaks as paragraphs.

**What would move it to Flow.** Switching to classic Notes, which flows can create. They show under Notes & Attachments rather than the Notes list, so it was kept in Apex.

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
