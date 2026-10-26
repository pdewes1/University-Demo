# Costs and savings

The Advisor Agent's running cost grows with how much advisors use it, not with how many students the university has. Its value comes from advisor time returned and, more importantly, from students who stay enrolled. A small number of retained students would cover the first year's cost, before counting any time saved.

Exact figures depend on Post's existing Salesforce and Data 360 entitlements, contracted rates and real usage, so this page describes what drives cost and savings, and how the pilot turns them into numbers.

## What it costs

| Cost | How it's charged | What drives it | Relative size |
|---|---|---|---|
| **Agent actions** | Agentforce consumption (Flex Credits): a set number of credits per action, plus a little more for each email the model drafts | How often advisors use the agent. A full student prep (find, summary, email, booking link, task, note) is about six actions; a quick lookup is two | Largest variable cost |
| **Data 360** | Consumption credits for data processed: stream refreshes, identity resolution and graph queries | The volume of Canvas and Banner activity refreshed each day, and how often student summaries are pulled | Small, unless data volume grows sharply |
| **Agentforce user licenses** | Per advisor, per month, when paying by consumption | Number of advisors using the agent | Small and predictable |
| **Calendly** | Per advisor seat (Teams plan) | Number of advisors who send booking links | Moderate; nothing if advisors already have seats |
| **Build and hardening** | One-time effort | Tests in CI, Calendly OAuth, the advising relationship model in Education Cloud, pilot support | One-time, in the first year |

**Agent usage is the number to watch.** Data 360 and the fixed costs stay fairly flat; actions rise directly with use. Doubling how often advisors use the agent raises the running cost noticeably but doesn't change the break-even much, because the value of each retained student is far larger than the cost of the preps behind it.

## Where the savings come from

1. **Students who stay enrolled.** This is the main return. Each student who persists another year keeps a year of tuition revenue. Because outreach happens sooner and is easier to act on, even a fraction of a percentage point of persistence is enough to cover the cost.
2. **Advisor time.** Preparing for one student today means opening Banner, Canvas and the CRM and piecing it together. The agent replaces that with one question. Across every advisor and every prep in a term, that adds up to many hours returned to working with students, without adding staff.
3. **Faster, more consistent outreach.** Drafted emails with a booking link already in them shorten the time from noticing a problem to reaching the student, and make sure every flagged student gets a real follow-up and a logged note.
4. **No new data infrastructure.** Banner and Canvas stay in Snowflake and are read in place (zero copy), so there's no new pipeline or copy of the data to build and maintain.

## Ways to keep cost down

- **Use what Post already has.** Existing Agentforce, Data 360 or Education Cloud bundles may already include credits, which would cover much of the running cost.
- **Choose the right pricing model.** Consumption pricing suits light or uneven use. A flat per-advisor add-on can be cheaper if advisors use the agent heavily every day. The pilot's usage data decides which.
- **Pull only what's needed.** The data graph already limits activity to the last 30 days and refreshes daily. Keep it that way unless advisors need fresher data.
- **Skip Calendly seats advisors don't need.** Only advisors who send booking links need one.

## How the pilot turns this into numbers

| Question | Measured from |
|---|---|
| How much do advisors use it? | Agent session logs, per advisor per week |
| What does that use actually cost? | Setup › Digital Wallet: credits used per week |
| How much prep time does it save? | A time study before launch, then session timing after |
| Does earlier outreach keep students? | Persistence for the pilot team against last term (institutional research) |
| What is a retained student worth? | Net tuition per retained student-year (Post finance) |

With those five answers, the break-even becomes a real number instead of an estimate: the year's total cost divided by the value of one retained student.
