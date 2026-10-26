# Operations and observability

How to tell, in production, that the Advisor Agent is working, safe and worth its cost. Each signal says where it comes from, what to watch for, and who acts.

## Where to look

| Signal | Source | Watch for | Owner |
|---|---|---|---|
| Conversations and the actions each one ran | Agentforce session tracing (Agent Builder's conversation preview, and session trace data in Data 360 when Agentforce analytics is enabled) | Topic misroutes, actions that should have run but didn't, repeated retries | Salesforce team |
| Agent quality over time | Testing Center suite in `tests/`, rerun on every agent change | Any drop in pass rate, especially the other-advisor and injection rows | Salesforce team |
| Apex action failures | Debug logs for the agent user; Apex exception emails; `Response.message` values returned to the agent | "Could not read Data 360", "Calendly returned", "Could not create" | Salesforce team |
| Access refusals | The refusal message returned by `StudentAccess` (counted from session traces) | A sudden rise: an advisor's caseload changed, or someone is probing | Advising lead |
| Data graph freshness | Data 360 › Data Graphs: status and last refresh time for `Student_360_Graph` | Status not "Ready", or last refresh more than 26 hours ago | Data engineering |
| Data streams | Data 360 › Data Streams: Snowflake stream status and last run | Failed or paused streams; Snowflake key-pair auth expiry | Data engineering |
| Identity resolution | Data 360 › Identity Resolutions: last run and consolidation rate (today 2,777 → 1,000) | Rate moving sharply between runs, which means merges changed | Data engineering |
| Engagement score | The calculated insight's last run | Not run since the last stream refresh | Data engineering |
| Calendly | Error text from `CalendlyService` (HTTP status and message) | 401 (token expired or revoked), 403 (advisor not in the organization), 429 (rate limit) | Calendly admin |
| Trust Layer | Einstein audit and feedback data in Data 360 | Toxicity flags on drafts; masked values appearing in output | Salesforce team |
| Consumption | Setup › Digital Wallet: Flex Credits and Data 360 credits per week | Usage rising faster than expected (see [costs and savings](cost-model.md)) | Salesforce team, finance |
| Pilot measures | Prep time study; Task, Note and booking-link dates against the engagement-drop date | No movement after four weeks | Advising lead |

## Release gates

Before any change to the agent, an action or the graph goes live:

1. **Apex tests pass.** `AdvisorAgentTests`: 21 tests, about 86% coverage today ([results](../validation/results/2026-10-26-apex-tests.json)). The refusal tests must not be weakened.
2. **Testing Center suite passes** at or above the last run's rate. Export the results, then delete the run (results count against data storage).
3. **Agent compiles** with no new errors before publishing.
4. **One manual multi-turn check** in the agent panel: a record update with its confirmation step, which Testing Center can't run.

## When something breaks

| Symptom | Likely cause | First step |
|---|---|---|
| Agent says it couldn't read Data 360 | Graph rebuilding, or a stream failed | Check the graph status; the agent still returns CRM activity in the meantime |
| Summaries look a day old | Daily graph refresh hasn't run | Check the last refresh; enable incremental refresh if a day is too stale |
| Booking link fails for one advisor | Their user has no `Calendly_Event_Type_URI__c`, or they left the Calendly organization | Set the field; check their Calendly membership |
| Booking links fail for everyone | Token expired or revoked | Calendly admin rotates the credential in Setup (never in chat or the repo) |
| Agent can't find a student the advisor owns | Misspelled name, or the Contact owner isn't the advisor | Search by Student ID; check the Contact owner |
| Agent shows another advisor's student | Should be impossible: the owner filter is in the SOQL | Treat as a security incident: deactivate the agent, then check sharing and the action code |
