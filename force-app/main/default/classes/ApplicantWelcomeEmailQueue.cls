/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ApplicantWelcomeEmailQueue
 * Author          : Navaneeth S
 * Created Date    : Jul 21, 2026
 * Last Modified By: Navaneeth S
 * Last Modified On: Jul 21, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 21, 2026  │ Navaneeth S   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class ApplicantWelcomeEmailQueue{
	

    

    public static String formatProgrammeList(List<String> programmes) {

        if (programmes == null || programmes.isEmpty()) {
            return '';
        }

        if (programmes.size() == 1) {
            return programmes[0];
        }

        if (programmes.size() == 2) {
            return programmes[0] + ' and ' + programmes[1];
        }

        String result = '';

        for (Integer i = 0; i < programmes.size() - 1; i++) {
            result += programmes[i] + ', ';
        }

        result += 'and ' + programmes[programmes.size() - 1];

        return result;
    }
}