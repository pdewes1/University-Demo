# Student_360_Graph

The data graph the Advisor Agent reads through `ConnectApi.CdpQuery.getDataGraphData('Student_360_Graph', <unified individual id>)`. It joins the unified profile, the engagement score, Canvas activity and the Banner financial aid summary into one JSON document per student.

- **Root:** `UnifiedIndividual__dlm`, keyed on `ssot__Id__c`
- **Refresh:** full refresh daily (incremental refresh off)
- **Definition:** [`Student_360_Graph.json`](Student_360_Graph.json) (the create payload; recreate with `d360_data_graph_create`)
- **Status in the demo org:** recreated 2026-10-25 without the Canvas `advisor` field (see below)

## Object tree

```
UnifiedIndividual__dlm                          ssot__Id__c, Student_ID__c, first/last/person name, pronoun
├── Student_Engagement_Score__cio               engagement_score__c        (unified_individual_id__c = ssot__Id__c)
└── IndividualIdentityLink__dlm                 SourceRecordId__c, data source  (UnifiedRecordId__c = ssot__Id__c)
    └── ssot__Individual__dlm                   ssot__Id__c, Student_ID__c       (ssot__Id__c = SourceRecordId__c)
        ├── Snowflake_Canvas_Users__dlm         major, class year, campus, enrollment status, last login
        │   │                                    (user_id__c = Individual.ssot__Id__c)
        │   ├── Snowflake_Canvas_Enrollment__dlm       course, state, current/final score, final grade
        │   ├── Snowflake_Canvas_Attendance__dlm       class date, course, status
        │   ├── Canvas_Submissions__dlm                 assignment, score, points possible, workflow state   [recency]
        │   ├── Snowflake_Canvas_Page_Views__dlm        event type, duration, event time                    [recency]
        │   └── Snowflake_Canvas_Discussion_Entries__dlm topic, entry type, word count, posted time          [recency]
        └── Snowflake_Banner_Financial_Aid_Summa__dlm  aid year, FAFSA, verification, SAP, Pell, offered/accepted/unmet need
                                                     (banner_id__c = Individual.ssot__Id__c)
```

The path goes through `IndividualIdentityLink` because each source keeps its own ID: the Canvas individual's ID is the Canvas `user_id` (`U00001`), and the Banner individual's ID is the Banner ID (S-number). Identity resolution links both to the same unified individual, so the graph reaches Canvas and Banner rows from one root.

## Recency limits

Submissions, page views and discussion entries are Engagement-category DMOs, so Data 360 requires recency criteria on them. Each one keeps **the last 30 days, up to 10 records**. 30 days is the maximum the UI allows.

So the agent sees a recent window of activity, not the whole term. `Student360DataAction` labels these lines "(recent window)" in the summary it gives the agent. The engagement score is calculated over all activity, so the score and the visible activity can differ.

## Not zero copy end to end

The Snowflake data streams are Direct Access (federated, zero copy). The data graph, however, materialises its own copy of the joined data inside Data 360 on each refresh. Graph data can therefore be up to a day behind Snowflake, and a copy of the projected fields (including financial aid figures) lives in Data 360.

## Advisor assignment lives in the CRM only

The Canvas users table in Snowflake had an `ADVISOR` column, and it disagreed with the CRM: Priya Cooper's Canvas advisor was "Jennifer Wilson" while her Contact owner is Paul. Two sources for the same fact invites the agent (or a person) to trust the wrong one, so for now **the CRM Contact owner is the only advisor assignment** in the design.

Removed on 2026-10-25, in this order:

1. **Data graph.** Data 360 doesn't allow removing a field from an existing graph (edits can only add fields), so the graph was deleted and recreated under the same name without it. Nothing depended on it.
2. **DMO field mapping** `advisor__c_fieldmap_advisor__c` on `Snowflake_Canvas_Users__dlm`.
3. **Data stream field.** `ADVISOR` disabled on the `Snowflake_Canvas_Users` stream, which also removed it from the data lake object and the DMO.

The column still exists in the Snowflake `CANVAS.PUBLIC.USERS` table; Data 360 just no longer reads it. Drop it there too if the source should change.

## Financial aid: status only for advisors

The graph still projects the Banner aid amounts, but `Student360DataAction` removes them before anything reaches the agent. An allow-list keeps only aid year, FAFSA status and received date, verification status, and satisfactory academic progress. Defense in depth for production: also drop the amount fields from the graph projection, so they're never copied into Data 360.
