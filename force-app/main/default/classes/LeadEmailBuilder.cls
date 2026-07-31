/**
 * @description LeadEmailBuilder Class takes in the set of programmes and creates an email body to be sent
 * to the concerned lead for the applicant conversion email.
 * 
 */
public without sharing class LeadEmailBuilder {

    /**
 * @description Wrapper used to pass email generation parameters.
 */
    public class EmailBuilderWrapper{
        public List<String> programs;
        public String username;
        public Lead l;
        public String communityUrl;
    }
/**
 * @description Creates formatted programme text
 * @param programs, contains set of programmes
 * @return String of programme text 
 */
    private static String formatPrograms(List<String> programs) {
        if (programs == null || programs.isEmpty()){
            return '';
        } 
        if (programs.size() == 1) {
            return programs[0];
        }

        if (programs.size() == 2) {
            return programs[0] + ' and ' + programs[1];
        }

        String result = '';
        for (Integer i = 0; i < programs.size(); i++) {
            if (i == programs.size() - 1) {
                result += 'and ' + programs[i];
            } else {
                result += programs[i] + ', ';
            }
        }
        return result + ' programmes' ;
    }

    // private static Boolean isGMP(String program) {
    //     return program != null && program.toUpperCase().contains('GMP');
    // }

    // public static List<String> getGmpPrograms(List<String> programs) {
    //     List<String> gmp = new List<String>();
    //     if (programs == null) return gmp;

    //     for (String p : programs) {
    //         if (isGMP(p)) gmp.add(p);
    //     }
    //     return gmp;
    // }

    // public static List<String> getNonGmpPrograms(List<String> programs) {
    //     List<String> other = new List<String>();
    //     if (programs == null) return other;

    //     for (String p : programs) {
    //         if (!isGMP(p)) other.add(p);
    //     }
    //     return other;
    // }


/**
 * @description Creates verification email body for a lead without a user account.
 * @param wrapper Contains lead, programs and community URL.
 * @return HTML email body.
 */
    public static String buildNormalEmail(LeadEmailBuilder.EmailBuilderWrapper wrapper) {
        List<String> programs = wrapper.programs;
        Lead l = wrapper.l;
        String communityUrl = wrapper.communityUrl;
        String programText = formatPrograms(programs);

        return
        '<table border="0" style="width: 100%; text-align: center; border-collapse: collapse;">' +
            '<tr>' +
                    '<td style="width: 50%; text-align: center; padding: 10px;">' +
                    '<img src="https://platform-energy-10.file.force.com/sfc/dist/version/download/?oid=00DdN00000UKZDF&ids=068OS00000HhGpW&d=%2Fa%2FOS000004pTP4%2FHGj69FkH73m3IykmWhrnPeOUC1sVTbBGMN1KV9Z0RHI&asPdf=false" style="width:20%; max-width:180px; height:auto; display:block; margin:0 auto;"/>' +
                '</td>' +
            '</tr>' +
        '</table>' +

        '<p>Dear ' + (l.FirstName != null ? l.FirstName : 'Applicant') + ' ' + (l.LastName != null ? l.LastName : '') + ',</p>' +

        '<p>Thank you for expressing your interest in the<b> ' + programText + ' </b>at S.P. Jain Institute of Management and Research (SPJIMR).' +
        '<p>To proceed, please verify your email address by clicking the button below. </p>'+

        '<div style="text-align:center; margin:20px 0;">' +
            '<a href="' + communityUrl + '/VerifyLead?leadId=' + l.Id + '" target="_blank"' +
            ' style="display:inline-block;background-color:#fbbc04;color:#000000;font-size:16px;font-weight:bold;padding:12px 24px;text-decoration:none;border-radius:6px;">' +
            'Verify Email</a>' +
        '</div>' +

        '<div style="text-align:center;">' +
            '<p style="color:#C3C3C3;">Warm Regards</p>' +
            '<p style="color:#C3C3C3;">Admissions Team</p>' +
            '<p style="color:#C3C3C3;">S.P. Jain Institute of Management and Research (SPJIMR)</p>' +
        '</div>';
    }

    
/**
 * @description Creates verification email body for a lead with a user account.
 * @param wrapper Contains lead, programs and community URL.
 * @return HTML email body.
 */
    public static String buildNormalEmailWithUser(LeadEmailBuilder.EmailBuilderWrapper wrapper) {
        List<String> programs = wrapper.programs;
        Lead l = wrapper.l;
        String username = wrapper.username;
        String communityUrl = wrapper.communityUrl;
        String programText = formatPrograms(programs);

        return
        '<table border="0" style="width: 100%; text-align: center; border-collapse: collapse;">' +
            '<tr>' +
                    '<td style="width: 50%; text-align: center; padding: 10px;">' +
                    '<img src="https://platform-energy-10.file.force.com/sfc/dist/version/download/?oid=00DdN00000UKZDF&ids=068OS00000HhGpW&d=%2Fa%2FOS000004pTP4%2FHGj69FkH73m3IykmWhrnPeOUC1sVTbBGMN1KV9Z0RHI&asPdf=false" style="width:20%; max-width:180px; height:auto; display:block; margin:0 auto;"/>' +
                '</td>' +
            '</tr>' +
        '</table>'
        +
        '<p>Dear ' + l.FirstName + ',</p>' +

        '<p>Thank you for expressing your interest in the ' +'<b>' + programText + '</b> at S.P. Jain Institute of Management and Research (SPJIMR).' +
        '<p>To proceed, please sign in to the application Portal. </p>'+
        '<p>Username: <b>' + username + '</b></p>' +
        '<p><a href="' + communityUrl + '/applicationportal">Go to Portal</a></p>' +

        '<div style="text-align:center;">' +
            '<p style="color:#C3C3C3;">Warm regards</p>' +
            '<p style="color:#C3C3C3;">Admissions Team</p>' +
            '<p style="color:#C3C3C3;">S.P. Jain Institute of Management and Research (SPJIMR)</p>' +
        '</div>';
    }

    // public static String buildGmpEmail(Lead l, List<String> programs, String communityUrl) {

    //     String programText = formatPrograms(programs);

    //     return
    //     '<table border="0" style="width: 100%; text-align: center; border-collapse: collapse;">' +
    //         '<tr>' +
    //             '<td style="width: 33%; padding: 10px;">' +
    //                 '<img src="https://platform-energy-10--devorg.sandbox.my.salesforce.com/sfc/dist/version/renditionDownload?rendition=ORIGINAL_Jpg&versionId=068C1000005irU3&operationContext=DELIVERY&contentId=05TC1000008JaCs&page=0&d=/a/C1000000c9AM/m_L_.eZoqBooGzE7DtpR6D9CUyM4REbz4xEDcyisJvY&oid=00DC1000002cd5h&dpt=null&viewId=" style="width:80%;"/>' +
    //             '</td>' +
    //             '<td style="width: 33%; padding: 10px;">' +
    //                 '<img src="https://platform-energy-10--devorg.sandbox.my.salesforce.com/sfc/dist/version/renditionDownload?rendition=ORIGINAL_Jpg&versionId=068C1000005X0ny&operationContext=DELIVERY&contentId=05TC10000084zbV&page=0&d=/a/C1000000Z0TN/MXNLPswwCL7F00p_VL8acCEke_h20soLWvCxA2312zM&oid=00DC1000002cd5h&dpt=null&viewId=" style="width:80%;"/>' +
    //             '</td>' +
    //         '</tr>' +
    //     '</table>' +

    //     '<p>Dear ' + (l.FirstName != null ? l.FirstName : 'Applicant') + ' ' + (l.LastName != null ? l.LastName : '') + ',</p>' +

    //     '<p>Thank you for applying to GMP at SPJIMR.</p>' +

    //     '<p><b>Your have applied for</b> ' + programText + '</p>' +

    //     '<div style="text-align:center; margin:20px 0;">' +
    //         '<a href="' + communityUrl + '/VerifyLead?leadId=' + l.Id + '" target="_blank"' +
    //         ' style="display:inline-block;background-color:#fbbc04;color:#000000;font-size:16px;font-weight:bold;padding:12px 24px;text-decoration:none;border-radius:6px;">' +
    //         'Verify Email</a>' +
    //     '</div>' +

    //     '<div style="text-align:center;">' +
    //         '<p style="color:#C3C3C3;">Thanks</p>' +
    //         '<p style="color:#C3C3C3;">Admissions Office</p>' +
    //         '<p style="color:#C3C3C3;">SPJIMR</p>' +
    //     '</div>';
    // }

    // public static String buildGmpEmailWithUser(Lead l, String username, String communityUrl, List<String> programs) {

    //     String programText = formatPrograms(programs);

    //     return
    //     '<table border="0" style="width: 100%; text-align: center; border-collapse: collapse;">' +
    //         '<tr>' +
    //             '<td style="width: 33%; padding: 10px;">' +
    //                 '<img src="https://platform-energy-10--devorg.sandbox.my.salesforce.com/sfc/dist/version/renditionDownload?rendition=ORIGINAL_Jpg&versionId=068C1000005irU3&operationContext=DELIVERY&contentId=05TC1000008JaCs&page=0&d=/a/C1000000c9AM/m_L_.eZoqBooGzE7DtpR6D9CUyM4REbz4xEDcyisJvY&oid=00DC1000002cd5h&dpt=null&viewId=" style="width:80%;"/>' +
    //             '</td>' +
    //             '<td style="width: 33%; padding: 10px;">' +
    //                 '<img src="https://platform-energy-10--devorg.sandbox.my.salesforce.com/sfc/dist/version/renditionDownload?rendition=ORIGINAL_Jpg&versionId=068C1000005X0ny&operationContext=DELIVERY&contentId=05TC10000084zbV&page=0&d=/a/C1000000Z0TN/MXNLPswwCL7F00p_VL8acCEke_h20soLWvCxA2312zM&oid=00DC1000002cd5h&dpt=null&viewId=" style="width:80%;"/>' +
    //             '</td>' +
    //         '</tr>' +
    //     '</table>' +
    //     '<p>Dear ' + l.FirstName + ',</p>' +

    //     '<p>Thank you for applying to GMP at SPJIMR.</p>' +

    //     '<p><b>Your have applied for</b> ' + programText + '</p>' +

    //     '<p>Username: <b>' + username + '</b></p>' +

    //     '<p><a href="' + communityUrl + '/applicationportal">Go to Portal</a></p>' +

    //     '<div style="text-align:center;">' +
    //         '<p style="color:#C3C3C3;">Thanks</p>' +
    //         '<p style="color:#C3C3C3;">Admissions Office</p>' +
    //         '<p style="color:#C3C3C3;">SPJIMR</p>' +
    //     '</div>';
    // }
}