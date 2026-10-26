"""Cost and investment model for the Academic Advisor agent. Every input is an assumption
listed in ASSUMPTIONS; change them and rerun (python3 tools/cost_model.py) to update docs/cost-model.md numbers."""
A = dict(
    advisors=40, students=8000, weeks=40,                     # scale (placeholder until Post confirms)
    full_preps_per_advisor_week=12, quick_lookups_per_advisor_week=25,
    flex_price=0.005,                                          # $ per Flex Credit ($500 / 100k)
    credits_per_action=20, credits_per_standard_prompt=4,
    agentforce_user_license=5,                                 # $ per user per month
    calendly_teams_seat_year=16*12,                            # $ per seat per year, annual billing
    dc_rows_per_month_millions=6.0,                            # Canvas + Banner rows refreshed per month
    dc_pipeline_credits_per_m=3500,                            # rate card streaming pipeline (upper bound for batch)
    dc_query_credits_per_m=3, dc_query_rows_per_lookup=2000,
    dc_unification_credits_per_m=75000, dc_unification_rows_per_month_millions=0.05,
    prep_minutes_before=20, prep_minutes_after=5, advisor_hourly_cost=35,
    net_revenue_per_retained_student=10000,                    # placeholder; replace with Post finance figure
    build_hours=160, build_hourly=150,                         # one-time partner/internal build
)
def run(a=A):
    full_actions, quick_actions = 6, 2   # find, 360, email(+prompt), booking, task, note | find, 360
    per_full = full_actions*a['credits_per_action'] + a['credits_per_standard_prompt']
    per_quick = quick_actions*a['credits_per_action']
    sessions_full = a['advisors']*a['full_preps_per_advisor_week']*a['weeks']
    sessions_quick = a['advisors']*a['quick_lookups_per_advisor_week']*a['weeks']
    agent_credits = sessions_full*per_full + sessions_quick*per_quick
    lookups = sessions_full + sessions_quick
    dc_credits = 12*(a['dc_rows_per_month_millions']*a['dc_pipeline_credits_per_m']
                     + a['dc_unification_rows_per_month_millions']*a['dc_unification_credits_per_m']) \
                 + lookups*a['dc_query_rows_per_lookup']/1e6*a['dc_query_credits_per_m']
    r = dict(per_full_usd=per_full*a['flex_price'], per_quick_usd=per_quick*a['flex_price'],
             agent_usd=agent_credits*a['flex_price'], dc_usd=dc_credits*a['flex_price'],
             licenses_usd=a['advisors']*a['agentforce_user_license']*12,
             calendly_usd=a['advisors']*a['calendly_teams_seat_year'],
             build_usd=a['build_hours']*a['build_hourly'])
    r['run_usd'] = r['agent_usd']+r['dc_usd']+r['licenses_usd']+r['calendly_usd']
    r['year1_usd'] = r['run_usd']+r['build_usd']
    hours_saved = sessions_full*(a['prep_minutes_before']-a['prep_minutes_after'])/60
    r['hours_saved'] = hours_saved; r['time_value_usd'] = hours_saved*a['advisor_hourly_cost']
    r['breakeven_students_year1'] = max(0, (r['year1_usd']-r['time_value_usd'])/a['net_revenue_per_retained_student'])
    r['agent_credits']=agent_credits; r['dc_credits']=dc_credits; r['sessions']=lookups
    return r
if __name__ == '__main__':
    for k, v in run().items(): print(f'{k:28s} {v:,.2f}')
