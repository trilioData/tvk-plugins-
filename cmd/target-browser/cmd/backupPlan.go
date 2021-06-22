package cmd

import (
	"github.com/spf13/cobra"
	_ "k8s.io/client-go/plugin/pkg/client/auth/gcp" // GCP auth lib for GKE

	targetBrowser "github.com/trilioData/tvk-plugins/tools/targetbrowser"
)

func init() {
	getCmd.AddCommand(backupPlanCmd())
}

func backupPlanCmd() *cobra.Command {
	var cmd = &cobra.Command{

		Use:     backupPlanCmdName,
		Aliases: []string{backupPlanCmdPluralName, backupPlanCmdAlias, backupPlanCmdAliasPlural},

		Short: shortUsage,
		Long:  longUsage,
		RunE:  getBackupPlanList,
	}

	cmd.Flags().IntVarP(&pageSize, PageSizeFlag, pageSizeShort, pageSizeDefault, pageSizeUsage)
	cmd.Flags().IntVarP(&page, pageFlag, pageShort, pageDefault, pageUsage)
	cmd.Flags().StringVarP(&ordering, OrderingFlag, orderingShort, orderingDefault, orderingUsage)
	cmd.Flags().StringVarP(&tvkInstanceUID, TvkInstanceUIDFlag, tvkInstanceUIDShort, tvkInstanceUIDDefault, tvkInstanceUIDUsage)
	return cmd
}

func getBackupPlanList(*cobra.Command, []string) error {

	bpOptions := targetBrowser.BackupPlanListOptions{
		Page:           page,
		PageSize:       pageSize,
		Ordering:       ordering,
		TvkInstanceUID: tvkInstanceUID,
	}
	err := targetBrowser.NewClient(APIKey).GetBackupPlans(&bpOptions)
	if err != nil {
		return err
	}
	return nil
}