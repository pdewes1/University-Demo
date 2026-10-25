# Focused technical validation

## The uncertainty

**When the Advisor Agent grounds on Data 360, does it only see the students that advisor is responsible for?**

FERPA requires a legitimate educational interest, which for an advisor means *their own advisees*. If access had to come from Data 360 itself, the architecture would depend on Data 360 policies that can express "students assigned to this advisor". If they can't, the check has to live somewhere else. Either answer changes where the trust boundary sits, so this is the assumption most likely to change the recommendation.

## Decision rule (set before testing)

- **Data 360 limits retrieval to the advisor's students:** rely on Data 360 policies, and agent actions can query freely.
- **Data 360 returns any student the running user can see:** enforce the advising relationship in every agent action *before* any Data 360, LLM or external call, and treat Data 360 as an unfiltered store behind that gate.

## Method

1. Two advisors, A and B, each own their students in the CRM (Contact owner = assigned advisor).
2. As Advisor A, call every agent action directly (REST Invocable Actions API) for:
   - one of A's students (should work);
   - one of B's students (should be refused);
   - a non-student record Id (should be refused).
3. As a control, have Advisor A query Data 360 directly for B's student, bypassing the actions.
4. Check that refusals happen *before* side effects: no Calendly link, no LLM call, no record written.

Raw outputs: [`results/2026-10-25-action-guardrails.json`](results/2026-10-25-action-guardrails.json)

## Results

| Action | A's student | B's student | Notes |
|---|---|---|---|
| Get Student 360 Data | ✅ summary returned | ✅ refused | A non-Contact Id was also refused |
| Update Student Record | ✅ allowed fields only | ✅ refused | `OwnerId` and `Student_ID__c` rejected even on A's own student |
| Draft Student Outreach Email | ✅ draft with booking link | ✅ refused | Refused before the Calendly and LLM calls |
| Create Calendly Booking Link | ✅ link created | ✅ refused | Refused before the Calendly callout |
| Create Student Task | ✅ task created | ✅ refused | |
| Log Student Note | ✅ note logged | ✅ refused | |
| **Control:** direct Data 360 query | | ⚠️ **returned B's student** | Data 360 doesn't filter on the advising relationship |

**12 of 12 action cases behaved as expected. The control showed the uncertainty was real.**

## Conclusion

Data 360 does not know who a student's advisor is. A user who can query the unified profile can read any student's profile. The architecture therefore puts the trust boundary in the action layer:

- Every action goes through `StudentAccess.ownedStudent()`, a `WITH USER_MODE` Contact query plus an owner check, before it touches Data 360, Calendly or the LLM.
- The refusal message is the same whether the student doesn't exist or belongs to someone else, so it doesn't reveal which students exist.
- The agent's instructions repeat the rule, but **the Apex check is the control**. The instructions are only a second layer.

This is the fallback branch of the original plan ("move sensitive objects behind a live, permission-checked action"), and it is what's built.

## Other findings along the way

- **The Trust Layer masks student names.** The masking turned "Hi Priya" into "Hi Cooper". The fix: names never go into the prompt. The model writes `{FIRST_NAME}` and `{ADVISOR_NAME}`, and Apex fills them in afterwards.
- **Agentforce redacts untrusted links.** Calendly links showed as `[URL_Redacted]` until `https://calendly.com` was added to Trusted URLs.
- **Engagement data is a 30-day window.** Data 360 requires recency limits on Engagement-category objects in a data graph, and the maximum is 30 days or 10 records. The agent sees recent activity, not the whole term.
- **The data graph is a copy.** The streams are zero copy, but the graph materialises its data daily.
- **The original agent had a key mismatch.** The existing Academic Advisor Agent's flow filters `UnifiedIndividual.Student_ID__c` with a Contact record Id, so it can never match. The new agent resolves through `Contact.Student_ID__c`.

## Not yet tested

- **Agent-level prompts, including adversarial ones** (`persona-question-matrix.csv`, rows marked "not yet run"). The checks above test the actions; the planner's behaviour still needs a run in the Agentforce Testing Center.
- **A second advisor through the agent UI.** The demo org has one Agentforce (Default) license, so Advisor B can't open the agent.
- **Financial aid detail (A10).** The 360 summary currently includes offered, accepted and unmet-need amounts. That fits "advisor may see aid status", but it is wider than "indicator only". The Registrar and Compliance need to decide before build. The email action already keeps aid amounts out of anything sent to the student.
