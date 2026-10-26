"""Builds the two agent flows from one definition.

python3 tools/build_flows.py <out_dir>
  writes <out_dir>/<Flow>.json   Tooling API payloads ({"FullName", "Metadata"})
  writes force-app/main/default/flows/<Flow>.flow-meta.xml for the repo

Both flows call CheckStudentAccessAction (Apex) first and stop unless the advisor owns the student.
"""
import json, os, sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFUSE = 'There is no student record owned by you with that information.'


def ref(name): return {'elementReference': name}
def text(s): return {'stringValue': s}
def var(name, dtype, inp=False, out=False, obj=None, default=None):
    v = {'name': name, 'dataType': dtype, 'isCollection': False, 'isInput': inp, 'isOutput': out}
    if obj: v['objectType'] = obj
    if default is not None: v['value'] = default
    return v
def formula(name, dtype, expr): return {'name': name, 'dataType': dtype, 'expression': expr}
def goto(target): return {'targetReference': target}
def assign(name, label, items, nxt=None, x=0, y=0):
    a = {'name': name, 'label': label, 'locationX': x, 'locationY': y,
         'assignmentItems': [{'assignToReference': k, 'operator': 'Assign', 'value': v} for k, v in items]}
    if nxt: a['connector'] = goto(nxt)
    return a
def is_true(name, label, var_name, yes, no, no_label, x=0, y=0):
    return {'name': name, 'label': label, 'locationX': x, 'locationY': y,
            'defaultConnector': goto(no), 'defaultConnectorLabel': no_label,
            'rules': [{'name': name + '_Yes', 'label': 'Yes', 'conditionLogic': 'and',
                       'conditions': [{'leftValueReference': var_name, 'operator': 'EqualTo',
                                       'rightValue': {'booleanValue': True}}],
                       'connector': goto(yes)}]}

ACCESS_OUTPUTS = [('accessAllowed', 'allowed'), ('accessStudentName', 'studentName'), ('accessMessage', 'message')]
def access_check(nxt):
    return {'name': 'Check_Student_Access', 'label': 'Check Student Access', 'locationX': 176, 'locationY': 134,
            'actionName': 'CheckStudentAccessAction', 'actionType': 'apex',
            'inputParameters': [{'name': 'studentRecordId', 'value': ref('studentRecordId')}],
            'outputParameters': [{'assignToReference': a, 'name': n} for a, n in ACCESS_OUTPUTS],
            'storeOutputAutomatically': False, 'connector': goto(nxt)}
ACCESS_VARS = [var('accessAllowed', 'Boolean', default={'booleanValue': False}),
               var('accessStudentName', 'String'), var('accessMessage', 'String')]
REFUSE_STEP = lambda: assign('Refuse', 'Refuse: not this advisor\'s student',
                             [('message', ref('accessMessage')), ('success', {'booleanValue': False})], x=440, y=350)


