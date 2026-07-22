public with sharing class EventInvitationSender {

    public class Request {

        @InvocableVariable(required=true)
        public List<String> formattedContactIds;

        @InvocableVariable(required=true)
        public String emailSubject;

        @InvocableVariable(required=true)
        public Datetime emailStartDateTime;

        @InvocableVariable(required=true)
        public Datetime emailEndDateTime;

        @InvocableVariable
        public String emailDescription;

        @InvocableVariable
        public String emailLocation;
    }

    @InvocableMethod(label='Send Event Invitation')
    public static void sendInvitation(List<Request> requests) {

        List<Messaging.SingleEmailMessage> emails =
            new List<Messaging.SingleEmailMessage>();

        for(Request req : requests){

            if(req.formattedContactIds == null ||
               req.formattedContactIds.isEmpty()){
                continue;
            }

            List<Contact> contacts = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :req.formattedContactIds
                AND Email != null
            ];

            for(Contact con : contacts){

                String uidValue =
                    String.valueOf(Crypto.getRandomLong());

                String startDate =
                    req.emailStartDateTime.formatGMT(
                        'yyyyMMdd\'T\'HHmmss\'Z\''
                    );

                String endDate =
                    req.emailEndDateTime.formatGMT(
                        'yyyyMMdd\'T\'HHmmss\'Z\''
                    );

                String dtStamp =
                    Datetime.now().formatGMT(
                        'yyyyMMdd\'T\'HHmmss\'Z\''
                    );
                String locationValue =
                    String.isBlank(req.emailLocation)
                    ? 'Salesforce Meeting'
                    : req.emailLocation;

                String icsBody =
                    'BEGIN:VCALENDAR\n' +
                    'VERSION:2.0\n' +
                    'PRODID:-//Salesforce//Event Invite//EN\n' +
                    'METHOD:REQUEST\n' +
                    'BEGIN:VEVENT\n' +
                    'UID:' + uidValue + '\n' +
                    'DTSTAMP:' + dtStamp + '\n' +
                    'DTSTART:' + startDate + '\n' +
                    'DTEND:' + endDate + '\n' +
                    'SUMMARY:' + req.emailSubject + '\n' +
                    'DESCRIPTION:' +
                        (req.emailDescription == null
                            ? ''
                            : req.emailDescription) + '\n' +
                    'LOCATION:' +
                        locationValue  + '\n' +
                    'STATUS:CONFIRMED\n' +
                    'SEQUENCE:0\n' +
                    'END:VEVENT\n' +
                    'END:VCALENDAR';

                Messaging.EmailFileAttachment attachment =
                    new Messaging.EmailFileAttachment();

                attachment.setFileName('EventInvitation.ics');
                attachment.setBody(Blob.valueOf(icsBody));
                attachment.setContentType('text/calendar');

                Messaging.SingleEmailMessage email =
                    new Messaging.SingleEmailMessage();

                email.setToAddresses(
                    new List<String>{ con.Email }
                );

                email.setSubject(
                    'Event Invitation: ' + req.emailSubject
                );

                email.setPlainTextBody(
                    'Hi ' + con.Name + ',\n\n' +
                    'You have been invited to an event.\n\n' +
                    'Event: ' + req.emailSubject + '\n' +
                    'Start: ' +
                        String.valueOf(req.emailStartDateTime) + '\n' +
                    'End: ' +
                        String.valueOf(req.emailEndDateTime) + '\n' +
                    'Description: '+String.valueOf(req.emailDescription)
                );

                email.setFileAttachments(
                    new List<Messaging.EmailFileAttachment>{
                        attachment
                    }
                );

                emails.add(email);
            }
        }

        if(!emails.isEmpty()){
            Messaging.sendEmail(emails);
            system.debug('Emails Sent successfully!' + emails);
        }
    }
}