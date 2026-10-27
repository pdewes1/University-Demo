# Post University Student Success Agents

[About me](#about-me) · [About Post University](#about-post-university) · [The goal](#the-goal) · [The challenges](#the-challenges) · [Outcomes](#outcomes-were-driving-and-measuring) · [The recommendation](#the-recommendation) · [Assumptions](#assumptions) · [Technical specifics](#technical-specifics)

## About me

Hi There! My name is Paul Dewes, and I've worked in the Salesforce ecosystem since 2019.

**Salesforce Support.** I started at Salesforce on the Marketing Cloud Engagement Support team and moved up quickly to Swarm Lead, supporting a group of Support Engineers better work with our customers. There I worked on Marketing Cloud Engagement and Data 360 when it first launched.

**Gerent / TELUS.** A former colleague asked me to help start a Marketing Cloud practice at Gerent where I joined in January of 2023. We built new processes and reusable assets for the Marketing Cloud & Data 360 practice and implemented Marketing Cloud, Data 360 and Agentforce for a variety of different clients across multiple verticals. When Agentforce first launched, I was in the first group to build proofs of concept for customers.

**Today.** I'm a senior member of the Solution Architect team, specializing in Data 360, and I keep taking on new challenges and responsibilities such as Marketing Cloud Next and assisting with pre-sales conversations.

**Outside of work:**

- I'm the Game Master for three different tabletop roleplaying campaigns.
- I ride motorcycles in great places and on race tracks.
- I recently took my mom on her first vacation since I was born, to my favorite place in the US: Glacier National Park.

<table>
  <tr>
    <td width="50%"><img src="docs/images/about/motorcycle.jpg" alt="Paul cornering a KTM motorcycle on a winding forest road"></td>
    <td width="50%"><img src="docs/images/about/glacier.jpg" alt="Paul and his mom at an overlook in Glacier National Park"></td>
  </tr>
  <tr>
    <td align="center"><em>Riding on the Tail of the Dragon in Tennessee/North Carolina</em></td>
    <td align="center"><em>Glacier National Park, with my mom (who I learned is afraid of heights on the Going to the Sun Road where this picture is taken)</em></td>
  </tr>
</table>

<br>

---

<br>

## About Post University

Post University has been educating students in Waterbury, Connecticut, since 1890. Today, most Post University students learn online. Many of them are working adults, military-affiliated, career changers, or returning to finish a degree.

Post University knows that school is often the first thing to slip when work, family or service make demands on a student's time. For many students, a missed class becomes a missed assignment, and missed assignments can quickly snowball into course withdrawals, failing grades or leaving altogether.

Post University's promise is an education that works with students' lives, not against them. Leadership is now asking: *how can we step in and help students sooner, before it's too late?*

> **Demo scenario.** This is a design and validation exercise. It is not affiliated with or endorsed by the university, and all student data is synthetic. No real student data is used.

## The goal

- **More students stay enrolled and graduate.**
- **Staff have reliable tools** to understand and engage their students.
- **Staff give timely, relevant guidance**, reaching out while it can still make a difference.

## The challenges

- **Advisors work across siloed systems.** The early warning signs are spread across Canvas (missed classes, late work, fewer logins), Banner (financial aid paperwork) and the CRM (no recent contact, overdue follow-ups). Seeing the whole picture means opening all three and piecing it together by hand.
- **Each advisor covers more students.** Budget pressure has raised caseloads, so that prep work crowds out the outreach itself.
- **The data is messy and duplicated.** The same student appears several times across systems, which makes finding the right student and the right record harder.

## Outcomes we're driving and measuring

| Outcome | How we'll know |
|---|---|
| Advisors spend their time on students, not on gathering data | **Prep time per student** goes down |
| At-risk students hear from their advisor sooner | **Days from an engagement drop to outreach** go down |
| Outreach turns into conversations | **Share of flagged students who book a meeting** goes up |
| Fewer students leave; more graduate | Term-to-term persistence, attrition and graduation rate, tracked over terms |
| Faster isn't careless | Advisor edits per draft, access refusals, and zero financial aid amounts exposed |

The first three move within weeks, so they decide the pilot. Persistence and graduation take terms, so they decide the rollout.

## The recommendation

Give every advisor an **Advisor Agent** in Agentforce, grounded in one trusted view of each student from **Data 360**.

The agent brings Banner, Canvas and the CRM together for one student, tells the advisor the two or three things that need attention, and turns that into action: a supportive outreach email with a single-use booking link, a follow-up task and a note. It works only on the advisor's own students, and nothing goes to a student without the advisor reviewing it. Banner and Canvas stay where they are, read from Snowflake with zero copy.

![Overview](docs/images/architecture-overview.png)

| Today | With the Advisor Agent |
|---|---|
| Opens three systems to prepare for one student | Asks "What should I know about this student?" and gets one summary |
| Notices disengagement when a grade drops or the student goes quiet | Sees attendance, LMS activity, engagement and the last contact together, with what to act on |
| Writes each check-in email from scratch | Reviews a specific, supportive draft with a booking link for that student |
| Follow-ups live in memory or a notebook | A task and a note are logged on the student record in the same conversation |

**How it gets there:** take baselines → pilot with one advising team → roll out to all advisors and track persistence → phase 2, an Admissions Agent. Running cost grows with how much advisors use the agent, not with the number of students, and keeping a small number of extra students enrolled covers the first year. [Costs and savings](docs/cost-model.md)

## Assumptions

- **Outreach timing matters for retention.** If faster outreach doesn't raise bookings, the agent saves advisors time but doesn't move persistence. The pilot tests this directly.
- **The engagement score flags the right students.** Before rollout, compare who it flags with who actually withdrew last term.
- **Bookings can be measured.** The pilot needs Calendly booking events written back to the CRM.
- **The CRM knows each student's advisor.** A nightly load from Banner keeps students and their assigned advisor (the Contact owner) current in Education Cloud.

## Technical specifics

The full depth lives in [**Technical details**](docs/technical-details.md). Start there, or go straight to a topic:

| Topic | Where |
|---|---|
| The agent, its actions, and the Flow + Apex build | [Advisor Agent](docs/technical-details.md#advisor-agent) · [Why each action is Flow or Apex](docs/flow-vs-apex.md) |
| Architecture, what stays where, trust boundaries | [Architecture](docs/technical-details.md#architecture) |
| Data streams, identity resolution, engagement score, data graph | [Data 360](docs/technical-details.md#data-360) |
| How it was tested, and what the tests changed | [Validation summary](docs/technical-details.md#focused-technical-validation) · [Full write-up and raw results](validation/README.md) |
| Building it in your own org | [Setup](docs/technical-details.md#setup) · [Repository structure](docs/technical-details.md#repository-structure) |
| Running it | [Operations](docs/operations.md) · [Demo script](docs/demo-script.md) |
| Handing it to a build team | [Execution handoff](docs/execution-handoff.md) · [What changes if a constraint changes](docs/changed-constraints.md) |
| Cost, limits and AI use | [Costs and savings](docs/cost-model.md) · [Limitations](docs/technical-details.md#limitations) · [How AI was used](docs/ai-usage.md) |
