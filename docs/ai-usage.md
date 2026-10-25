# How AI was used

I built this with an AI assistant (Claude) working against the org through the Salesforce APIs: Tooling, Connect, Data 360 and NextGen Authoring. It also drafted the Apex, the agent script and these docs. This page records what it produced, what I kept or changed, and how the output was checked.

## What it produced

- Nine Apex classes: the agent actions, the Calendly client and the shared access check.
- The Agent Script for `Academic_Advisor_Student_Success`, through four published versions.
- The `Student_360_Graph` data graph definition, plus the Calendly credential and permission set setup.
- The validation runs in `validation/` and this documentation.

## Where the first approach was wrong, and what replaced it

| First attempt | What happened | What replaced it |
|---|---|---|
| Draft the email with a Prompt Builder template | The API forced Jinja format, and record inputs came through empty | Apex calls the Models API directly with a prompt it builds |
| Put the student's name in the prompt | The Trust Layer masked it inconsistently ("Hi Cooper") | Name placeholders, filled in by Apex after the model responds |
| Create the data graph fully through the API | Engagement DMOs needed recency criteria in an undocumented format; full validation then failed on every recency field | Saved as a draft through the API and finished in the Data 360 UI (30 days, the UI maximum) |
| Reuse the existing advisor agent's lookup flow | It filtered `UnifiedIndividual.Student_ID__c` with a Contact Id, which never matches | New action resolves through `Contact.Student_ID__c` |
| Trust the existing Discussion Entries relationship | It pointed at the wrong key, so no posts joined | Relationship rebuilt on `user_id` |
| Send Calendly auth with the named credential's standard header fields | The API rejected those field names | Custom `Authorization` header using a credential merge field |
| Assume Calendly links would render | Agentforce showed `[URL_Redacted]` | Calendly added to Trusted URLs |
| Use the agent's current record Id everywhere | It would treat an Account or Case Id as a student | Instructions branch on `currentObjectApiName == "Contact"` |

## How the output was checked

- **Run, not read.** Every action was called through the REST API against real records, including refusal cases. See `validation/`.
- **The live version is the reference.** The repo's Apex, agent script and Data 360 definitions were pulled from or compared with what is deployed.
- **Compile before publishing.** Every agent version was compiled through the authoring API (no errors; one known warning about an optional input) before it was published and activated.
- **Negative control.** The direct Data 360 query showed why the action-layer check is needed.

## What still needs a human decision

- Whether advisors should see financial aid **amounts** or only status (see `validation/README.md`).
- Whether Contact owner is the right model for "assigned advisor", versus Education Cloud's advisee or success-team relationships.
- Production authentication for Calendly (an OAuth service account instead of a personal token).
