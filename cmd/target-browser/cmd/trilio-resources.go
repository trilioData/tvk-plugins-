package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	targetBrowser "github.com/trilioData/tvk-plugins/tools/target-browser"
)

func init() {
	backupCmd.AddCommand(trilioResourcesCmd())
}

// nolint:lll // ignore long line lint errors
// trilioResourcesCmd represents the trilio-resources command (sub-command for backup)
func trilioResourcesCmd() *cobra.Command {
	var cmd = &cobra.Command{
		Use:   TrilioResourcesCmdName,
		Short: "Get trilio resources for specific backup",
		Long:  `Performs GET operation on target-browser's '/backup/{backupUID}/trilio-resources' API and gets trilio resources for backup`,
		Example: `  # Get trilio resources for specific backup
  kubectl tvk-target-browser get backup trilio-resources <backup-uid> --backup-plan-uid <uid> --kinds ClusterBackupPlan,Backup,Hook --target-name <name> --target-namespace <namespace>`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return getTrilioResources(args)
		},
	}

	cmd.Flags().StringSliceVar(&kinds, kindsFlag, []string{}, kindsUsage)

	cmd.Flags().StringVar(&backupPlanUID, BackupPlanUIDFlag, backupPlanUIDDefault, backupPlanUIDUsage)

	return cmd
}

func getTrilioResources(args []string) error {

	if len(args) == 0 {
		return fmt.Errorf("at-least 1 backupUID is needed")
	}

	args = removeDuplicates(args)

	trilioResourcesOptions := targetBrowser.TrilioResourcesListOptions{
		BackupPlanUID:     backupPlanUID,
		BackupUID:         backupUID,
		Kinds:             kinds,
		CommonListOptions: commonOptions,
	}

	return targetBrowserAuthConfig.GetTrilioResources(&trilioResourcesOptions, args)
}
