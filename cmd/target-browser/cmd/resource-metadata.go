package cmd

import (
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"

	targetBrowser "github.com/trilioData/tvk-plugins/tools/target-browser"
)

func init() {
	getCmd.AddCommand(resourceMetadataCmd())
}

// resourceMetadataCmd represents the resource-metadata command
func resourceMetadataCmd() *cobra.Command {
	var cmd = &cobra.Command{
		Use:   ResourceMetadataCmdName,
		Short: "Get metadata details of particular resource from backup",
		Long:  `Performs GET operation on target-browser's '/resource-metadata' API and gets Application metadata from backup`,
		Example: `  # Get resource-metadata details of specific backup
  kubectl tvk-target-browser get resource-metadata --backup-uid <uid> --backup-plan-uid <uid> --name <name> --group <group> 
	--version <version> --kind <kind>
`,
		RunE: getResourceMetadata,
	}

	cmd.Flags().StringVarP(&group, GroupFlag, GroupFlagShort, groupDefault, groupUsage)

	cmd.Flags().StringVar(&name, NameFlag, nameDefault, nameUsage)

	cmd.Flags().StringVar(&backupPlanUID, BackupPlanUIDFlag, backupPlanUIDDefault, backupPlanUIDUsage)
	err := cmd.MarkFlagRequired(BackupPlanUIDFlag)
	if err != nil {
		log.Fatalf("Invalid option or missing required flag %s - %s", BackupPlanUIDFlag, err.Error())
	}

	cmd.Flags().StringVar(&backupUID, BackupUIDFlag, backupUIDDefault, backupUIDUsage)
	err = cmd.MarkFlagRequired(BackupUIDFlag)
	if err != nil {
		log.Fatalf("Invalid option or missing required flag %s - %s", BackupUIDFlag, err.Error())
	}

	cmd.Flags().StringVarP(&version, VersionFlag, VersionFlagShort, versionDefault, versionUsage)
	err = cmd.MarkFlagRequired(VersionFlag)
	if err != nil {
		log.Fatalf("Invalid option or missing required flag %s - %s", VersionFlag, err.Error())
	}

	cmd.Flags().StringVarP(&kind, KindFlag, KindFlagShort, kindDefault, kindUsage)
	err = cmd.MarkFlagRequired(KindFlag)
	if err != nil {
		log.Fatalf("Invalid option or missing required flag %s - %s", KindFlag, err.Error())
	}

	return cmd
}

func getResourceMetadata(*cobra.Command, []string) error {
	resourceMdOptions := targetBrowser.ResourceMetadataListOptions{
		BackupPlanUID: backupPlanUID,
		BackupUID:     backupUID,
		Name:          name,
		Group:         group,
		Kind:          kind,
		Version:       version,
		OutputFormat:  outputFormat,
	}

	err := targetBrowserAuthConfig.GetResourceMetadata(&resourceMdOptions)
	if err != nil {
		return err
	}
	return nil

}
