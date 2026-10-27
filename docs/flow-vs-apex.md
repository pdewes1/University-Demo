# Standard, Flow or Apex: the three builds

There are three builds of the Advisor Agent in the org, all active:

| Agent | Built with |
|---|---|
| `Academic_Advisor_Student_Success` (v9) | All actions in Apex |
| `Academic_Advisor_Hybrid` (v3) | Flow for the access check and simple record work; Apex for the rest |
| `Academic_Advisor_Standard` (v1) | Standard Agentforce actions for search and updates, with Salesforce sharing doing the owner check; Flow for tasks; Apex only where no standard action exists |

They have the same instructions, topics and action names, so the same Testing Center suites run against all three, and they can be compared directly. The standard build is the one to demo to a client: it shows what comes out of the box, and the custom code that's left each has a reason. [Jump to the standard build](#the-standard-actions-build)

## The rule used

**Flow** for anything an admin should be able to read and change: the access check, creating a record, updating fields, branching on a value.

**Apex** for work Flow handles badly or can't do at all: parsing nested JSON, HTTP callouts with custom headers, calls to the model, free-text processing, and Enhanced Notes (which flows can't create).

The question for each action was: *could a Post admin read this in Flow Builder and safely change it?* If yes, Flow. If the logic would turn into a wall of formulas and loops, or the platform blocks it, Apex.

## Which action uses what

| Action | Hybrid agent | Standard agent | Why (hybrid) |
|---|---|---|---|
| Check student access | **Flow** (`Advisor_Check_Student_Access`), called as a subflow by every flow action | **Sharing.** Contact is Private, so the advisor only sees their own students | One Get Records, filtered on the student Id **and** `OwnerId = $User.Id`. Another advisor's student is never read into the flow. One shared subflow, so the rule lives in one place, like `StudentAccess` does in Apex |
| Create Student Task | **Flow** (`Advisor_Create_Student_Task`) | Flow (same) | One record create with defaults (due in 3 days, Normal priority) |
| Update Student Record | **Flow** (`Advisor_Update_Student_Record`) | **Standard** Update Record, plus a validation rule | A get, an assignment and an update. Same 14 fields as the Apex action; blank inputs keep the current value |
| Find Students | Apex | **Standard** Query Records | Pulls a Student ID, email or record Id out of free text, drops filler words, and falls back to word pairs |
| Get Student 360 Data | Apex | Apex (same) | Walks nested Data 360 graph JSON, calculates attendance rates and recency windows, and applies the aid allow-list |
| Draft Outreach Email | Apex | **Prompt Builder** template (`Email_Outreach`), after a separate booking-link step | Calls the Models API, then fills in the name and booking link after the model responds, so the model never sees either |
| Create Calendly Booking Link | Apex | Apex (same) | HTTP callout through a Named Credential with a custom `Authorization` header, URL-encoded prefill, and per-status error messages |
| Log Student Note | Apex | Apex (same) | Salesforce doesn't allow it: deploying a flow that creates an Enhanced Note fails with "You can't create ContentNote records in a flow" (tested 2026-10-26). Classic Notes would work in Flow, but they show under Notes & Attachments instead of Notes |

The Apex actions keep their own check (`StudentAccess`), so every action in all three agents checks ownership before it touches anything.

## Action by action

Each action below covers what it does, why it's built the way it is, what it would look like the other way, the trade-offs, and what would change the decision.

### Check student access: Flow

**What it does.** Confirms the student belongs to the advisor before any other step reads or writes anything. Every flow action in the hybrid agent calls it first, and stops if it says no.

**Why Flow.**

