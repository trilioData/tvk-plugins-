package cmd

import (
	"github.com/spf13/cobra"

	targetBrowser "github.com/trilioData/tvk-plugins/tools/target-browser"
)

func init() {
	getCmd.AddCommand(backupPlanCmd())
}

// nolint:lll // ignore long line lint errors
// backupPlanCmd represents the backupPlan command
func backupPlanCmd() *cobra.Command {
	var cmd = &cobra.Command{
		Use:     BackupPlanCmdName,
		Aliases: []string{backupPlanCmdPluralName, backupPlanCmdAlias, backupPlanCmdAliasPlural},
		Short:   "Get specific BackupPlan or list of BackupPlans",
		Long: `Performs GET operation on target-browser's '/backupplan' API and gets specific BackupPlan or list of BackupPlans from mounted target location
using available flags and options.`,
		Example: `  # List of backupPlans	
  kubectl tvk-target-browser get backupPlan --target-name <name> --target-namespace <namespace>

  # Get specific backupPlan
  kubectl tvk-target-browser get backupPlan <backup-plan-uid> --target-name <name> --target-namespace <namespace>

  # List of backupPlans: order by [name]
  kubectl tvk-target-browser get backupPlan --order-by name --target-name <name> --target-namespace <namespace>

  # List of backupPlans: order by [backupPlanTimestamp] in [ascending] order
  kubectl tvk-target-browser get backupPlan --order-by backupPlanTimestamp --target-name <name> --target-namespace <namespace>

  # List of backupPlans: order by [backupPlanTimestamp] in [descending] order
  kubectl tvk-target-browser get backupPlan --order-by -backupPlanTimestamp --target-name <name> --target-namespace <namespace>
  
  # List of backupPlans: filter by [tvkInstanceUID]
  kubectl tvk-target-browser get backupPlan --tvk-instance-uid <uid> --target-name <name> --target-namespace <namespace>
 
  # List of backupPlans in Single Namespace: filter by [operationScope]
  kubectl tvk-target-browser get backupPlan --operation-scope SingleNamespace --target-name <name> --target-namespace <namespace>

  # List of backupPlans in Multi Namespace/Cluster Scope: filter by [operationScope]
  kubectl tvk-target-browser get backupPlan --operation-scope MultiNamespace --target-name <name> --target-namespace <namespace>

  # List of backupPlans: filter by [creationStartTime] and [creationEndTime]
  kubectl tvk-target-browser get backupPlan --creation-start-time <creation-start-time> --creation-end-time <creation-end-time>--target-name <name> --target-namespace <namespace>
`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return getBackupPlanList(args)
		},
	}

	return cmd
}

func getBackupPlanList(args []string) error {
	if len(args) > 1 {
		args = removeDuplicates(args)
	}

	bpOptions := targetBrowser.BackupPlanListOptions{
		CommonListOptions: commonOptions,
	}
	return targetBrowserAuthConfig.GetBackupPlans(&bpOptions, args)
}