def task_flow():
    return {
        'apiVersion': 66.0, 'label': 'Advisor - Create Student Task', 'processType': 'AutoLaunchedFlow', 'status': 'Active',
        'interviewLabel': 'Advisor - Create Student Task {!$Flow.CurrentDateTime}',
        'description': 'Agent action: creates a follow-up task for the advisor on one of their students. '
                       'Calls CheckStudentAccessAction first and creates nothing unless the advisor owns the student.',
        'start': {'locationX': 50, 'locationY': 0, 'connector': goto('Check_Student_Access')},
        'actionCalls': [access_check('Is_Allowed')],
        'decisions': [
            is_true('Is_Allowed', 'Advisor owns the student?', 'accessAllowed', 'Has_Subject', 'Refuse', 'Not allowed', 176, 242),
            is_true('Has_Subject', 'Subject given?', 'fHasSubject', 'Create_Task', 'Need_Subject', 'No subject', 176, 350),
        ],
        'recordCreates': [{
            'name': 'Create_Task', 'label': 'Create Task', 'locationX': 176, 'locationY': 458, 'object': 'Task',
            'assignRecordIdToReference': 'taskId', 'storeOutputAutomatically': False,
            'inputAssignments': [{'field': f, 'value': v} for f, v in [
                ('WhoId', ref('studentRecordId')), ('OwnerId', ref('$User.Id')), ('Subject', ref('fSubject')),
                ('Description', ref('description')), ('ActivityDate', ref('fDueDate')),
                ('Priority', ref('fPriority')), ('Status', text('Not Started'))]],
            'connector': goto('Report_Created'), 'faultConnector': goto('Report_Fault')}],
        'assignments': [
            REFUSE_STEP(),
            assign('Need_Subject', 'Ask for a subject', [('message', text('A task subject is required.'))], x=440, y=458),
            assign('Report_Created', 'Report the task', [('success', {'booleanValue': True}), ('message', ref('fCreatedMessage'))], x=176, y=566),
            assign('Report_Fault', 'Report the error', [('message', ref('fFaultMessage'))], x=440, y=566),
        ],
        'formulas': [
            formula('fHasSubject', 'Boolean', 'NOT(ISBLANK({!subject}))'),
            formula('fSubject', 'String', 'LEFT({!subject}, 255)'),
            formula('fDueDate', 'Date', 'IF(ISBLANK({!dueDate}), TODAY() + 3, {!dueDate})'),
            formula('fPriority', 'String', 'CASE(LOWER({!priority}), "high", "High", "low", "Low", "Normal")'),
            formula('fCreatedMessage', 'String', '"Task \\"" & {!fSubject} & "\\" created for " & {!accessStudentName} & ", due " & TEXT({!fDueDate}) & "."'),
            formula('fFaultMessage', 'String', '"Could not create the task: " & {!$Flow.FaultMessage}'),
        ],
        'variables': [
            var('studentRecordId', 'String', inp=True), var('subject', 'String', inp=True),
            var('description', 'String', inp=True), var('dueDate', 'Date', inp=True), var('priority', 'String', inp=True),
            var('success', 'Boolean', out=True, default={'booleanValue': False}),
            var('taskId', 'String', out=True), var('message', 'String', out=True),
        ] + ACCESS_VARS,
    }


# The flow's inputs are the allow-list: only these five fields can change, so there is no JSON to validate.
UPDATE_FIELDS = [('studentStage', 'Student_Stage__c', 'Student Stage'), ('studentLevel', 'Student_Level__c', 'Student Level'),
                 ('email', 'Email', 'Email'), ('phone', 'Phone', 'Phone'), ('mobilePhone', 'MobilePhone', 'Mobile Phone')]

