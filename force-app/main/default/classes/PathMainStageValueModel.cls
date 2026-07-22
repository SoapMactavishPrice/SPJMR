/**
 * One allowed main path stage (path picklist API value) per program from {@link Path_Main_Stage_Value__mdt}.
 * When at least one row matches the lead's program codes, the path bar shows only those stages in sort order.
 */
public with sharing class PathMainStageValueModel {
    public String programCode { get; set; }
    public String pathStageValueApi { get; set; }
    public String label { get; set; }
    public Decimal sortOrder { get; set; }

    /**
     * Ordered API values and optional display labels for the path bar after merging rows for program codes.
     */
    public class ProgramScopedMainStages {
        public List<String> orderedApis { get; set; }
        public Map<String, String> labelOverrideByApi { get; set; }

        public ProgramScopedMainStages() {
            orderedApis = new List<String>();
            labelOverrideByApi = new Map<String, String>();
        }

        public Boolean hasWhitelist() {
            return orderedApis != null && !orderedApis.isEmpty();
        }
    }

    /**
     * Builds a model from custom metadata.
     *
     * @param row CMDT row.
     * @return Model or null.
     */
    public static PathMainStageValueModel fromCmdt(Path_Main_Stage_Value__mdt row) {
        PathMainStageValueModel result = null;
        if (row != null) {
            result = new PathMainStageValueModel();
            result.programCode = row.Program_Code__c;
            result.pathStageValueApi = row.Path_Stage_Value_API__c;
            result.label = row.Label__c;
            result.sortOrder = row.Sort_Order__c;
        }
        return result;
    }

    /**
     * Merges active main-stage rows for the given program codes: union of stages, ordered by lowest sort order per stage.
     *
     * @param programCodesNormalized Lowercased program codes from related programs.
     * @param allRows Loaded CMDT models for the path config.
     * @return Ordered APIs and label overrides (when row supplies Label__c for the winning row per stage).
     */
    public static ProgramScopedMainStages resolveForPrograms(
        Set<String> programCodesNormalized,
        List<PathMainStageValueModel> allRows
    ) {
        ProgramScopedMainStages out = new ProgramScopedMainStages();
        if (programCodesNormalized == null || programCodesNormalized.isEmpty() || allRows == null || allRows.isEmpty()) {
            return out;
        }
        Map<String, Decimal> bestSortByStage = new Map<String, Decimal>();
        Map<String, String> winningLabelByStage = new Map<String, String>();
        for (PathMainStageValueModel m : allRows) {
            String pc = normalizeProgramCode(m.programCode);
            if (!programCodesNormalized.contains(pc)) {
                continue;
            }
            String stageApi = m.pathStageValueApi != null ? m.pathStageValueApi.trim() : '';
            if (String.isBlank(stageApi)) {
                continue;
            }
            Decimal sk = m.sortOrder != null ? m.sortOrder : Decimal.valueOf(999999);
            if (!bestSortByStage.containsKey(stageApi) || sk < bestSortByStage.get(stageApi)) {
                bestSortByStage.put(stageApi, sk);
                if (String.isNotBlank(m.label)) {
                    winningLabelByStage.put(stageApi, m.label.trim());
                } else {
                    winningLabelByStage.remove(stageApi);
                }
            }
        }
        if (bestSortByStage.isEmpty()) {
            return out;
        }
        List<MainStageSortWrapper> wrappers = new List<MainStageSortWrapper>();
        for (String api : bestSortByStage.keySet()) {
            wrappers.add(new MainStageSortWrapper(api, bestSortByStage.get(api)));
        }
        wrappers.sort();
        for (MainStageSortWrapper w : wrappers) {
            out.orderedApis.add(w.api);
        }
        for (String api : winningLabelByStage.keySet()) {
            out.labelOverrideByApi.put(api, winningLabelByStage.get(api));
        }
        return out;
    }

    private static String normalizeProgramCode(String raw) {
        String result = '';
        if (String.isNotBlank(raw)) {
            result = raw.trim().toLowerCase();
        }
        return result;
    }

    private class MainStageSortWrapper implements Comparable {
        String api;
        Decimal sortKey;
        MainStageSortWrapper(String a, Decimal s) {
            api = a;
            sortKey = s;
        }
        public Integer compareTo(Object other) {
            MainStageSortWrapper o = (MainStageSortWrapper) other;
            if (sortKey < o.sortKey) {
                return -1;
            }
            if (sortKey > o.sortKey) {
                return 1;
            }
            return api.compareTo(o.api);
        }
    }
}