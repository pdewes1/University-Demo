# Data streams

As configured in the demo org (exported 2026-10-25).

| Data stream | Source | Stream type | Notes |
|---|---|---|---|
| `Contact_Home` | Salesforce CRM | Ingest (batch upsert) | About 850 rows. Students are Contacts, with `Student_ID__c` holding the Canvas user ID. |
| `Snowflake_Canvas_Users` | Snowflake (Canvas) | Direct Access (zero copy) | Profile category. `user_id` is the shared student identifier. |
| `Snowflake_Canvas_Courses` | Snowflake (Canvas) | Direct Access | |
| `Snowflake_Canvas_Enrollment` | Snowflake (Canvas) | Direct Access | |
| `Snowflake_Canvas_Assignments` | Snowflake (Canvas) | Direct Access | |
| `Snowflake_Canvas_Submissions` | Snowflake (Canvas) | Direct Access | Engagement category |
| `Snowflake_Canvas_Attendance` | Snowflake (Canvas) | Direct Access | |
| `Snowflake_Canvas_Page_Views` | Snowflake (Canvas) | Direct Access | Engagement category |
| `Snowflake_Canvas_Discussion_Entries` | Snowflake (Canvas) | Direct Access | Engagement category. Its relationship originally pointed at the wrong key and was corrected to `user_id`. |
| `Snowflake_Banner_Student_Profile` | Snowflake (Banner) | Direct Access | Carries the Party Identification columns. |
| `Snowflake_Banner_Financial_Aid_Summary` | Snowflake (Banner) | Direct Access | Joined on `banner_id` |
| `Snowflake_Banner_Financial_Aid_Awards` | Snowflake (Banner) | Direct Access | Not used by the agent yet. |

The CRM is ingested because Data 360 needs the Contact for identity resolution and the record relationship. Banner and Canvas stay in Snowflake and are queried live (federated), so no copy is made at the stream layer. The data graph is the exception; see [Student_360_Graph](data-graphs/Student_360_Graph.md).
