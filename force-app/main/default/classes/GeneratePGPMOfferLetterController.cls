public with sharing class GeneratePGPMOfferLetterController {
    public String applicationNumber { get; private set; }
    public String applicantName { get; private set; }
    public String firstName { get; private set; }
    public String correspondenceAddressLine1 { get; private set; }
    public String correspondenceAddressLine2 { get; private set; }
    public String correspondenceAddressLine3 { get; private set; }
    public String correspondenceAddressLine4 { get; private set; }
    public String batchName { get; private set; }
    public String letterDate { get; private set; }
    public String offerDeadline { get; private set; }
    public String firstInstallmentDeadline { get; private set; }
    public String programmeStartDate { get; private set; }

    public GeneratePGPMOfferLetterController() {
        Id admissionDecisionId = ApexPages.currentPage()
            .getParameters()
            .get('admissionId');
        if (admissionDecisionId == null) {
            return;
        }

        List<Admission_Decision__c> decisions = [
            SELECT
                Id,
                Application__c,
                Application__r.Name,
                Application__r.Applicant__r.Name,
                Application__r.Batch__r.Name,
                Application__r.Batch__r.StartDate,
                Offer_Letter_Date__c,
                PaymentOfTheFirstInstallmentEta__c
            FROM Admission_Decision__c
            WHERE Id = :admissionDecisionId
            LIMIT 1
        ];
        if (decisions.isEmpty()) {
            return;
        }

        Admission_Decision__c decision = decisions[0];
        applicationNumber = decision.Application__r.Name;
        applicantName = decision.Application__r.Applicant__r == null
            ? null
            : decision.Application__r.Applicant__r.Name;
        batchName = decision.Application__r.Batch__r == null
            ? null
            : decision.Application__r.Batch__r.Name;

        if (decision.Offer_Letter_Date__c != null) {
            letterDate = formatDate(decision.Offer_Letter_Date__c, false, false);
            offerDeadline = formatDate(decision.Offer_Letter_Date__c, true, false);
        }
        firstInstallmentDeadline = formatDate(
            decision.PaymentOfTheFirstInstallmentEta__c,
            true,
            false
        );
        programmeStartDate = decision.Application__r.Batch__r == null
            ? null
            : formatDate(
                decision.Application__r.Batch__r.StartDate,
                true,
                true
            );

        loadPersonalDetails(decision.Application__c);
        if (String.isBlank(firstName)) {
            firstName = extractFirstName(applicantName);
        }
    }

    private void loadPersonalDetails(Id applicationId) {
        List<Personal_Detail__c> personalDetails = [
            SELECT
                First_Name__c,
                Corr_Address1__c,
                Corr_Address2__c,
                Corr_Country__r.Name,
                Corr_Ind_City__r.Name,
                Other_Corr_Ind_City__c,
                Corr_City__r.Name,
                Other_Corr_City__c,
                Corr_State__r.Name,
                Corr_Ind_Pincode__r.Name,
                Corr_Pincode__c
            FROM Personal_Detail__c
            WHERE Application__c = :applicationId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (personalDetails.isEmpty()) {
            return;
        }

        Personal_Detail__c personalDetail = personalDetails[0];
        firstName = clean(personalDetail.First_Name__c);
        correspondenceAddressLine1 = joinNonBlank(
            new List<String>{
                clean(personalDetail.Corr_Address1__c),
                clean(personalDetail.Corr_Address2__c)
            },
            ' '
        );

        String country = relatedName(personalDetail.Corr_Country__r);
        String townOrCity = resolveTownOrCity(personalDetail, country);
        String district = resolveDistrict(personalDetail, country);
        String state = relatedName(personalDetail.Corr_State__r);
        String pinCode = resolvePinCode(personalDetail, country);

        if (country == 'India') {
            correspondenceAddressLine2 = townOrCity;
            correspondenceAddressLine3 = appendPinCode(district, pinCode);
            correspondenceAddressLine4 = state;
        } else {
            correspondenceAddressLine2 = appendPinCode(townOrCity, pinCode);
            correspondenceAddressLine3 = joinUniqueNonBlank(
                new List<String>{ state, country },
                ', '
            );
        }
    }

    private static String resolveTownOrCity(
        Personal_Detail__c personalDetail,
        String country
    ) {
        if (country == 'India') {
            String indianCity = relatedName(personalDetail.Corr_Ind_City__r);
            return String.isBlank(indianCity) || indianCity == 'Other'
                ? clean(personalDetail.Other_Corr_Ind_City__c)
                : indianCity;
        }

        String internationalCity = relatedName(personalDetail.Corr_City__r);
        return String.isBlank(internationalCity) || internationalCity == 'Other'
            ? clean(personalDetail.Other_Corr_City__c)
            : internationalCity;
    }

    private static String resolveDistrict(
        Personal_Detail__c personalDetail,
        String country
    ) {
        if (country != 'India') {
            return null;
        }

        String district = relatedName(personalDetail.Corr_City__r);
        return district == 'Other'
            ? clean(personalDetail.Other_Corr_City__c)
            : district;
    }

    private static String resolvePinCode(
        Personal_Detail__c personalDetail,
        String country
    ) {
        String indianPinCode = relatedName(personalDetail.Corr_Ind_Pincode__r);
        if (
            country != 'India' ||
            String.isBlank(indianPinCode) ||
            indianPinCode == 'Other'
        ) {
            return clean(personalDetail.Corr_Pincode__c);
        }
        return indianPinCode;
    }

    private static String appendPinCode(String location, String pinCode) {
        if (String.isBlank(pinCode)) {
            return location;
        }
        return String.isBlank(location)
            ? pinCode
            : location + ' - ' + pinCode;
    }

    private static String relatedName(SObject relatedRecord) {
        return relatedRecord == null
            ? null
            : clean((String) relatedRecord.get('Name'));
    }

    private static String clean(String value) {
        return String.isBlank(value)
            ? null
            : value.replace('\r', ' ').replace('\n', ' ').trim();
    }

    private static String extractFirstName(String fullName) {
        String cleanedName = clean(fullName);
        return cleanedName == null ? null : cleanedName.split(' ')[0];
    }

    private static String joinNonBlank(
        List<String> values,
        String separator
    ) {
        List<String> populatedValues = new List<String>();
        for (String value : values) {
            if (!String.isBlank(value)) {
                populatedValues.add(value);
            }
        }
        return String.join(populatedValues, separator);
    }

    private static String joinUniqueNonBlank(
        List<String> values,
        String separator
    ) {
        List<String> uniqueValues = new List<String>();
        Set<String> normalizedValues = new Set<String>();
        for (String value : values) {
            if (String.isBlank(value)) {
                continue;
            }
            String normalizedValue = value.toLowerCase();
            if (normalizedValues.add(normalizedValue)) {
                uniqueValues.add(value);
            }
        }
        return String.join(uniqueValues, separator);
    }

    @TestVisible
    private static String formatDate(
        Date value,
        Boolean includeComma,
        Boolean includeWeekday
    ) {
        if (value == null) {
            return null;
        }
        DateTime dateTimeValue = DateTime.newInstance(
            value,
            Time.newInstance(12, 0, 0, 0)
        );
        String pattern = includeWeekday
            ? 'EEEE, MMMM d, yyyy'
            : (includeComma ? 'd MMMM, yyyy' : 'd MMMM yyyy');
        return dateTimeValue.format(pattern, 'GMT');
    }
}