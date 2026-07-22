/**
 * @description Handles Academic Term trigger operations related to
 * automatic student promotion. When a new Academic Term is created
 * with Allow Auto Promote enabled and a Previous Term specified,
 * this handler automatically creates Academic Term Enrollment
 * records for students from the previous term.
 */
public class AcademicTermTriggerHandler {
    /**
 * @description Automatically promotes students from the Previous Term
 * to the newly created Academic Term. This method is invoked from the
 * AcademicTerm after insert trigger and executes only when:
 * - Allow_Auto_Promote__c is true.
 * - SPJIMR_Previous_term__c is populated.
 *
 * It fetches the previous term AcademicTermEnrollment records and
 * creates AcademicTermEnrollment records for the current term by
 * invoking SPJIMREnrolledStudentInTermController.createTermEnrollments().
 *
 * @param newTerms List of newly inserted AcademicTerm records.
 */
    public static void handleAutoPromotion(List<AcademicTerm> newTerms){
        
        for(AcademicTerm term : newTerms){
            
            if(term.Allow_Auto_Promote__c == true &&
               term.SPJIMR_Previous_term__c != null){
                   
                   List<AcademicTermEnrollment> previousEnrollments = [
                       SELECT Id
                       FROM AcademicTermEnrollment
                       WHERE AcademicTermId = :term.SPJIMR_Previous_term__c
                   ];
                   
                   List<Id> enrollmentIds = new List<Id>();
                   
                   for(AcademicTermEnrollment ate : previousEnrollments){
                       enrollmentIds.add(ate.Id);
                   }
                   if(!enrollmentIds.isEmpty()){
                       SPJIMREnrolledStudentInTermController.createTermEnrollments(
                           term.Id,
                           enrollmentIds,
                           null,
                           false,
                           'noDivision',
                           null,
                           false
                       );
                   }
               }
        }
    }
}