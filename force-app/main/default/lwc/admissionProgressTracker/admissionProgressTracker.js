import { LightningElement,track,api } from 'lwc';

export default class AdmissionProgressTracker extends LightningElement {
@track currentStep = '1'
applicationId = 'a000o0000000000p';
@track isCurrentStep1=true
@track isCurrentStep2=false
@track isCurrentStep3=false
@track isCurrentStep4=false
@track isCurrentStep5=false
@track isCurrentStep6=false
@track isCurrentStep7=false
@track isCurrentStep8=false
@track isCurrentStep9=false


updateCurrentStep(){
    this.isCurrentStep1 = this.currentStep === '1';
    this.isCurrentStep2 = this.currentStep === '2';
    this.isCurrentStep3 = this.currentStep === '3';
    this.isCurrentStep4 = this.currentStep === '4';
    this.isCurrentStep5 = this.currentStep === '5';
    this.isCurrentStep6 = this.currentStep === '6';
    this.isCurrentStep7 = this.currentStep === '7';
    this.isCurrentStep8 = this.currentStep === '8';
    this.isCurrentStep9 = this.currentStep === '9';
}
handleClick(event){
    

}

handleSubmitChild(event){
    console.log(event.detail+' is the step')
    this.currentStep = String(Number(this.currentStep)+1)
    this.updateCurrentStep()
}
handleStepClick(event){
    const step = event.target.value;
    if(Number(step)== Number(this.currentStep)+1 || Number(step)== Number(this.currentStep)+1){
        this.currentStep = step;
    }
}
}