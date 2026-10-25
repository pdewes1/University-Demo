/**
 * Agent action: drafts a supportive email from the running user (the Academic Advisor)
 * to one of their students, grounded in the Student record and the Student 360 summary.
 * Calls the org's default LLM through the Einstein Models API (Einstein Trust Layer applies).
 * Only students owned by the running user can be drafted for. Nothing is sent.
 */
public with sharing class DraftStudentEmailAction {

    @TestVisible
    private static final String MODEL = 'sfdc_ai__DefaultGPT4Omni';

    public class Request {
        @InvocableVariable(label='Student Record Id' description='Salesforce Id of the Student (Contact) record.' required=true)
        public String studentRecordId;
        @InvocableVariable(label='Student Context' description='Student 360 summary from Get Student 360 Data.')
        public String studentContext;
        @InvocableVariable(label='Advisor Focus' description='Optional focus for the email, e.g. attendance or financial aid paperwork.')
        public String advisorFocus;
        @InvocableVariable(label='Include Booking Link' description='When true (default), adds a single-use Calendly link for booking a meeting with the advisor.')
        public Boolean includeBookingLink;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when a draft was produced.')
        public Boolean success;
        @InvocableVariable(label='Email Draft' description='Drafted email with a subject line, for the advisor to review.')
        public String emailDraft;
        @InvocableVariable(label='Message' description='Status or error message.')
        public String message;
        @InvocableVariable(label='Booking URL' description='The single-use Calendly link included in the email, if any.')
        public String bookingUrl;
    }

    @InvocableMethod(label='Draft Student Outreach Email' description='Drafts a supportive email from the advisor to a student based on their record and Data 360 summary. Does not send it.')
    public static List<Response> draft(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) results.add(handle(req));
        return results;
    }

    private static Response handle(Request req) {
        Response res = new Response();
        res.success = false;
        try {
            List<Contact> found = [
                SELECT Id, FirstName, LastName, Email, Student_Level__c, Student_Stage__c, OwnerId
                FROM Contact WHERE Id = :req.studentRecordId WITH USER_MODE LIMIT 1
            ];
            if (found.isEmpty() || found[0].OwnerId != UserInfo.getUserId()) {
                res.message = 'There is no student record owned by you with that information.';
                return res;
            }
            // Create the Calendly link first (callout) so the email can reference it. Failure is non-fatal.
            String linkNote = '';
            if (req.includeBookingLink != false) {
                try {
                    res.bookingUrl = CreateCalendlyBookingLinkAction.createForCurrentAdvisor(found[0].Id);
                } catch (Exception e) {
                    linkNote = ' No booking link was added: ' + e.getMessage();
                }
            }
            String prompt = buildPrompt(found[0], req.studentContext, req.advisorFocus,
                UserInfo.getFirstName() + ' ' + UserInfo.getLastName(), String.isNotBlank(res.bookingUrl));

            aiplatform.ModelsAPI.createChatGenerations_Request request = new aiplatform.ModelsAPI.createChatGenerations_Request();
            request.modelName = MODEL;
            aiplatform.ModelsAPI_ChatGenerationsRequest body = new aiplatform.ModelsAPI_ChatGenerationsRequest();
            aiplatform.ModelsAPI_ChatMessageRequest msg = new aiplatform.ModelsAPI_ChatMessageRequest();
            msg.role = 'user';
            msg.content = prompt;
            body.messages = new List<aiplatform.ModelsAPI_ChatMessageRequest>{ msg };
            request.body = body;

            aiplatform.ModelsAPI.createChatGenerations_Response response = new aiplatform.ModelsAPI().createChatGenerations(request);
            String firstName = String.isBlank(found[0].FirstName) ? found[0].LastName : found[0].FirstName;
            res.emailDraft = fillLink(fillNames(response.Code200.generationDetails.generations[0].content,
                firstName, UserInfo.getFirstName() + ' ' + UserInfo.getLastName()), res.bookingUrl);
            res.success = String.isNotBlank(res.emailDraft);
            res.message = (res.success ? 'Draft ready for review. It has not been sent.' : 'The model returned an empty draft.') + linkNote;
        } catch (aiplatform.ModelsAPI.createChatGenerations_ResponseException e) {
            res.message = 'Could not draft the email: ' + e.getMessage();
        } catch (Exception e) {
            res.message = 'Could not draft the email: ' + e.getMessage();
        }
        return res;
    }

    @TestVisible
    private static String buildPrompt(Contact s, String context, String focus, String advisorName, Boolean hasLink) {
        List<String> p = new List<String>();
        p.add('You are writing on behalf of an Academic Advisor at the university. Draft a short, warm, supportive email from the advisor to the student below.');
        p.add('');
        p.add('Student record: level ' + nv(s.Student_Level__c) + ', stage ' + nv(s.Student_Stage__c) + '.');
        p.add('Names are filled in later: write {FIRST_NAME} wherever you address the student by name, and sign the email as {ADVISOR_NAME}. Do not use any other name for the student or the advisor.');
        if (hasLink) {
            p.add('When you invite the student to meet, put {BOOKING_LINK} on its own line right after the invitation (for example "You can grab a time that works for you here:" then {BOOKING_LINK}). Use {BOOKING_LINK} exactly once and never write any other URL.');
        } else {
            p.add('Do not include any links; invite the student to reply to this email to set up a time.');
        }
        p.add('');
        p.add('What the advisor knows from Data 360 (attendance, coursework, grades, LMS activity, discussion participation, financial aid, engagement score):');
        p.add(String.isBlank(context) ? 'No Data 360 summary was provided.' : stripNames(context, s));
        p.add('');
        p.add('What the advisor wants this email to focus on: ' + (String.isBlank(focus) ? 'no specific focus' : stripNames(focus, s)));
        p.add('');
        p.add('Instructions:');
        p.add('1. Pick the one to three most important needs the data shows, for example low attendance, missing or late submissions, a low course score, little LMS activity, no discussion participation, a low engagement score, an incomplete FAFSA or verification, or satisfactory academic progress at risk. If the advisor gave a focus, lead with it.');
        p.add('2. Greet the student by first name and check in genuinely before raising anything. Do not open with a list of problems.');
        p.add('3. Mention specific observations in plain, non-judgmental language, for example "I noticed you missed a recent class in HIST 210". Never quote internal scores, system names, IDs, or raw numbers such as the engagement score or percentages; describe patterns instead.');
        p.add('4. Offer concrete help for each need: meeting with the advisor, tutoring or the writing center, talking to the instructor, the financial aid office, or student support services. Invite the student to reply or book a time to meet this week.');
        p.add('5. If the data shows the student is doing well, write a short encouraging note that recognizes their effort instead.');
        p.add('6. Keep it under 200 words, friendly and professional, in short paragraphs.');
        p.add('7. Never mention financial details such as aid amounts, Pell eligibility, or unmet need figures; only say the financial aid office can help review their aid.');
        p.add('8. Do not invent facts that are not in the information above.');
        p.add('');
        p.add('Return only the email in this format:');
        p.add('Subject: <subject line>');
        p.add('');
        p.add('<email body starting "Hi {FIRST_NAME}," and signed {ADVISOR_NAME}>');
        return String.join(p, '\n');
    }

    private static String nv(String v) { return String.isBlank(v) ? 'not recorded' : v; }

    // Keep the student's name out of the model prompt; the Trust Layer masks names and can unmask them inconsistently.
    @TestVisible
    private static String stripNames(String text, Contact s) {
        String out = text;
        for (String n : new List<String>{ s.FirstName + ' ' + s.LastName, s.LastName, s.FirstName }) {
            if (String.isNotBlank(n) && n.trim() != 'null') out = out.replace(n.trim(), 'the student');
        }
        return out;
    }

    @TestVisible
    private static String fillLink(String draft, String bookingUrl) {
        if (draft == null) return null;
        if (String.isBlank(bookingUrl)) return draft.replace('{BOOKING_LINK}', '').trim();
        if (draft.contains('{BOOKING_LINK}')) return draft.replace('{BOOKING_LINK}', bookingUrl);
        // Model omitted the placeholder: add the link before the sign-off rather than dropping it.
        return draft.trim() + '\n\nYou can book a time to meet with me here: ' + bookingUrl;
    }

    @TestVisible
    private static String fillNames(String draft, String firstName, String advisorName) {
        if (draft == null) return null;
        return draft.replace('{FIRST_NAME}', firstName).replace('{ADVISOR_NAME}', advisorName);
    }
}
