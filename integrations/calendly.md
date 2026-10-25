# Calendly integration

The Advisor Agent puts a **single-use** Calendly booking link in every outreach email, so a student can book time with their own advisor in one click. Calendly owns calendars and availability. Salesforce only asks Calendly for a link.

## Flow

```
Advisor (Agentforce panel or Slack)
  → Draft Student Outreach Email / Create Calendly Booking Link   (Apex action)
      → StudentAccess check: is this the advisor's student?
      → read User.Calendly_Event_Type_URI__c for the running advisor
      → POST callout:Calendly/scheduling_links
           { "max_event_count": 1, "owner": <event type URI>, "owner_type": "EventType" }
      ← 201 { "resource": { "booking_url": "https://calendly.com/d/xxxx-xxx-xxx" } }
      → add ?name=&email= so the booking form opens pre-filled with the student's details
  ← email draft with the link in it (never sent automatically)
```

A link is created **before** the LLM call. The prompt gets a `{BOOKING_LINK}` placeholder and Apex substitutes the real URL afterwards, so the model never sees or invents a URL. If Calendly fails, the email is still drafted, it asks the student to reply instead, and the agent tells the advisor why there is no link.

## Salesforce configuration

| Item | Value |
|---|---|
| External Credential | `Calendly_EC`, Custom protocol, named principal `CalendlyPAT` with one encrypted parameter `Token` |
| Named Credential | `Calendly`, URL `https://api.calendly.com`, custom header `Authorization: Bearer {!$Credential.Calendly_EC.Token}`, "Generate Authorization Header" off, "Allow Formulas in HTTP Header" on |
| Permission set | `Calendly_Access`: principal access to `Calendly_EC - CalendlyPAT`, plus read/edit on `User.Calendly_Event_Type_URI__c` |
| User field | `Calendly_Event_Type_URI__c` (URL) on each advisor, e.g. `https://api.calendly.com/event_types/{uuid}` |
| Trusted URL | `https://calendly.com` (Setup → Trusted URLs). Without it, the Agentforce panel replaces the link with `[URL_Redacted]`. |

The token lives only in the external credential. Nothing in this repo contains it.

### Token scopes

The personal access token needs at least:

- `scheduling_links:write`: create single-use links (the only scope used at run time)
- `event_types:read`: list an advisor's meeting types to find their URI
- `users:read` and `organizations:read`: admin lookups when onboarding a new advisor

## One token for every advisor

Tested on 2026-10-25. A token that belongs to the **owner of the Calendly organization** can create single-use links on **another member's** event type. A second advisor was invited to the Calendly organization, and a link was created on their 30-minute meeting with the owner's token (HTTP 201). Each advisor therefore only needs to:

1. Join the university's Calendly organization (Teams or Enterprise plan).
2. Have their event type URI set on their Salesforce user.
3. Be assigned the `Calendly_Access` permission set.

An advisor with a *separate* Calendly account outside the organization cannot be served by this token. That case would need a per-user credential (a per-user principal on the external credential, or OAuth).

## Finding an advisor's event type URI

Run the `List Calendly Event Types` admin action (`ListCalendlyEventTypesAction`) with the advisor's Calendly user URI. Or call the API directly:

```
GET https://api.calendly.com/event_types?organization=<org URI>
```

Each entry's `uri` is the value for `Calendly_Event_Type_URI__c`.

## Known gaps

- **Unused links pile up.** Every draft creates a link, even if the email is never sent. Production should create the link when the advisor sends the email, or expire unused links.
- **Bookings don't come back into Salesforce yet.** A Calendly `invitee.created` webhook into Salesforce would create the Event/Appointment and close the loop.
- **The token is over-privileged.** An org-owner personal access token is broader than the run-time need (`scheduling_links:write`). Production should use an OAuth app owned by a service account.
