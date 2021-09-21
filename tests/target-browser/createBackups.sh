#!/bin/bash
# shellcheck disable=SC2004
# shellcheck disable=SC1073
# shellcheck disable=SC1048
# shellcheck disable=SC1072
# shellcheck disable=SC1009

set -ex

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixpath="/triliodata"
backupType=('Helm' 'Operator' 'Custom' 'Namespace')
backupStatus=('InProgress' 'Completed' 'Available' 'Failed')
for ((i = 0; i < $1; i++)); do
  bplanuid=$(uuidgen)
  if [ "$5" = "helm" ]; then
    index=0
  elif [ "$5" = "custom" ]; then
    index=2
  else
    index=$RANDOM%4
  fi
  backupStatusIndex=$RANDOM%4

  for ((j = 0; j < $2; j++)); do

    backupuid=$4
    backuppath=${fixpath}/${bplanuid}/${backupuid}
    completionTime=$(($(($RANDOM % 50)) + 10))
    expirationTime=$(($(($RANDOM % 50)) + 10))
    echo "Creating backup in directory ${backuppath}"
    mkdir -p "${backuppath}"

    # used to add custom parameter values in backup & backupplans .json files
    if [ "$3" = "backup" ]; then
      cp "${src_dir}"/test_files/backup-with-placeholders.json "${src_dir}"/test_files/backup-modified.json
      cp "${src_dir}"/test_files/backupplan-with-placeholders.json "${src_dir}"/test_files/backupplan-modified.json

      echo "Replacing placeholders in backup & backupplan json files"
      # change placeholders in backup file with a new values
      sed -i "s/BACKUP-NAME/backup-$j/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/BACKUP-UUID/$backupuid/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/BACKUPPLAN-UUID/$bplanuid/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/BACKUPPLAN-NAME/backupplan-$i/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/BACKUP-STATUS/${backupStatus[backupStatusIndex]}/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/APPLICATION-TYPE/${backupType[index]}/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/COMPLETION-TIMESTAMP/$completionTime/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/EXPIRATION-TIMESTAMP/$expirationTime/g" "${src_dir}"/test_files/backup-modified.json

      # change placeholders in backupplan file with a new value
      sed -i "s/BACKUP-NAME/backup-$j/g" "${src_dir}"/test_files/backupplan-modified.json
      sed -i "s/BACKUPPLAN-NAME/backupplan-$i/g" "${src_dir}"/test_files/backupplan-modified.json
      sed -i "s/APPLICATION-TYPE/${backupType[index]}/g" "${src_dir}"/test_files/backupplan-modified.json
      sed -i "s/BACKUPPLAN-UUID/$bplanuid/g" "${src_dir}"/test_files/backupplan-modified.json
      sed -i "s/BACKUP-UUID/$backupuid/g" "${src_dir}"/test_files/backupplan-modified.json
      sed -i "s/COMPLETION-TIMESTAMP/$completionTime/g" "${src_dir}"/test_files/backupplan-modified.json

      # modify backupcomponents in backupPlan json file as per value of index variable
      if [[ $index -eq 0 ]]; then
        sed -i "s/\"BACKUPPLAN-COMPONENTS\"/{\"helmReleases\":[\"mysql\"]}/g" "${src_dir}"/test_files/backupplan-modified.json
      elif [[ $index -eq 1 ]]; then
        sed -i "s/\"BACKUPPLAN-COMPONENTS\"/{\"operators\":[{\"operatorId\":\"abc\"}]}/g" "${src_dir}"/test_files/backupplan-modified.json
      elif [[ $index -eq 2 ]]; then
        sed -i "s/\"BACKUPPLAN-COMPONENTS\"/{\"custom\":[{\"matchLabels\":{\"app\":\"nginx\"}}]}/g" "${src_dir}"/test_files/backupplan-modified.json
      else
        sed -i "s/\"BACKUPPLAN-COMPONENTS\"/{}/g" "${src_dir}"/test_files/backupplan-modified.json
      fi

      # copy modified files to NFS location
      mv "${src_dir}"/test_files/backup-modified.json "${backuppath}"/backup.json
      mv "${src_dir}"/test_files/backupplan-modified.json "${backuppath}"/backupplan.json
      if [ "$6" == "ingress" ]; then
        mkdir "${backuppath}"/custom
        mkdir "${backuppath}"/custom/metadata-snapshot/
        mv "${src_dir}"/test-data/resource-metadata-ingress.json "${backuppath}"/custom/metadata-snapshot/metadata.json
      fi
    elif [ "$3" == "all_type_backup" ]; then
      cp "${src_dir}"/test_files/backup-all.json "${src_dir}"/test_files/backup-modified.json
      cp "${src_dir}"/test_files/backupplan-all.json "${src_dir}"/test_files/backupplan-modified.json

      echo "Replacing placeholders in backup & backupPlan json files"
      # change placeholders in backup file with a new values

      sed -i "s/BACKUP-UUID/$backupuid/g" "${src_dir}"/test_files/backup-modified.json
      sed -i "s/BACKUPPLAN-UUID/$bplanuid/g" "${src_dir}"/test_files/backup-modified.json

      # change placeholders in backupPlan file with a new value
      sed -i "s/BACKUPPLAN-UUID/$bplanuid/g" "${src_dir}"/test_files/backupplan-modified.json
      sed -i "s/BACKUP-UUID/$backupuid/g" "${src_dir}"/test_files/backupplan-modified.json

      # copy modified files to NFS location
      mv "${src_dir}"/test_files/backup-modified.json "${backuppath}"/backup.json
      mv "${src_dir}"/test_files/backupplan-modified.json "${backuppath}"/backupplan.json
    elif [ "$3" == "cluster_backup" ]; then
      cp "${src_dir}"/test_files/cluster-backup-with-placeholders.json "${src_dir}"/test_files/cluster-backup-modified.json
      cp "${src_dir}"/test_files/cluster-backupplan-with-placeholders.json "${src_dir}"/test_files/cluster-backupplan-modified.json

      echo "Replacing placeholders in cluster backup & backupplan json files"
      # change placeholders in cluster backup file with a new values
      sed -i "s/CLUSTER-BACKUP-NAME/cluster-backup-$j/g" "${src_dir}"/test_files/cluster-backup-modified.json
      sed -i "s/CLUSTER-BACKUP-UUID/$backupuid/g" "${src_dir}"/test_files/cluster-backup-modified.json
      sed -i "s/CLUSTER-BACKUPPLAN-UUID/$bplanuid/g" "${src_dir}"/test_files/cluster-backup-modified.json
      sed -i "s/CLUSTER-BACKUPPLAN-NAME/cluster-backupplan-$i/g" "${src_dir}"/test_files/cluster-backup-modified.json
      sed -i "s/BACKUP-STATUS/${backupStatus[backupStatusIndex]}/g" "${src_dir}"/test_files/cluster-backup-modified.json
      sed -i "s/COMPLETION-TIMESTAMP/$completionTime/g" "${src_dir}"/test_files/cluster-backup-modified.json
      sed -i "s/EXPIRATION-TIMESTAMP/$expirationTime/g" "${src_dir}"/test_files/cluster-backup-modified.json

      # change placeholders in cluster backupplan file with a new value
      sed -i "s/CLUSTER-BACKUP-NAME/backup-$j/g" "${src_dir}"/test_files/cluster-backupplan-modified.json
      sed -i "s/CLUSTER-BACKUPPLAN-NAME/cluster-backupplan-$i/g" "${src_dir}"/test_files/cluster-backupplan-modified.json
      sed -i "s/CLUSTER-BACKUPPLAN-UUID/$bplanuid/g" "${src_dir}"/test_files/cluster-backupplan-modified.json
      sed -i "s/CLUSTER-BACKUP-UUID/$backupuid/g" "${src_dir}"/test_files/cluster-backupplan-modified.json

      # copy modified files to NFS location
      mv "${src_dir}"/test_files/cluster-backup-modified.json "${backuppath}"/cluster-backup.json
      mv "${src_dir}"/test_files/cluster-backupplan-modified.json "${backuppath}"/cluster-backupplan.json
    else
      if [ "$3" = "mutate-tvk-id" ]; then
        cp "${src_dir}"/test_files/tvk-meta.json "${src_dir}"/test_files/tvk-meta-modified.json
        sed -i "s/TVK-UID/$4/g" "${src_dir}"/test_files/tvk-meta-modified.json
        mv "${src_dir}"/test_files/tvk-meta-modified.json "${backuppath}"/tvk-meta.json
      fi
      cp "${src_dir}"/test_files/backup.json "${backuppath}"/backup.json
      cp "${src_dir}"/test_files/backupplan.json "${backuppath}"/backupplan.json
    fi
  done
done
