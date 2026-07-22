public class LeadEmailFlowInvoke {
    
    public static void runFlow(String LeadId){
        Map<String,Object> flowInputs = new Map<String,Object>();
        flowInputs.put('LeadId',LeadId);
        
        Flow.Interview.LeadEmail_Flow instance = new  Flow.Interview.LeadEmail_Flow(flowInputs);
        instance.start();
        
        String s = (String)instance.getVariableValue('output');
        system.debug(s);

    }

}