/**
 * @description: Lead can be transferred to a different user, along with events and activities
 * @Date 12 September 2025
 */
public with sharing class AssignLeadHelper {
    
    
    /**
     * @description : Creates a new lead with the new Owner and Lead Source that has the selected program
     * @Date 12 September 2025
     * @param String LeadRecordId,String ProgramId,String UserId
     * @return Map<String,String>
     */
    @AuraEnabled
    public static Map<String,String> createLead(String LeadRecordId,String ProgramId,String UserId){
        Map<String,String> map_result = new Map<String,String>();
        try {
            
            Lead oldLead = [SELECT Id, LastName, FirstName, Salutation, Name, RecordTypeId, 
    Title, Company, Street, City, State, PostalCode, Country, Latitude, Longitude, GeocodeAccuracy, Address, 
    Phone, Email, Website, PhotoUrl, Description, LeadSource, Status, Industry, Rating, 
    AnnualRevenue, NumberOfEmployees, OwnerId, HasOptedOutOfEmail, 
     Jigsaw, JigsawContactId, EmailBouncedReason, EmailBouncedDate, IndividualId, 
    GenderIdentity, Date_Of_Birth__c, Events__c, Other__c, Publisher_Name__c, Referred_By__c, 
    Lead_Sub_Status__c, XS_CurrentlyStudingIn__c, XS_Year__c, XS_State__c, XS_City__c, 
    XS_YearsOfWorkExperience__c, XS_EntranceExamName__c, XS_SPJIMR_PartnerCompany__c, 
     XS_Programme__c, XS_College__c, 
    XS_HaveYouCompletedYourGraduation__c, Program_Master__c, Converted_From__c, Lead_Source__c, Notes__c
    FROM Lead  
    WHERE Id = :LeadRecordId 
    LIMIT 1];
            
            if (oldLead != null) {
                Lead newLead = new Lead();
                
                
                newLead.FirstName = oldLead.FirstName;
                newLead.LastName = oldLead.LastName;
                newLead.Salutation = oldLead.Salutation;
                
                newLead.Title = oldLead.Title;
                newLead.Company = oldLead.Company;
                newLead.Street = oldLead.Street;
                newLead.City = oldLead.City;
                newLead.State = oldLead.State;
                newLead.PostalCode = oldLead.PostalCode;
                newLead.Country = oldLead.Country;
                newLead.Latitude = oldLead.Latitude;
                newLead.Longitude = oldLead.Longitude;
                newLead.GeocodeAccuracy = oldLead.GeocodeAccuracy;
                
                newLead.Phone = oldLead.Phone;
                newLead.Email = oldLead.Email;
                newLead.Website = oldLead.Website;
                newLead.Description = oldLead.Description;
                newLead.LeadSource = oldLead.LeadSource;
                newLead.Status = oldLead.Status;
                newLead.Industry = oldLead.Industry;
                newLead.Rating = oldLead.Rating;
                newLead.AnnualRevenue = oldLead.AnnualRevenue;
                newLead.NumberOfEmployees = oldLead.NumberOfEmployees;
                
                newLead.GenderIdentity = oldLead.GenderIdentity;
                newLead.Date_Of_Birth__c = oldLead.Date_Of_Birth__c;
                //newLead.Other_Enquiry__c = oldLead.Other_Enquiry__c;
                newLead.Events__c = oldLead.Events__c;
                newLead.Other__c = oldLead.Other__c;
                newLead.Publisher_Name__c = oldLead.Publisher_Name__c;
                newLead.Referred_By__c = oldLead.Referred_By__c;
                newLead.Lead_Sub_Status__c = oldLead.Lead_Sub_Status__c;
                //newLead.Age__c = oldLead.Age__c;
                //newLead.XS_Source__c = oldLead.XS_Source__c;
                newLead.XS_CurrentlyStudingIn__c = oldLead.XS_CurrentlyStudingIn__c;
                //newLead.XS_Age__c = oldLead.XS_Age__c;
                newLead.XS_Year__c = oldLead.XS_Year__c;
                newLead.XS_State__c = oldLead.XS_State__c;
                newLead.XS_City__c = oldLead.XS_City__c;
                newLead.XS_YearsOfWorkExperience__c = oldLead.XS_YearsOfWorkExperience__c;
                //newLead.XS_DoYouHaveEntranceExamScore__c = oldLead.XS_DoYouHaveEntranceExamScore__c;
                newLead.XS_EntranceExamName__c = oldLead.XS_EntranceExamName__c;
                newLead.XS_SPJIMR_PartnerCompany__c = oldLead.XS_SPJIMR_PartnerCompany__c;
                //newLead.XS_EnterOrganisation__c = oldLead.XS_EnterOrganisation__c;
                newLead.XS_Programme__c = oldLead.XS_Programme__c;
                //newLead.XS_HowDidYouFindOutAboutUs__c = oldLead.XS_HowDidYouFindOutAboutUs__c;
                //newLead.XS_CurrentDesigination__c = oldLead.XS_CurrentDesigination__c;
                newLead.XS_College__c = oldLead.XS_College__c;
                newLead.XS_HaveYouCompletedYourGraduation__c = oldLead.XS_HaveYouCompletedYourGraduation__c;
                
                newLead.Converted_From__c = oldLead.Converted_From__c;
                newLead.Lead_Source__c = oldLead.Lead_Source__c;
                //newLead.Notes__c = oldLead.Notes__c;
                
                Map<String, Schema.RecordTypeInfo> leadRtByDev =
                    Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
                if (leadRtByDev != null && leadRtByDev.containsKey('B2B')) {
                    newLead.RecordTypeId = leadRtByDev.get('B2B').getRecordTypeId();
                } else {
                    newLead.RecordTypeId = oldLead.RecordTypeId;
                }
                newLead.Program_Master__c = ProgramId;
                newLead.OwnerId = UserId;
                Lead_Sources__c oldLeadSource = [SELECT Id,Lead__c,Program__c,Campaign__c FROM Lead_Sources__c WHERE Lead__c = :LeadRecordId AND Program__c = :ProgramId LIMIT 1];
                
                List<Event> listOldEvents = [SELECT Id,WhoId,OwnerId,ShowAs,Subject,Description,EventSubtype,StartDateTime,EndDateTime,IsAllDayEvent,Location FROM Event WHERE WhoId = :LeadRecordId];
                
                List<Task>listOldTasks = [SELECT Id, Subject, WhatId,TaskSubType,Status, ActivityDate,Priority,WhoId,OwnerId,
            IsHighPriority, Description, IsClosed FROM Task WHERE WhoId = :LeadRecordId];
                
                 
                system.debug('Event list is '+newLead.LastName+ ' '+listOldEvents);
                system.debug('Task Last is '+newLead.LastName+ ' '+listOldTasks);
                
                //Inserting new Lead
                Database.DMLOptions option = new Database.DMLOptions();
                option.DuplicateRuleHeader.AllowSave = true;
                Database.SaveResult sr = Database.insert(newLead, option);
                    if(oldLeadSource!=null && sr.isSuccess()){
                        Lead_Sources__c newLeadSource = oldLeadSource.clone(false,true,false,false);
                        newLeadSource.Lead__c = newLead.Id;
                        newLeadSource.Campaign__c = oldLeadSource.Campaign__c;
                        newLeadSource.Program__c = oldLeadSource.Program__c;
                        try{
                            //insert the new Lead Source
                            insert newLeadSource;
                        }
                        catch(DMLException e){
                            system.debug('Lead Source insertion Exception-> '+e.getMessage());
                            map_result.put('INSERTION_FAILED','Could not create a lead source');
                            return map_result;
                        }
                        
                        try{
                            if(oldLeadSource!=null){
                                //deleting the old Lead Source
                                delete oldLeadSource;
                            }
                        }
                        catch(DmlException e){
                            system.debug('Lead Source insertion Exception-> '+e.getMessage());
                            map_result.put('INSERTION_FAILED','Could not delete the old lead source');
                            return map_result;
                        }
                        List<Event> eventInsertList = new List<Event>();
                        List<Task> taskInsertList = new List<Task>();
                        if(listOldTasks.size()>0){
                            
                            for(Task t:listOldTasks){
                                Task newTask = t.clone(false,true,false,false);
                                newTask.Subject = t.Subject;
                                newTask.TaskSubType = t.TaskSubType;
                                newTask.Status = t.Status;
                                newTask.WhoId = newLead.Id;
                                newTask.OwnerId = UserId;
                                newTask.ActivityDate = t.ActivityDate;
                                newTask.Priority = t.Priority;
                                
                                taskInsertList.add(newTask);
                            }
                        }
                        
                        if(listOldEvents.size()>0){
                            
                            for(Event e:listOldEvents){
                                Event newEvent = e.clone(false,true,false,false);
                                newEvent.WhoId = newLead.Id;
                                newEvent.Subject = e.Subject;
                                newEvent.OwnerId = UserId;
                                newEvent.Description = e.Description;
                                newEvent.EventSubtype = e.EventSubtype;
                                newEvent.ShowAs = e.ShowAs;
                                newEvent.StartDateTime = e.StartDateTime;
                                newEvent.EndDateTime = e.EndDateTime;
                                newEvent.IsAllDayEvent = e.IsAllDayEvent;
                                newEvent.Location = e.Location;
                                eventInsertList.add(newEvent);
                            }
                        }
                        
                        if(eventInsertList.size()>0){
                            try{
                                //inserting the events for the new lead
                                insert eventInsertList;
                                system.debug('Successfully Inserted eventInsertlist');
                            }catch(DMLException e){
                                map_result.put('INSERTION_FAILED','Event Insertion Failed');
                                system.debug(e.getMessage());
                                return map_result;
                            }
                            
                        }
                        
                        if(taskInsertList.size()>0){
                            try{
                                //inserting the tasks for the new lead
                                insert taskInsertList;
                                system.debug('Successfully Inserted taskInsertList');
                            }catch(DMLException e){
                                map_result.put('INSERTION_FAILED','Task Insertion Failed');
                                system.debug(e.getMessage());
                                return map_result;
                            }
                        }
                    }
                else if(!sr.isSuccess()){
                    map_result.put('ERROR','Error Inserting new Lead');
                    
                        system.debug('Error is '+sr.getErrors());
                   	
                    return map_result;
                }
                    map_result.put('LeadId',newLead.Id);
                    
                    //return map_result;
                
            }
            else{
                map_result.put('INSERTION_FAILED','There is no lead record');
                //return map_result;
            }
            return map_result;
            
        } catch (Exception e) {
            system.debug('Unexpected Exception here '+e.getMessage());
            map_result.put('INSERTION_FAILED','Cannot Transfer due to an unexpected exception');
            return map_result;
        }
    }
    
    /**
     * @description Returns a list of child programs of Lead Sources
     * @Date 12 September 2025
     * @param LeadId String
     * @return Map<String,String>
     */
    
    @AuraEnabled
    public static Map<String,String> retrievePrograms(String LeadId){
        try {
            Map<String,String> map_programInfo = new Map<String,String>();
            List<Lead_Sources__c> list_programInfo  = [SELECT Program__c,Program__r.Name FROM Lead_Sources__c 
        WHERE Lead__c=:LeadId LIMIT 200];
            
            
            if(list_programInfo.size() > 0){
                for(Lead_Sources__c p : list_programInfo){
                    map_programInfo.put(p.Program__c,p.Program__r.Name);
                }
                return map_programInfo;
            }
            else{
                map_programInfo.put('EMPTY_LIST','No Records Found');
                return map_programInfo;
            }
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * @description Returns Internal User List
     * @Date 12 September 2025
     * @return Map<String,String>
     */
    @AuraEnabled
    public static Map<String,String> retrieveUserInfo(){
        try {
            Map<String,String> map_userInfo = new Map<String,String>();
            List<User> list_userInfo = [SELECT Id,Name FROM User WHERE Lead_Transfer__c =true LIMIT 50];
            
            if(list_userInfo.size() > 0){
                for(User u : list_userInfo){
                    map_userInfo.put(u.Id,u.Name);
                }
                return map_userInfo;
            }
            else{
                map_userInfo.put('EMPTY_LIST','No Records Found');
                return map_userInfo;
            }
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}