- **It's simple.** The whole check is one lookup: get the Contact where the Id matches the student *and* the owner is the running user. If a record comes back, the advisor owns the student; if not, refuse. In Flow Builder that's four elements: a check that an Id was given, the lookup, a yes/no decision, and the result.
- **It's a business rule Post will change.** "Who is this student's advisor?" is policy, not plumbing. Today it's the Contact owner. In production it may become an Education Cloud advising relationship, a success team, or a rule like "the primary advisor, or anyone covering for them this week". When that happens, the people who own advising policy should be able to see the rule and change it, and Flow lets an admin do that without a developer or a deploy.
- **Another advisor's student is never loaded.** The ownership condition is in the lookup's filter, not checked after the record comes back, so the flow never holds data it shouldn't. That holds whatever context the flow runs in.
- **One place for the rule.** It's a subflow, `Advisor_Check_Student_Access`, called by the task and update flows rather than copied into each. Change it once and every flow action follows. That's the same design as `StudentAccess` in Apex, which every Apex action calls.

**What the Apex version looks like.** `StudentAccess.ownedStudent()`: about ten lines, a `WITH USER_MODE` query, then an owner comparison. The all-Apex agent uses it, and so do the hybrid agent's Apex actions.

**Trade-offs.**

- The Apex check runs in user mode, so it also applies the advisor's sharing and field-level security. The Flow check is just as strict on *ownership*, but doesn't add field-level security. The update flow makes up for that with a fixed list of inputs: it can only ever touch its 14 fields.
- Being easy to edit means being easy to break. Someone could open the flow and delete the owner filter. That's why it's a single shared subflow with its own tests (`accessFlowAllowsOnlyOwnedStudents`, `accessFlowRefusesBlankAndMalformedIds`): a change that loosens the check fails those tests before it can be deployed.

**What would push it back to Apex.** A rule that needs both sharing and field-level security enforced, or that spans several objects with dates and roles (for example "on the student's success team, and the assignment is current").

### Create Student Task: Flow

**What it does.** Creates a follow-up task on the student, assigned to the advisor, with a subject, optional details, a due date and a priority.

**Why Flow.**

- **It's exactly what Flow is for.** One record create with three defaults: due in three days if no date is given, Normal priority unless High or Low is asked for, status Not Started. There's no logic that needs code.
- **Admins are the likely editors.** This is the action Post is most likely to want to adjust: a different default due date, a task record type for advising, a category field, or a rule that High priority also notifies the advising lead. Each of those is a small change in Flow Builder.
- **Errors still come back cleanly.** The create has a fault path that returns "Could not create the task:" plus the reason, the same as the Apex version's `catch`, so the agent can tell the advisor what went wrong.

**What the Apex version looks like.** `CreateStudentTaskAction`: about 50 lines for the same behavior: request and response classes, the access check, the defaults, the insert, the message. It works, but every tweak needs a developer.

**Trade-offs.** Hardly any. The flow is still tested in Apex (`taskFlowCreatesTaskForOwnStudentWithDefaults` and two others) because Flow has no test framework of its own that runs in CI.

**What would push it back to Apex.** Nothing likely. Even creating tasks for many students at once is fine in Flow.

### Update Student Record: Flow

**What it does.** Changes allowed fields on the student record, after the advisor confirms the change in the conversation.

**Why Flow.**

- **The logic is simple.** Get the record, set each field that was given and keep each one that wasn't, save.
- **The allow-list is visible.** Each of the 14 allowed fields is a named input, so the inputs *are* the allow-list. An admin, or an auditor, can open the flow and see exactly what the agent can change. Adding a field is one input variable, one formula and one assignment line.
- **No JSON from the model.** The Apex version asks the model to write a JSON object of field names and values, which the code then parses. That's a failure point: a stray quote or the wrong field name, and nothing updates. With the flow, the model fills in named inputs, such as `phone`, and there's nothing to parse.
- **The safety step stays.** The advisor still has to confirm before the update runs; that's set on the agent action, not in the flow.

**What the Apex version looks like.** `UpdateStudentRecordAction`: it takes a JSON map, looks up each field name, checks it against a 14-field allow-list and whether the user may edit it, converts the value to the field's type, and saves in user mode. It's flexible, but an admin can't easily see or change what it allows.

