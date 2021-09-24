package cmd

import (
	"fmt"
	"time"

	"github.com/spf13/cobra"
	targetBrowser "github.com/trilioData/tvk-plugins/tools/target-browser"
)

// nolint:lll // ignore long line lint errors
var backupCmd = &cobra.Command{
	Use:     BackupCmdName,
	Aliases: []string{backupCmdPluralName},
	Short:   "Get specific Backup or list of Backups",
	Long: `Performs GET operation on target-browser's '/backup' API and gets specific Backup or list of Backups from mounted target location
for specific backupPlan using available flags and options.`,
	Example: `  # List of backups for specific backupPlan
  kubectl tvk-target-browser get backup --backup-plan-uid <uid> --target-name <name> --target-namespace <namespace>

  # List of backups
  kubectl tvk-target-browser get backup --target-name <name> --target-namespace <namespace>
  
  # Get specific backup
  kubectl tvk-target-browser get backup <backup-uid> --target-name <name> --target-namespace <namespace>

  # List of backups: order by [name]
  kubectl tvk-target-browser get backup --backup-plan-uid <uid> --order-by name --target-name <name> --target-namespace <namespace>

  # List of backups: order by [backupTimestamp] in [ascending] order
  kubectl tvk-target-browser get backup --backup-plan-uid <uid> --order-by backupTimestamp --target-name <name> --target-namespace <namespace>

  # List of backups: order by [backupTimestamp] in [descending] order
  kubectl tvk-target-browser get backup --backup-plan-uid <uid> --order-by -backupTimestamp --target-name <name> --target-namespace <namespace>

  # List of backups: filter by [backup-status]
  kubectl tvk-target-browser get backup --backup-plan-uid <uid> --backup-status Available --target-name <name> --target-namespace <namespace>

  # List of backups in Single Namespace: filter by [operationScope]
  kubectl tvk-target-browser get backup --operation-scope SingleNamespace --target-name <name> --target-namespace <namespace>

  # List of backups in Multi Namespace/Cluster Scope: filter by [operationScope]
  kubectl tvk-target-browser get backup --operation-scope MultiNamespace --target-name <name> --target-namespace <namespace>

  # List of backups: filter by [tvkInstanceUID]
  kubectl tvk-target-browser get backup --tvk-instance-uid <uid> --target-name <name> --target-namespace <namespace>

  # List of backups: filter by [expirationStartTime] and [expirationEndTime]
  kubectl tvk-target-browser get backup --expiration-start-time <expiration-start-time> --expiration-end-time <expiration-end-time>--target-name <name> --target-namespace <namespace>

  # List of backups: filter by [creationStartTime] and [creationEndTime]
  kubectl tvk-target-browser get backup --creation-start-time <creation-start-time> --creation-end-time <creation-end-time>--target-name <name> --target-namespace <namespace>
`,

	RunE: func(cmd *cobra.Command, args []string) error {
		if (cmd.Flags().Changed(ExpirationStarTimeFlag) || cmd.Flags().Changed(ExpirationEndTimeFlag)) && expirationEndTime == "" {
			return fmt.Errorf("[%s] flag value cannot be empty", ExpirationEndTimeFlag)
		}
		var ts *time.Time
		var err error
		if expirationEndTime != "" {
			ts, err = parseTimestamp(expirationEndTime)
			if err != nil {
				return fmt.Errorf("[%s] flag invalid value. Usage - %s", ExpirationEndTimeFlag, expirationEndTimeUsage)
			}
			expirationEndTime = ts.Format(time.RFC3339)
		}

		if expirationStartTime != "" {
			ts, err = parseTimestamp(expirationStartTime)
			if err != nil {
				return fmt.Errorf("[%s] flag invalid value. Usage - %s", ExpirationStarTimeFlag, expirationStartTimeUsage)
			}
			expirationStartTime = ts.Format(time.RFC3339)
		}

		if cmd.Flags().Changed(ExpirationEndTimeFlag) && expirationStartTime == "" {
			expirationStartTime = time.Now().Format(time.RFC3339)
		}
		return getBackupList(args)
	},
}

func init() {
	backupCmd.Flags().StringVar(&backupPlanUID, BackupPlanUIDFlag, backupPlanUIDDefault, backupPlanUIDUsage)
	backupCmd.Flags().StringVar(&backupStatus, BackupStatusFlag, backupStatusDefault, backupStatusUsage)
	backupCmd.Flags().StringVar(&backupUID, BackupUIDFlag, backupUIDDefault, backupUIDUsage)
	backupCmd.Flags().StringVar(&expirationStartTime, ExpirationStarTimeFlag, "", expirationStartTimeUsage)
	backupCmd.Flags().StringVar(&expirationEndTime, ExpirationEndTimeFlag, "", expirationEndTimeUsage)
	getCmd.AddCommand(backupCmd)
}

func getBackupList(args []string) error {

	if len(args) > 1 {
		args = removeDuplicates(args)
	}

	bpOptions := targetBrowser.BackupListOptions{
		BackupPlanUID:            backupPlanUID,
		BackupStatus:             backupStatus,
		CommonListOptions:        commonOptions,
		ExpirationStartTimestamp: expirationStartTime,
		ExpirationEndTimestamp:   expirationEndTime,
	}
	return targetBrowserAuthConfig.GetBackups(&bpOptions, args)
}
