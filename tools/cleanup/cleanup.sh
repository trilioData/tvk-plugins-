#!/bin/bash 

# Cleans up all Trilio resources from the k8s cluster
# IMP - Runs on the sourced kubeconfig (refers to .kube/config)
# Please make sure that correct kubeconfig is used or sourced
# Deleted resources can not be recovered

CLEANUP_RUN_SUCCESS=true

check_if_ocp() {
  # Check if the k8s cluster is upstream or OCP
  local is_ocp="False"
  if (kubectl api-resources | grep -q openshift.io); then
    is_ocp="True"
  fi
  echo "${is_ocp}"
}

delete_tvk_res(){
  # Same for OCP & Upstream
  # Check all the namespaces for restores, delete the restores 
  local exit_status=0
  for res in ${TVK_resources}
  do
    if (kubectl get "${res}" -A --no-headers 2>/dev/null)
    then
      # Fetch non-deuplicate namespace for the given resource
      for ns in $(kubectl get "${res}" -A --no-headers 2>/dev/null | awk '{print $1}'| uniq) 
      do
        # Fetch given resource name
        for name in $(kubectl get "${res}" -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'| uniq)
        do 
          # Delete 
          echo "kubectl delete ${res} ${name} -n ${ns} "
          kubectl delete "${res}" "${name}" -n "${ns}"
	  retValue=$?
          if [ "${retValue}" -ne 0 ]
          then
	    exit_status=1
          fi
        done
      done
    else
      echo "Resource ${res} does not exist on the cluster"
      echo
    fi
  done
  return ${exit_status}
}

delete_tvk_op(){
  # Check if the k8s cluster is upstream or OCP
  local exit_status=0
  if [[ $(check_if_ocp) == "True" ]]; then
    echo "This is OCP Cluster"
    # Delete k8s-triliovault operator
    if (kubectl get subscription k8s-triliovault -n openshift-operators >/dev/null 2>&1)
    then 
      echo "Uninstalling k8s-triliovault operator"
      kubectl delete subscription k8s-triliovault -n openshift-operators
      retValue=$?
      if [ "${retValue}" -ne 0 ]
      then
        exit_status=1
      fi
    fi
    
    # Delete k8s-triliovault clusterserviceversion
    tvkcsversion=$(kubectl get clusterserviceversion --no-headers -n openshift-operators 2>/dev/null | grep k8s-triliovault | awk '{print $1}')
    if [ -n "${tvkcsversion}" ]
    then 
      echo "Deleting k8s-triliovault clusterserviceversion"
      kubectl delete clusterserviceversion "${tvkcsversion}" -n openshift-operators
      retValue=$?
      if [ "${retValue}" -ne 0 ]
      then
        exit_status=1
      fi
    fi
    
    # Delete k8s-triliovault-resource-cleaner cronjob
    tvkcron=$(kubectl get cronjob --no-headers -n openshift-operators 2>/dev/null | grep k8s-triliovault | awk '{print $1}')
    if [ -n "${tvkcron}" ]
    then 
      echo "Deleting k8s-triliovault-resource-cleaner cronjob"
      kubectl delete cronjob "${tvkcron}" -n openshift-operators
      retValue=$?
      if [ "${retValue}" -ne 0 ]
      then
        exit_status=1
      fi
    fi
  fi

  # For Upstream OR in case if TVK installed on OCP using "helm"
  # Delete Triliovault-manager and Triliovault-operator using helm/label
  if (helm list -A | grep -v REVISION | grep triliovault >/dev/null 2>&1)
  then
    echo "Uninstalling Trilivault-manager"
    tvm=("$(helm list -A | grep -v REVISION | grep triliovault-v | awk '{print $1,$2}')")
    helm uninstall "${tvm[0]}" -n "${tvm[1]}"
    retValue=$?
    if [ "${retValue}" -ne 0 ]
    then
      exit_status=1
    fi
    echo "Uninstalling Trilivault-operator"
    tvm=("$(helm list -A | grep -v REVISION | grep triliovault-o | awk '{print $1,$2}')")
    helm uninstall "${tvm[0]}" -n "${tvm[1]}"
    retValue=$?
    if [ "${retValue}" -ne 0 ]
    then
      exit_status=1
    fi
  fi
  return ${exit_status}
}

delete_tvk_crd(){
  # Same for OCP & Upstream
  # Check all the namespaces for restores, delete the restores 
  # Delete Triliovault CRDs
  local exit_status=0
  for tvkcrd in $(kubectl get crd --no-headers 2>/dev/null | grep triliovault | awk '{print $1}')
  do
    # Delete
    echo "kubectl delete crd ${tvkcrd}"
    kubectl delete crd "${tvkcrd}"
    retValue=$?
    if [ "${retValue}" -ne 0 ]
    then
      exit_status=1
    fi
  done
  return ${exit_status}
}

print_usage(){
  echo "
--------------------------------------------------------------
tvk-cleanup - Cleans up Triliovault Custom reources and CRDs
Usage:
kubectl tvk-cleanup [options] [arguments]
Options:
        -h, --help                show brief help
        -n, --noninteractive      run script in non-interactive mode
        -c, --crd                 delete Triliovault CRDs
        -t, --tvm                 delete Triliovault Manager or Operator
        -r, --resources \"resource1 resource2..\"
                                  specify list of Triliovault CRs to delete
                                  If not provided, all Triliovault CRs (listed below) will be deleted
                                  e.g. Restore Backup Backupplan Hook Target Policy License
--------------------------------------------------------------
"
}

# Main script starts here
# Check the options provided
if [ $# -eq 0 ]
then
  print_usage
  exit 1
fi

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      print_usage
      exit 0
      ;;
    -n|--noninteractive)
      export Non_interact=True
      echo "Flag set to run cleanup in non-interactive mode"
      echo
      ;;
    -c|--crd)
      export Delete_CRD=True
      echo "Flag set to delete Triliovault CRDs"
      echo
      ;;
    -t|--tvm)
      export Delete_TVM=True
      echo "Flag set to delete Triliovault Manager or Operator"
      echo
      ;;
    -r|--resources)
      shift
      if [[ "$*" == -* || $# -eq 0 ]]; then
        export TVK_resources="Restore Backup Backupplan Hook Target Policy License"
        echo "No resources specified, will be deleting all resources listed below"
        echo "Restore Backup Backupplan Hook Target Policy License"
	echo
        continue
      else
        export TVK_resources=$1
	echo "Resource list: ${TVK_resources}"
	echo
      fi
      ;;
    *)
      echo "Incorrect option, check usage below..."
      echo
      print_usage
      exit 1
      ;;
  esac
  shift
done

echo "##################### DISCLAIMER ############################"
echo "# This script deletes all the Triliovault Custom Resources, #"
echo "# Triliovault Manager application and CRDs from all the     #" 
echo "# namespaces. Once deleted, these can not be recovered.     #"
echo "# Please select the options carefully.                      #"
echo "#############################################################"
echo

if [[ ${Non_interact} != "True" ]]
then
  echo -n "Do you want to continue: y/n? "
  read -r start
  if [[ ${start} != "Y" && ${start} != "y" ]]
  then
    echo "Exiting..............................."
    echo
    exit 0
  fi
fi

if [[ -z "${TVK_resources}" && -z "${Delete_TVM}" && -z "${Delete_CRD}" ]]
then
  echo "No resources selected for cleanup, please check usage below"
  print_usage
  exit
fi

echo "Starting Cleanup..............................."
echo

if [ -n "${TVK_resources}" ]
then
  echo "Deleting Triliovault resources: "
  echo "${TVK_resources}"
  echo
  # Delete Triliovault resource
  delete_tvk_res
  retValue=$?
  if [ "${retValue}" -ne 0 ]
  then
    CLEANUP_RUN_SUCCESS=false
  fi
fi

if [ ${Delete_TVM} ]
then
  echo "Deleting Triliovault Manager or Operator"
  echo
  # Delete Triliovault Manager or Operator
  delete_tvk_op
  retValue=$?
  if [ "${retValue}" -ne 0 ]
  then
    CLEANUP_RUN_SUCCESS=false
  fi
fi

if [ ${Delete_CRD} ]
then
  echo "Deleting Triliovault CRDs"
  echo
  # Delete CRDs
  delete_tvk_crd
  retValue=$?
  if [ "${retValue}" -ne 0 ]
  then
    CLEANUP_RUN_SUCCESS=false
  fi
fi

# Print status of cleanup
if [ $CLEANUP_RUN_SUCCESS == "true" ]; then
  echo "Cleanup completed successfully!!"
else
  echo "Cleanup failed!!"
  exit 1
fi