**Trade-offs.**

- **Fourteen inputs make the flow wide.** It's longer to read than the Apex version's single JSON input.
- **A blank value can't clear a field.** In the flow, blank means "keep the current value", so the agent can't remove a phone number. The Apex version can, by sending an empty value.
- **No field-level security.** The Apex version saves in user mode; the flow relies on its fixed inputs instead.
- **Picklists need care.** `Level__c` is a picklist, so its formula has to convert it to text first. Each new picklist field needs the same treatment.

**What would push it back to Apex.** Rules that depend on other values (for example "Student Level can only change while the stage is Enrolled"), a real need to clear fields, or an allow-list long enough that the flow becomes hard to read.

### Find Students: Apex

**What it does.** Finds the advisor's own students from whatever the advisor typed: "Aisha Chen U00974", "pull up priya cooper's record", "mark Priya Cooper's follow-up done", an email address or a record Id.

**Why Apex.**

- **It's text processing.** The action splits the text into words and handles each one:
  - a 15- or 18-character Id starting `003` is a record Id;
  - anything with `@` is an email;
  - `U` followed by digits is a Student ID;
  - filler words ("student", "the", "my", "named") and possessives ("Cooper's") are dropped;
  - whatever is left is treated as name words.
- **The query changes shape.** It then builds a query with as many name conditions as there are name words (up to four), always inside the owner filter. If that finds nothing, it tries adjacent pairs of words. Flow has no regular expressions and no easy way to loop over the words of a string, and a Get Records element's conditions are fixed when the flow is built. Doing this in Flow would mean many lookups and decisions guessing at the shape of the input.
- **It's where testing found problems.** Testing Center run 3 found that "name plus Student ID" found nothing; run 4 found that extra words like "mark … follow-up" broke the match. Each fix was a few lines of Apex. In Flow, each would have been a new branch.
- **It has to be deterministic.** The first version used the standard Query Records action, which lets the model write the query. Run 1 showed it returning other advisors' students, because "only my students" was just an instruction to the model. This action puts the owner filter in code, where the model can't skip it.

**What would move it to Flow.** If search only ever had to handle an exact Student ID or email, a single Get Records would do.

### Get Student 360 Data: Apex

**What it does.** Pulls everything the advisor needs about one student into a plain-language summary. From the Student 360 data graph in Data 360: attendance, submissions, course scores, LMS activity, discussion posts, financial aid status and the engagement score. Live from the CRM: the last advising contact and open or overdue follow-ups.

**Why Apex.**

- **The data is deeply nested.** The data graph comes back as one JSON document several levels deep: the unified student, then identity links to each source system, then the Canvas and Banner records under each. The action walks that tree and does the arithmetic: attendance counts and rate, average score on graded work, total minutes of page views, most recent activity dates. Flow can't parse arbitrary nested JSON, and the counting and averaging would be dozens of loops and assignments.
- **Aid filtering is a security control.** Advisors may see financial aid status, not amounts. The action keeps only an allow-list of status fields before anything reaches the agent, and a test (`financialAidIsReducedToStatusOnly`) fails if that ever changes. A control like that belongs in code with a test, not in a flow someone can edit on a busy day.
- **It combines two sources with date logic.** The CRM part looks across tasks, events and two kinds of notes for the most recent contact, then works out which follow-ups are overdue *as of today* and says so in words, "none overdue" or "1 overdue". That wording is there because Testing Center run 2 caught the agent calling a future task overdue. Getting that right is easier to test in code.

**What would move it to Flow.** Probably nothing. This is the core data shaping, and moving it would make it harder to read, not easier.

### Draft Student Outreach Email: Apex

**What it does.** Writes a supportive check-in email from the 360 summary, with a single-use link the student can use to book a meeting.

**Why Apex.**

