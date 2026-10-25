-- Student Engagement Score (Student_Engagement_Score__cio)
-- Calculated insight as deployed in the demo org. ANSI SQL dialect, refreshed every 12 hours.
-- Dimension: unified_individual_id__c   Measure: engagement_score__c (0-100)
--
-- Weights: 35% on-time submissions (late = half, excused excluded)
--          30% attendance (tardy = half, excused excluded)
--          20% LMS page views, capped at 20
--          15% discussion posts, capped at 5
-- Grades are deliberately left out: the score describes behaviour, not performance.
-- Each source is aggregated in its own subquery so the fact tables don't multiply rows.

SELECT
  ROUND(100 * SUM(
      0.35 * CASE WHEN subs.submission_rate  IS NULL THEN 0 ELSE subs.submission_rate  END
    + 0.30 * CASE WHEN att.attendance_rate   IS NULL THEN 0 ELSE att.attendance_rate   END
    + 0.20 * CASE WHEN pv.page_view_score    IS NULL THEN 0 ELSE pv.page_view_score    END
    + 0.15 * CASE WHEN disc.discussion_score IS NULL THEN 0 ELSE disc.discussion_score END
  ), 1) AS engagement_score__c,
  UnifiedIndividual__dlm.ssot__Id__c AS unified_individual_id__c
FROM UnifiedIndividual__dlm

LEFT OUTER JOIN (
  SELECT
    UnifiedIndividual__dlm.ssot__Id__c AS unified_individual_id,
    SUM(CASE WHEN Canvas_Submissions__dlm.workflow_state__c = 'graded' THEN 1.0
             WHEN Canvas_Submissions__dlm.workflow_state__c = 'late'   THEN 0.5
             ELSE 0 END)
    / SUM(CASE WHEN Canvas_Submissions__dlm.workflow_state__c = 'excused' THEN 0 ELSE 1 END)
      AS submission_rate
  FROM Canvas_Submissions__dlm
  JOIN IndividualIdentityLink__dlm
    ON Canvas_Submissions__dlm.user_id__c = IndividualIdentityLink__dlm.SourceRecordId__c
  JOIN UnifiedIndividual__dlm
    ON IndividualIdentityLink__dlm.UnifiedRecordId__c = UnifiedIndividual__dlm.ssot__Id__c
  GROUP BY UnifiedIndividual__dlm.ssot__Id__c
) subs ON UnifiedIndividual__dlm.ssot__Id__c = subs.unified_individual_id

LEFT OUTER JOIN (
  SELECT
    UnifiedIndividual__dlm.ssot__Id__c AS unified_individual_id,
    SUM(CASE WHEN Snowflake_Canvas_Attendance__dlm.status__c = 'present' THEN 1.0
             WHEN Snowflake_Canvas_Attendance__dlm.status__c = 'tardy'   THEN 0.5
             ELSE 0 END)
    / SUM(CASE WHEN Snowflake_Canvas_Attendance__dlm.status__c = 'excused' THEN 0 ELSE 1 END)
      AS attendance_rate
  FROM Snowflake_Canvas_Attendance__dlm
  JOIN IndividualIdentityLink__dlm
    ON Snowflake_Canvas_Attendance__dlm.user_id__c = IndividualIdentityLink__dlm.SourceRecordId__c
  JOIN UnifiedIndividual__dlm
    ON IndividualIdentityLink__dlm.UnifiedRecordId__c = UnifiedIndividual__dlm.ssot__Id__c
  GROUP BY UnifiedIndividual__dlm.ssot__Id__c
) att ON UnifiedIndividual__dlm.ssot__Id__c = att.unified_individual_id

LEFT OUTER JOIN (
  SELECT
    UnifiedIndividual__dlm.ssot__Id__c AS unified_individual_id,
    LEAST(1.0, COUNT(Snowflake_Canvas_Page_Views__dlm.event_id__c) / 20.0) AS page_view_score
  FROM Snowflake_Canvas_Page_Views__dlm
  JOIN IndividualIdentityLink__dlm
    ON Snowflake_Canvas_Page_Views__dlm.user_id__c = IndividualIdentityLink__dlm.SourceRecordId__c
  JOIN UnifiedIndividual__dlm
    ON IndividualIdentityLink__dlm.UnifiedRecordId__c = UnifiedIndividual__dlm.ssot__Id__c
  GROUP BY UnifiedIndividual__dlm.ssot__Id__c
) pv ON UnifiedIndividual__dlm.ssot__Id__c = pv.unified_individual_id

LEFT OUTER JOIN (
  SELECT
    UnifiedIndividual__dlm.ssot__Id__c AS unified_individual_id,
    LEAST(1.0, COUNT(Snowflake_Canvas_Discussion_Entries__dlm.entry_id__c) / 5.0) AS discussion_score
  FROM Snowflake_Canvas_Discussion_Entries__dlm
  JOIN IndividualIdentityLink__dlm
    ON Snowflake_Canvas_Discussion_Entries__dlm.user_id__c = IndividualIdentityLink__dlm.SourceRecordId__c
  JOIN UnifiedIndividual__dlm
    ON IndividualIdentityLink__dlm.UnifiedRecordId__c = UnifiedIndividual__dlm.ssot__Id__c
  GROUP BY UnifiedIndividual__dlm.ssot__Id__c
) disc ON UnifiedIndividual__dlm.ssot__Id__c = disc.unified_individual_id

GROUP BY unified_individual_id__c
