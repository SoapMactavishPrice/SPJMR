/**
 * Async handler for Metadata API deployments started from {@link PathConfigurationHubMetadataService}.
 * Completion is surfaced in Setup → Deployment Status; the hub UI shows the async job Id when queued.
 */
public class PathConfigurationHubDeployCallback implements Metadata.DeployCallback {
    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        // Intentionally minimal: admins use Deployment Status for details.
    }
}