- **The model never sees the student's name or the link.** The action builds the prompt itself and asks the model to write `{FIRST_NAME}` and `{BOOKING_LINK}` as placeholders. Only after the model responds does Apex put in the real name and the real Calendly URL. So the student's name never goes to the model, and the model can't invent or alter a link.
- **The Flow route was tried first.** Flow can call a Prompt Builder template, and that was the first approach. It was dropped because record inputs came through empty, and Trust Layer masking garbled names ("Hi Cooper" instead of "Hi Priya").
- **The prompt carries the rules.** No grades or scores, no aid details, no system names, always supportive even if the advisor asks for a harsh tone, never mention internal notes or tasks. Those are written into the prompt and tested.
- **It chains steps and handles failure.** It checks access, creates the booking link, calls the model and fills in the placeholders. If Calendly fails, the email is still drafted and asks the student to reply instead, and the agent is told why there's no link.

**What would move it to Flow.** A Prompt Builder template that reliably takes the summary as input and keeps names intact, plus a supported way to insert values after generation. The standard build now does this with a template called straight from the agent; see [The email as a prompt template](#the-email-as-a-prompt-template).

### Create Calendly Booking Link: Apex

**What it does.** Creates a single-use Calendly link for the advisor's meeting type, pre-filled with the student's name and email, so one student can book once.

**Why Apex.**

- **It's an HTTP call with custom authentication.** It goes through a Named Credential, but Calendly rejected the credential's standard header fields, so the action sends a custom `Authorization` header built from a credential merge field.
- **It shapes the request and the result.** It builds the request body, adds the student's name and email to the returned link with proper URL-encoding, and turns Calendly's error codes into messages an advisor can act on: token expired, advisor not in the Calendly organization, rate limited.
- **It can be tested without calling Calendly.** In Apex tests, Calendly is replaced by a mock (`HttpCalloutMock`), so the success and error paths are tested on every run. Flow's HTTP callout action needs an External Service registration, handles custom auth headers and per-status errors poorly, and can't be mocked as easily in tests.

**What would move it to Flow.** A Calendly OAuth connection that works with standard Named Credential authentication, and an External Service generated from Calendly's API specification.

### Log Student Note: Apex

**What it does.** Logs an advising note on the student, for example after a review or meeting.

**Why Apex.**

- **Salesforce doesn't allow it in Flow.** This was tested: deploying a flow that creates an Enhanced Note (`ContentNote`) fails with "You can't create ContentNote records in a flow." (2026-10-26).
- **The note has to be stored correctly.** Enhanced Notes store their text as HTML, so the action escapes the advisor's text, keeps line breaks as paragraphs, and links the note to the student record.

**What would move it to Flow.** Switching to classic Notes, which flows can create. They show under Notes & Attachments rather than the Notes list, so new notes would sit apart from existing ones. The agent would still find them, because the last-contact summary reads both kinds. Keeping notes in Apex was the better trade.

## The standard-actions build

`Academic_Advisor_Standard` asks a different question: *what does Salesforce already do, if the org is set up so the platform can enforce the rules?* Two org settings make that possible:

- **Contact sharing is Private.** An advisor can only see students they own. The standard Query Records and Update Record actions run as the advisor, so another advisor's student is never returned and can't be changed. No custom check is needed for those two actions.
- **A validation rule protects Student ID and owner.** The standard Update Record action can write any field the advisor can edit. `Advisors_Keep_Student_ID_and_Owner` blocks Academic Advisor users from changing `Student_ID__c` or `OwnerId`, whether they use the agent or the record page. ([metadata](../force-app/main/default/objects/Contact/Contact.object-meta.xml))

| Action | Built with | Why |
|---|---|---|
| Find Students | Standard **Query Records** | Sharing scopes the results to the advisor's students |
| Update Student Record | Standard **Update Record** (`EmployeeCopilot__UpdateRecordFields`) | Sharing, field-level security and the validation rule decide what can change. The advisor still confirms first |
| Create Student Task | Flow | There's no standard create-record action for this agent type (the agent builder rejects `createRecord` without a standard source action), so the task flow stays |
| Log Student Note | Apex | Flow can't create Enhanced Notes, and there's no standard action for it |
| Get Student 360 Data | Apex | Data 360 doesn't apply CRM sharing, so this action checks ownership first, then applies the financial aid allow-list and adds CRM activity. The standard data graph action also needs the unified Id, not the Contact Id |
| Review a student | **Prompt Builder** template `Student_Briefing` | A consistent four-part briefing with fixed thresholds. [Details](#the-student-briefing-as-a-prompt-template) |
| Draft Outreach Email | **Prompt Builder** template `Email_Outreach` | Reads the student record directly with merge fields; the booking link comes from the Calendly action first. [How it was tested](#the-email-as-a-prompt-template) |
| Create Calendly Booking Link | Apex | No standard action exists for an outside API |

**It has to be demoed as an advisor.** The platform rules only apply to users they apply to. A System Administrator has View All Data, so Query Records returns every student, and the validation rule only targets the Academic Advisor profile. That's correct platform behavior, not a bug, but it means the standard build only shows its security as an advisor user. The Apex and hybrid builds check ownership themselves, so they behave the same for any user.

**Why the first version moved away from Query Records.** Testing Center run 1 had the standard search returning other advisors' students. At the time, Contact sharing wasn't Private and the tests ran as an admin, so the model's "only my students" instruction was the only thing in the way. With sharing set to Private and an advisor user, the platform enforces it instead.

**Trade-offs.**

- **Less code to own.** Two of the seven actions are standard, the owner check for them is a setting, and the field rule is one formula an admin can read.
- **Security lives in configuration.** Loosen sharing or give advisors View All Data and the standard actions follow. In the Apex build, the check is in code and can't be switched off by a setting. Keep the sharing model and the validation rule under change control.
- **The model writes the query.** Query Records turns the advisor's words into a query, so unusual searches ("name plus Student ID", extra words) depend on the model. The Apex search handles those in code.
- **Updates accept any editable field.** There's no 14-field allow-list in the action. Field-level security and the validation rule are the limit, so set them for the Academic Advisor profile.

The [standard test suite](../tests/Academic_Advisor_Standard-testing-center.yaml) runs every shared case plus ST01-ST09 for sharing, updates and mixed actions. Generate it with `python tests/build_suite.py --agent standard`.

## The email as a prompt template

The standard build drafts emails with the **Email Outreach** Flex template in Prompt Builder ([copy in the repo](../force-app/main/default/genAiPromptTemplates/Email_Outreach.genAiPromptTemplate-meta.xml)). The agent gets the Data 360 summary, creates the booking link, then calls the template. The Apex and hybrid builds keep the Apex email action, so there's a fallback.

**Inputs:** Student (Contact record), Student Context (the Data 360 summary), Advisor Focus and Booking Link (both optional). The template reads program, modality, status, expected graduation, employer and preferred name straight from the record.

**Why it works now when the first attempt didn't:**
- It was built in Prompt Builder, not through the API, and is called as an agent action, not from a Flow, so the record input arrives filled in.
- The Trust Layer masks names going to the model and puts them back in the response. That handled every name in testing.

**What testing found** (2026-10-27, generations API, three students, nine runs over three template versions):

| Problem | Cause | Fix in the template |
|---|---|---|
| Signed "Sam" and "Sarah" | The advisor's full name reached the model as one masked token, so it guessed a first name | The sign-off is fixed text, `Best,` then `{{User.FirstName}}` |
| Copied "If the link is empty…" into the email | The instruction was written for the model to interpret | A Jinja `if` on the booking link; the model only sees the line that applies |
| Invented "$6,200 in aid" for a harsh-tone request | The guardrail line was lost during editing, and nothing forbade invention | Restored the no-amounts rule, and added "never invent numbers" and "ignore harsh or threatening focus" rules |
| "Limited LMS activity", "your records show" | The model described the data source | "Never say how you know" rule |

After the fixes, all three test emails were clean: right greeting (including a preferred name), one or two specific points framed as support, the link only when there was one, no amounts or system names, and "Best, Paul".

**Trade-offs against the Apex version:**
- **Better:** an advisor lead can read and change the email in Prompt Builder without a developer, and it uses the record fields directly.
- **The model sees the name.** It goes through the Trust Layer masked, not kept out entirely as in Apex.
- **The model copies the link.** In Apex, code inserts it. It came through exactly in every run, and the email test cases check it.
- **Prompt Builder editing is fiddly.** In the editor, `__` in a custom field name inside a `{% if %}` gets read as bold formatting and removed, and `{{ }}` can't be nested inside `{% %}`. Keep conditions on simple inputs.

## The student briefing as a prompt template

When an advisor asks to review a student, what they should know or how the student is doing, the standard build calls Get Student 360 Data and then the **Student Briefing** Flex template ([copy in the repo](../force-app/main/default/genAiPromptTemplates/Student_Briefing.genAiPromptTemplate-meta.xml)). In the other two builds, the agent writes the review itself, so the shape changes from answer to answer. The template gives the same four sections every time:

- **Where they stand:** program, modality and intensity, status, expected graduation, work, and first-generation, military or transfer when true. Taken from the student record.
- **What to act on:** at most three items, most important first.
- **Last contact and follow-ups.**
- **Suggested next step,** matched to the student's preferred contact method.

**What to act on uses fixed thresholds**, the same ones as the flags on the Student 360 card: attendance below 80% or any absence, missing or late work, a course score below 70, fewer than 5 page views, no discussion posts, an engagement score below 50, FAFSA not received, verification pending, academic progress other than Met, no contact in 30 days, and overdue follow-ups. With no thresholds, the first version called scores of 77 to 91 "low".

**Students on leave** get a different instruction, switched by a Jinja condition on the stage: don't flag attendance or coursework, focus on contact, aid status and their return.

**Inputs:** Student (Contact record) and Student Context (the Data 360 summary). Unlike the email template, this one was created through the Connect API. Its input reference names had to be `Input.Student` (with a dot) for the record input to resolve; `Input:Student` failed with "Invalid input value: null".

**Testing** (2026-10-27, three students, four template versions): Priya (several flags), Aisha (on leave) and Jess (mostly on track, with a preferred name). The final version kept the format, flagged only real issues, left out false flags, used the on-leave mode for Aisha, and suggested a text for Priya and an email for the others, matching their contact preferences.

**Data mismatch to know about.** The Data 360 summary's profile line comes from the Canvas sample data, which has its own majors and enrollment status. The seeded CRM profile doesn't always match it: Jess is a Psychology senior, full-time, in Canvas, but AS Early Childhood Education, part-time, on her record. The briefing is told to use the student record for program and enrollment. In production both would come from Banner and agree.

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

## In short

"Anything an admin should own is Flow, including the access check. It's one shared subflow that filters on the record owner, so another advisor's student is never even read. The integrations stay in Apex because they need callouts, JSON parsing and the model. Both sides check ownership before they touch anything, and both are tested."

## About the flow files

The flows were deployed to the org through the Tooling API from one definition in [`tools/build_flows.py`](../tools/build_flows.py), which also writes the `.flow-meta.xml` files in the repo. New versions are created with the `Name-2` convention, because an active flow version can't be overwritten. The repo files weren't retrieved from the org, so before deploying them somewhere else, open the flows in Flow Builder or run `sf project retrieve start -m Flow:Advisor_Check_Student_Access -m Flow:Advisor_Create_Student_Task -m Flow:Advisor_Update_Student_Record` to get Salesforce's own copy.
