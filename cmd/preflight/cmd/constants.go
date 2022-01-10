package cmd

const (
	preflightCmdName    = "preflight"
	preflightRunCmdName = "run"
	cleanupCmdName      = "cleanup"

	kubeconfigFlag          = "kubeconfig"
	kubeconfigShorthandFlag = "k"
	kubeconfigUsage         = "Path to kubeconfig file to use for CLI requests"

	namespaceFlag          = "namespace"
	namespaceFlagShorthand = "n"
	namespaceUsage         = "Namespace of the cluster in which the preflight checks will be performed"

	logLevelFlag          = "log-level"
	logLevelFlagShorthand = "l"
	logLevelUsage         = "Set the logging level for the for preflight or cleanup in the level of" +
		" PANIC, FATAL, ERROR, WARN, INFO, DEBUG TRACE"
	defaultLogLevel = "INFO"

	storageClassFlag  = "storage-class"
	storageClassUsage = "Name of storage class to use for preflight checks"

	snapshotClassFlag  = "volume-snapshot-class"
	snapshotClassUsage = "Name of volume snapshot class to use for preflight checks"

	localRegistryFlag  = "local-registry"
	localRegistryUsage = "Name of the local registry from where the images will be pulled"

	imagePullSecFlag  = "image-pull-secret"
	imagePullSecUsage = "Name of the secret for authentication while pulling the images from the local registry"

	serviceAccountFlag  = "service-account"
	serviceAccountUsage = "Name of the service account to use for preflight checks and creating preflight resources"

	cleanupOnFailureFlag  = "cleanup-on-failure"
	cleanupOnFailureUsage = "Cleanup the resources on cluster if preflight checks fail. By-default it is false"

	uidFlag  = "uid"
	uidUsage = "UID of the preflight check whose resources must be cleaned"

	preflightLogFilePrefix = "preflight"
	cleanupLogFilePrefix   = "preflight_cleanup"
)

var (
	kubeconfig       string
	namespace        string
	logLevel         string
	storageClass     string
	snapshotClass    string
	localRegistry    string
	imagePullSecret  string
	serviceAccount   string
	cleanupOnFailure bool

	cleanupUID string
)
