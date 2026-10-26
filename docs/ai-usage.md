# How AI was used

I built this with an AI assistant (Claude) working against the org through the Salesforce APIs: Tooling, Connect, Data 360 and NextGen Authoring. It also drafted the Apex, the agent script and these docs. This page records what it produced, what I kept or changed, and how the output was checked.

## What it produced

- Eleven Apex classes: the agent actions, the owner-filtered student search, the CRM advising-activity reader, the Calendly client and the shared access check.
- The Agent Script for `Academic_Advisor_Student_Success`, through eight published versions.
- The `Student_360_Graph` data graph definition, plus the Calendly credential and permission set setup.
- The validation runs in `validation/`, the Testing Center suites in `tests/`, and this documentation.

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
| Use the standard Query Records action, told to filter by owner | **Testing Center run 1 showed other advisors' students reached the agent.** The filter was an instruction to an LLM-built query, not enforced | `FindStudentsAction`: the owner filter is in the SOQL |
| Write test expectations with the agent's short action names | 61 of 75 action checks failed on naming alone | Expectations use the names Testing Center reports |
| Run Testing Center headlessly through the Grid API | Every run sent a placeholder instead of the utterance | Generated CSV and YAML suites; runs done in the Testing Center UI |
| Match a Student ID only when it was the whole search | "Aisha Chen U00974" found nothing (run 3) | Student ID, email or record Id is picked out anywhere in the text |
| Require every search word to match | "Mark Priya Cooper's follow-up" found nothing (run 4) | Falls back to adjacent word pairs, still inside the owner filter |
| Remove a field by editing the data graph | Data 360 graphs can only add fields | Graph deleted and recreated without the Canvas advisor field |

## How the output was checked

- **Run, not read.** Every action was called through the REST API against real records, including refusal cases. See `validation/`.
- **The live version is the reference.** The repo's Apex, agent script and Data 360 definitions were pulled from or compared with what is deployed.
- **Compile before publishing.** Every agent version was compiled through the authoring API before it was published and activated. The current warning is that the agent doesn't read the search's match count, which is intended.
- **Test the agent, not just the actions.** Four Testing Center runs (195 cases). Every failure was read, not just counted: some were real agent issues, some were wrong expectations in my own suite, and in a few cases the LLM judge passed a wrong answer (a future follow-up called "overdue") or failed a right one (the advisor's own Carters). Those misreads are why each run's replies were checked by hand.
- **Negative control.** The direct Data 360 query showed why the action-layer check is needed.

## What still needs a human decision

- Whether Contact owner is the right model for "assigned advisor", versus Education Cloud's advisee or success-team relationships.
- Production authentication for Calendly (an OAuth service account instead of a personal token).
