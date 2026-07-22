import { LightningElement, wire } from 'lwc';
import getVFPageUrl from '@salesforce/apex/InterviewController.getVFPageUrl';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
export default class RenderApplicationView extends NavigationMixin(LightningElement) {
    bool_displayIFrame = false
    vfPageUrl = '';
    applicationId = '';
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            // Accessing a custom URL parameter named 'myUrlParameter'
            console.log('Params are ', JSON.stringify(currentPageReference.state))
            this.applicationId = currentPageReference.state.recordId
            this.getUrl()
        }
    }

    async getUrl() {
        if (this.applicationId) {
            await getVFPageUrl({ applicationId: this.applicationId }).then((result) => {
                if (result) {
                    this.vfPageUrl = result;
                    this.bool_displayIFrame = true
                }

        //         window.open(result, '_blank');

        //          this[NavigationMixin.Navigate]({
        //         type: 'standard__webPage',
        //         attributes: {
        //             url:result
        //         },
        // });

                console.log('Result is ', result)
            })
                .catch((error) => { console.log('Could not fetch URL ', JSON.stringify(error)) })

        }

    }
}