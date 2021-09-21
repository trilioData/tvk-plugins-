package cmd

import (
	"fmt"
	"strings"

	"github.com/trilioData/tvk-plugins/internal"
)

const (
	KubeConfigFlag  = "kubeconfig"
	kubeConfigUsage = "Path to the kubeconfig file to use for CLI requests"

	InsecureSkipTLSFlag  = "insecure-skip-tls-verify"
	insecureSkipTLSUsage = "If true, the server's certificate will not be checked for validity. This will make your HTTPS connections insecure"

	UseHTTPS      = "use-https"
	useHTTPSUsage = "use https scheme for client connection"

	CertificateAuthorityFlag  = "certificate-authority"
	certificateAuthorityUsage = "Path to a cert file for the certificate authority"

	OutputFormatFlag      = "output"
	OutputFormatFlagShort = "o"

	TargetNameFlag  = "target-name"
	targetNameUsage = "Name of target CR to be used to query mounted target"

	TargetNamespaceFlag      = "target-namespace"
	targetNamespaceDefault   = "default"
	targetNamespaceUsage     = "Namespace of specified target CR to be used to query mounted target"
	BackupPlanCmdName        = "backupplan"
	backupPlanCmdPluralName  = BackupPlanCmdName + "s"
	backupPlanCmdAlias       = "backupPlan"
	backupPlanCmdAliasPlural = backupPlanCmdAlias + "s"
	BackupCmdName            = "backup"
	backupCmdPluralName      = BackupCmdName + "s"
	MetadataCmdName          = "metadata"
	ResourceMetadataCmdName  = "resource-metadata"
	TrilioResourcesCmdName   = "trilio-resources"

	pagesFlag    = "pages"
	pagesDefault = 1
	pagesUsage   = "Number of Pages to display within the paginated result set"

	PageSizeFlag    = "page-size"
	PageSizeDefault = 10
	pageSizeUsage   = "Maximum number of results in a single page"

	OrderByFlag    = "order-by"
	orderByDefault = "name"
	orderByUsage   = "Parameter to use for ordering the paginated result set"

	TvkInstanceUIDFlag  = "tvk-instance-uid"
	tvkInstanceUIDUsage = "TVK instance id to filter backup/backupPlan"

	BackupPlanUIDFlag    = "backup-plan-uid"
	backupPlanUIDDefault = ""
	backupPlanUIDUsage   = "backupPlanUID to get all backup related to UID"

	BackupStatusFlag    = "backup-status"
	backupStatusDefault = ""
	backupStatusUsage   = "Status of Backup to filter for [Success, InProgress, Failed]"

	BackupUIDFlag    = "backup-uid"
	backupUIDDefault = ""
	backupUIDUsage   = "backupUID to get all backup related to UID"

	OperationScopeFlag  = "operation-scope"
	operationScopeUsage = "Filter backup/backupPlan for [SingleNamespace, MultiNamespace]. " +
		"Supported values can be in any case capital, small or mixed."

	GroupFlag      = "group"
	GroupFlagShort = "g"
	groupDefault   = ""
	groupUsage     = "API group name of resource whose resource-metadata needs to be retrieved"

	VersionFlag      = "version"
	VersionFlagShort = "v"
	versionDefault   = ""
	versionUsage     = "API version of resource whose resource-metadata needs to be retrieved"

	KindFlag      = "kind"
	KindFlagShort = "k"
	kindDefault   = ""
	kindUsage     = "API resource Kind of backed up resource whose resource-metadata needs to be retrieved"

	NameFlag    = "name"
	nameDefault = ""
	nameUsage   = "name of backed up resource whose resource-metadata needs to be retrieved"

	kindsFlag  = "kinds"
	kindsUsage = "List of kinds of trilio resources. Available kinds: ClusterBackup, ClusterBackupPlan," +
		" Backup, BackupPlan, Target, Secret, Policy, Hook"

	supportedTSFormat = "Supported format can be yyyy-mm-dd or yyyy-mm-ddThh:mm:ssZ, yyyy/mm/dd, dd/mm/yyy," +
		" mm/dd/yy, yyyy-mm-dd hh:mm:ss, yyyymmdd, yyyy-mm-ddThh"
	CreationStartTimeFlag  = "creation-start-time"
	creationStartTimeUsage = "Any valid date or timestamp to filter backup/backupPlans on creationTimestamp from. " + supportedTSFormat
	CreationEndTimeFlag    = "creation-end-time"
	creationEndTimeUsage   = "Any valid date or timestamp to filter backup/backupPlans on creationTimestamp to." + supportedTSFormat

	ExpirationStarTimeFlag   = "expiration-start-time"
	expirationStartTimeUsage = "Any valid  date or timestamp to filter backups on expirationTimestamp from." + supportedTSFormat
	ExpirationEndTimeFlag    = "expiration-end-time"
	expirationEndTimeUsage   = "Any valid date or timestamp to filter backups on expirationTimestamp to." + supportedTSFormat
)

var (
	group   string
	version string
	kind    string
	name    string

	tvkInstanceUID                         string
	backupPlanUID                          string
	backupStatus                           string
	backupUID                              string
	orderBy                                string
	pages, pageSize                        int
	creationStartTime, creationEndTime     string
	expirationStartTime, expirationEndTime string
	operationScope                         string

	kinds []string
)

var (
	OutputFormatFlagUsage = fmt.Sprintf("Output format to use. Supported formats: %s.",
		strings.Join(internal.AllowedOutputFormats.List(), "|"))
)
