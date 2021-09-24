package cmd

import (
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"

	targetBrowser "github.com/trilioData/tvk-plugins/tools/target-browser"
)

func init() {
	getCmd.AddCommand(metadataCmd())
}

// metadataCmd represents the metadata command
func metadataCmd() *cobra.Command {
	var cmd = &cobra.Command{
		Use:   MetadataCmdName,
		Short: "Get Backup high level metadata details",
		Long:  `Performs GET operation on target-browser's '/metadata' API and gets Backup high level metadata details`,
		Example: `  # Get metadata details of specific backup
  kubectl tvk-target-browser get metadata --backup-uid <uid> --backup-plan-uid <uid> --target-name <name> --target-namespace <namespace>
`,
		RunE: getMetadata,
	}

	cmd.Flags().StringVar(&backupPlanUID, BackupPlanUIDFlag, backupPlanUIDDefault, backupPlanUIDUsage)
	cmd.Flags().StringVar(&backupUID, BackupUIDFlag, backupUIDDefault, backupUIDUsage)
	err := cmd.MarkFlagRequired(BackupUIDFlag)
	if err != nil {
		log.Fatalf("Invalid option or missing required flag %s - %s", BackupUIDFlag, err.Error())
	}
	return cmd
}

func getMetadata(*cobra.Command, []string) error {
	mdOptions := targetBrowser.MetadataListOptions{
		BackupPlanUID: backupPlanUID,
		BackupUID:     backupUID,
		OutputFormat:  outputFormat,
	}

	return targetBrowserAuthConfig.GetMetadata(&mdOptions)
}