def update_flow():
    changed = ' & '.join('IF(ISBLANK({!%s}), "", "%s, ")' % (i, label) for i, _, label in UPDATE_FIELDS)
    return {
        'apiVersion': 66.0, 'label': 'Advisor - Update Student Record', 'processType': 'AutoLaunchedFlow', 'status': 'Active',
        'interviewLabel': 'Advisor - Update Student Record {!$Flow.CurrentDateTime}',
        'description': 'Agent action: updates stage, level, email, phone or mobile phone on one of the advisor\'s students. '
                       'Calls CheckStudentAccessAction first. Fields left blank are not changed; no other field can be.',
        'start': {'locationX': 50, 'locationY': 0, 'connector': goto('Check_Student_Access')},
        'actionCalls': [access_check('Is_Allowed')],
        'decisions': [
            is_true('Is_Allowed', 'Advisor owns the student?', 'accessAllowed', 'Has_Changes', 'Refuse', 'Not allowed', 176, 242),
            is_true('Has_Changes', 'Any change given?', 'fAnyChange', 'Get_Student', 'No_Changes', 'Nothing to change', 176, 350),
        ],
        'recordLookups': [{
            'name': 'Get_Student', 'label': 'Get Student', 'locationX': 176, 'locationY': 458, 'object': 'Contact',
            'filterLogic': 'and', 'filters': [{'field': 'Id', 'operator': 'EqualTo', 'value': ref('studentRecordId')}],
            'getFirstRecordOnly': True, 'outputReference': 'student', 'storeOutputAutomatically': False,
            'queriedFields': ['Id'] + [f for _, f, _ in UPDATE_FIELDS],
            'connector': goto('Apply_Changes'), 'faultConnector': goto('Report_Fault')}],
        'recordUpdates': [{
            'name': 'Update_Student', 'label': 'Update Student', 'locationX': 176, 'locationY': 674,
            'inputReference': 'student', 'connector': goto('Report_Updated'), 'faultConnector': goto('Report_Fault')}],
        'assignments': [
            REFUSE_STEP(),
            assign('No_Changes', 'Explain what can change', [('message', text(
                'No changes were given. Student Stage, Student Level, Email, Phone and Mobile Phone can be updated.'))], x=440, y=458),
            assign('Apply_Changes', 'Apply only the given fields',
                   [('student.' + f, ref('f_' + i)) for i, f, _ in UPDATE_FIELDS], nxt='Update_Student', x=176, y=566),
            assign('Report_Updated', 'Report the update', [('success', {'booleanValue': True}), ('updatedFields', ref('fChangedList')),
                                                          ('message', ref('fUpdatedMessage'))], x=176, y=782),
            assign('Report_Fault', 'Report the error', [('message', ref('fFaultMessage'))], x=440, y=782),
        ],
        'formulas': [formula('f_' + i, 'String', 'IF(ISBLANK({!%s}), {!student.%s}, {!%s})' % (i, f, i)) for i, f, _ in UPDATE_FIELDS] + [
            formula('fAnyChange', 'Boolean', 'NOT(AND(' + ', '.join('ISBLANK({!%s})' % i for i, _, _ in UPDATE_FIELDS) + '))'),
            formula('fChangedList', 'String', 'LEFT(' + changed + ', LEN(' + changed + ') - 2)'),
            formula('fUpdatedMessage', 'String', '"Updated " & {!accessStudentName} & ": " & {!fChangedList} & "."'),
            formula('fFaultMessage', 'String', '"Could not update the student record: " & {!$Flow.FaultMessage}'),
        ],
        'variables': [var('studentRecordId', 'String', inp=True)] + [var(i, 'String', inp=True) for i, _, _ in UPDATE_FIELDS] + [
            var('student', 'SObject', obj='Contact'),
            var('success', 'Boolean', out=True, default={'booleanValue': False}),
            var('updatedFields', 'String', out=True), var('message', 'String', out=True),
        ] + ACCESS_VARS,
    }


FLOWS = {'Advisor_Create_Student_Task': task_flow, 'Advisor_Update_Student_Record': update_flow}

def to_xml(tag, val, ind):
    pad = '    ' * ind
    if isinstance(val, dict):
        inner = ''.join(to_xml(k, val[k], ind + 1) for k in sorted(val))
        return f'{pad}<{tag}>\n{inner}{pad}</{tag}>\n'
    if isinstance(val, list):
        return ''.join(to_xml(tag, v, ind) for v in val)
    if isinstance(val, bool): val = 'true' if val else 'false'
    return f'{pad}<{tag}>{escape(str(val))}</{tag}>\n'

if __name__ == '__main__':
    out_dir = sys.argv[1]
    flows_dir = os.path.join(ROOT, 'force-app', 'main', 'default', 'flows')
    os.makedirs(flows_dir, exist_ok=True)
    for name, build in FLOWS.items():
        md = build()
        json.dump({'FullName': name, 'Metadata': md}, open(os.path.join(out_dir, name + '.json'), 'w'))
        body = ''.join(to_xml(k, md[k], 1) for k in sorted(md))
        open(os.path.join(flows_dir, name + '.flow-meta.xml'), 'w').write(
            '<?xml version="1.0" encoding="UTF-8"?>\n<Flow xmlns="http://soap.sforce.com/2006/04/metadata">\n' + body + '</Flow>\n')
        print(name, len(json.dumps(md)))
