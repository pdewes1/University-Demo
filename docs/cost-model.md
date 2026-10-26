# Cost and investment model

What the Advisor Agent costs to run, what it costs to build, and how many students it has to keep enrolled to pay for itself. The numbers come from [`tools/cost_model.py`](../tools/cost_model.py). Change the inputs there and rerun it (`python3 tools/cost_model.py`); every input is listed below.

**Treat these as planning numbers, not a quote.** List prices are from public sources as of October 2026. Post's contracted rates, its existing Salesforce and Data 360 entitlements, and real usage will move them. The scale inputs are placeholders until Post confirms them.

## Inputs

| Input | Value | Basis |
|---|---|---|
| Advisors in rollout | 40 | Placeholder; confirm with the Provost's office |
| Students in scope | 8,000 | Placeholder |
| Teaching weeks per year | 40 | Placeholder |
| Full student preps per advisor per week | 12 | Find, 360 summary, draft email, booking link, task, note (6 actions + 1 prompt) |
| Quick lookups per advisor per week | 25 | Find + 360 summary (2 actions) |
| Flex Credit price | $0.005 | $500 per 100,000 credits ([eesel, July 2026](https://www.eesel.ai/blog/agentforce-pricing)) |
| Credits per agent action | 20 | Salesforce Flex Credits rate card, 21 Apr 2026 (production) |
| Credits per standard prompt | 4 | Same rate card (the email draft) |
| Agentforce user license | $5 per user per month | eesel, July 2026; needed with Flex Credits |
| Calendly Teams seat | $16 per month, annual | [zeeg, 2026](https://zeeg.me/en/blog/post/calendly-pricing-guide); seats 1-30 tier |
| Data 360 rows processed per month | 6 million | Placeholder: Canvas page views, submissions, attendance, discussions, Banner aid, for 8,000 students |
| Data 360 pipeline credits per million rows | 3,500 | Rate card "Streaming Pipeline", base tier. Used as an upper bound: zero-copy Direct Access streams may be billed lower or differently |
| Data 360 query credits per million rows | 3 | Rate card, base tier; ~2,000 rows read per 360 lookup |
| Data 360 unification credits per million rows | 75,000 | Rate card, base tier; ~50,000 changed profile rows per month |
| Prep time per student, before / after | 20 / 5 minutes | Placeholder; the pilot measures it |
| Advisor loaded cost | $35 per hour | Placeholder |
| Net revenue per retained student-year | $10,000 | Placeholder; Post finance to replace |
| Build effort | 160 hours at $150 | Hardening, tests in CI, OAuth, Education Cloud relationships, pilot support |

## Results

| | Year 1 |
|---|---|
| Cost per full student prep | **$0.62** |
| Cost per quick lookup | $0.20 |
| Agent actions (Flex Credits) | $19,904 |
| Data 360 consumption | $1,487 |
| Agentforce user licenses | $2,400 |
| Calendly Teams seats | $7,680 |
| **Run cost** | **$31,471** (about $790 per advisor) |
| One-time build | $24,000 |
| **Year 1 total** | **$55,471** |
| Advisor hours returned (15 min × 19,200 preps) | 4,800 hours, about $168,000 |
| **Students retained to break even, revenue only** | **5.5 students** in year 1 |

The break-even ignores the time saved entirely. It is the number of extra students who stay a year that pays for the whole first year. At 8,000 students that is under 0.1 percentage points of persistence.

## Sensitivity

| Scenario | Run cost | Year 1 | Break-even students |
|---|---|---|---|
| Base | $31,471 | $55,471 | 5.5 |
| Advisors use it twice as much | $51,377 | $75,377 | 7.5 |
| Ten times the Data 360 rows | $42,811 | $66,811 | 6.7 |
| Prep only drops from 20 to 15 minutes | $31,471 | $55,471 | 5.5 (time value falls to $56,000) |

Agent actions are the largest variable cost, not Data 360. Usage is the number to watch in the pilot.

## What would change this

- **Post already owns Agentforce or Data 360 credits.** An Agentforce 1 or Education Cloud bundle may include Flex Credits, which would remove most of the run cost.
- **Flat per-user pricing.** An Agentforce add-on at $125 per user per month ($60,000 a year for 40 advisors) is unmetered. It only beats Flex Credits if each advisor runs well over 100 full preps a week.
- **Direct Access billing.** If federated Snowflake reads are billed per query rather than per row ingested, the Data 360 line changes shape. Check the contract.
- **Calendly.** If advisors already have Calendly seats, that line is zero.

## How the pilot replaces the placeholders

- Usage per advisor: from agent session logs (see [operations](operations.md)).
- Prep time: from the time study before launch and session timing after.
- Credits actually consumed: from the Digital Wallet in Setup, per week.
- Retention value: from Post finance (net tuition per retained student-year) and institutional research (persistence for the pilot team against last term).
