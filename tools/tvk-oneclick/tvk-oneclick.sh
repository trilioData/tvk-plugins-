#!/bin/bash


#This program is use to install/configure/test TVK product with one click and few required inputs


#This module is used to perform preflight check which checks if all the pre-requisites are satisfied before installing Triliovault for Kubernetes application in a Kubernetes cluster
preflight_checks()
{
  ret=$(kubectl krew 2>/dev/null)
  if [[ -z "$ret" ]];then
    echo "Please install krew plugin and then try.For information on krew installation please visit:"
    echo "https://krew.sigs.k8s.io/docs/user-guide/setup/install/"
    exit 1
  fi
  if  [[ $(kubectl tvk-preflight --help  2>/dev/null) ]];
  then
    echo "Skipping plugin tvk-preflight installation as it is already installed"
  else
    plugin_url='https://github.com/trilioData/tvk-plugins.git'
    kubectl krew index add tvk-plugins "$plugin_url" 1>> >(logit) 2>> >(logit)
    kubectl krew install tvk-plugins/tvk-preflight 1>> >(logit) 2>> >(logit)
    retcode=$?
    if [ "$retcode" -ne 0 ];then 
      echo "Failed to install tvk-plugins/tvk-preflight plugin" 2>> >(logit)
    fi
  fi 
  if  [[ -z "${input_config}" ]];then
    read -r -p "Provide storageclass to be used for TVK/Application Installation(storageclass with default annotation): " storage_class
  fi
  if [[ -z "$storage_class" ]];then
	  storage_class=$(kubectl get storageclass | grep -w '(default)' | awk  '{print $1}')
	  if [[ -z "$storage_class" ]];then
	    echo "No default storage class found, need one to proceed";
	    exit 1
          fi
  fi
  check=$(kubectl tvk-preflight --storageclass "$storage_class" | tee /dev/tty)
  check_for_fail=$(echo "$check" | grep  'Some Pre-flight Checks Failed!')
  if [[ -z "$check_for_fail" ]];then
    echo "All preflight checks are done and you can proceed"
  else 
    if  [[ -z "${input_config}" ]];then
      echo "There are some failures"
      read -r -p "Do you want to proceed?y/n: " proceed_even_PREFLIGHT_fail
    fi
    if [[ "$proceed_even_PREFLIGHT_fail" != "Y" ]] && [[ "$proceed_even_PREFLIGHT_fail" != "y" ]];then
      exit 1
    fi
  fi
}

#This function is use to compare 2 versions
vercomp () {
    if [[ $1 == "$2" ]]
    then
        return 0
    fi
    local IFS=.
    # shellcheck disable=SC2206
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}



#function to print waiting symbol
wait_install()
{
  runtime=$1
  spin='-\|/'
  i=0
  endtime=$(date -ud "$runtime" +%s)
  if [[ -z ${endtime} ]];then
    echo "There is some issue with date usage, please check the pre-requsites in README page" 1>> >(logit) 2>> >(logit)
    echo "Something went wrong..terminating" 2>> >(logit)
  fi
  val1=$(eval "$2")
  while [[ $(date -u +%s) -le $endtime ]] && [[ "" == "$val1" ]] || [[ "$val1" == '{}' ]]
  do
    i=$(( (i+1) %4 ))
    printf "\r %s" "${spin:$i:1}"
    sleep .1
    val1=$(eval "$2")
  done
  echo ""
}

#This module is used to install TVK along with its free trial license
install_tvk()
{
  # Add helm repo and install triliovault-operator chart
  helm repo add triliovault-operator http://charts.k8strilio.net/trilio-stable/k8s-triliovault-operator 1>> >(logit) 2>> >(logit)
  retcode=$?
  if [ "$retcode" -ne 0 ];then
    echo "There is some error in helm update,please resolve and try again" 1>> >(logit) 2>> >(logit)
    echo "Error ading helm repo"
    exit 1
  fi
  helm repo add triliovault http://charts.k8strilio.net/trilio-stable/k8s-triliovault 1>> >(logit) 2>> >(logit) 
  helm repo update 1>> >(logit) 2>> >(logit)
  if  [[ -z ${input_config} ]];then
    read -r -p "Please provide the operator version to be installed(2.1.0): " operator_version
    read -r -p "Please provide the triliovault manager version(v2.1.1-alpha): " triliovault_manager_version
    read -r -p "Proceed even if resource exists(True): " if_resource_exists_still_proceed
  fi
  if [[ -z "$if_resource_exists_still_proceed" ]];then
    if_resource_exists_still_proceed=True
  fi
  if [[ -z "$operator_version" ]];then
    operator_version='2.1.0'
  fi
  if [[ -z "$triliovault_manager_version" ]];then
    triliovault_manager_version='v2.1.1-alpha'
  fi
  get_ns=$(kubectl get deployments -l "release=triliovault-operator" -A 2>> >(logit) | awk '{print $1}' | sed -n 2p)
  if [ -z "$get_ns" ];then
    # Install triliovault operator
    echo "Installing Triliovault operator..."
    helm install triliovault-operator triliovault-operator/k8s-triliovault-operator --version $operator_version 2>> >(logit)
    retcode=$?
    if [ "$retcode" -ne 0 ];then 
      echo "There is some error in helm install triliovaul operator,please resolve and try again" 2>> >(logit) 
      exit 1
    fi
  else
    old_operator_version=$(helm list  -n "$get_ns" | grep k8s-triliovault-operator | awk '{print $9}' | rev  | cut -d- -f1 | rev | sed 's/[a-z-]//g')
    # shellcheck disable=SC2001
    new_operator_version=$(echo $operator_version | sed 's/[a-z-]//g')
    vercomp "$old_operator_version" "$new_operator_version"
    ret_val=$?
    if [[ $ret_val != 2 ]];then
      echo "Triliovault operator cannot be upgraded, please check version number"
      if ! [[ $if_resource_exists_still_proceed ]];then
        exit 1
      fi
    else
      echo "Upgrading Triliovault operator"
      # shellcheck disable=SC2206
      semver=( ${old_operator_version//./ } )
      major="${semver[0]}"
      minor="${semver[1]}"
      sub_ver=${major}.${minor}
      if [[ $sub_ver == 2.0 ]];then
        helm plugin install https://github.com/trilioData/tvm-helm-plugins >/dev/null 1>> >(logit) 2>> >(logit)
	rel_name=$(helm list | grep k8s-triliovault-operator | awk '{print $1}')
	helm tvm-upgrade --release="$rel_name" --namespace="$get_ns" 2>> >(logit)
	retcode=$?
	if [ "$retcode" -ne 0 ];then 
	  echo "There is some error in helm tvm-upgrade,please resolve and try again" 2>> >(logit)
	  exit 1
        fi
      fi 	
      helm  upgrade triliovault-operator triliovault-operator/k8s-triliovault-operator --version $operator_version 2>> >(logit)
      retcode=$?
      if [ "$retcode" -ne 0 ];then 
        echo "There is some error in helm upgrade,please resolve and try again" 2>> >(logit)
	exit 1
      fi
      sleep 10
    fi
  fi
  cmd="kubectl get pod -l release=triliovault-operator -o 'jsonpath={.items[*].status.conditions[*].status}' | grep -v False"
  wait_install "10 minute" "$cmd"
  if ! kubectl get pods -l release=triliovault-operator 2>/dev/null | grep -q Running;then
    echo "Triliovault operator installation failed"
    exit 1
  fi
  echo "Triliovault operator is running"
  
  #check if TVK manager is installed
  if [[ $(kubectl get pods -l app=k8s-triliovault-control-plane 2>/dev/null) ]] && [[ $(kubectl get pods -l app=k8s-triliovault-admission-webhook 2>/dev/null) ]];then
    #Check if TVM can be upgraded
    old_tvm_version=$(kubectl get TrilioVaultManager -n "$get_ns" -o json | grep releaseVersion | awk '{print$2}' | sed 's/[a-z-]//g' |  sed -e 's/^"//' -e 's/"$//')
    # shellcheck disable=SC2001
    new_triliovault_manager_version=$(echo $triliovault_manager_version | sed 's/[a-z-]//g')
    vercomp "$old_tvm_version" "$new_triliovault_manager_version"
    ret_val=$?
    if [[ $ret_val != 2 ]];then
      echo "TVM cannot be upgraded! Please check version"
      if ! [[ $if_resource_exists_still_proceed ]];then
        exit 1
      fi
      return
    else
      if [[ $old_tvm_version == 2.1* ]] && [[ $new_triliovault_manager_version == 2.5* ]];
      then
        svc_type=$(kubectl get svc k8s-triliovault-ingress-gateway -o 'jsonpath={.spec.type}')
        if [[ $svc_type == LoadBalancer ]];
        then
          get_host=$(kubectl get ingress k8s-triliovault-ingress-master -o 'jsonpath={.spec.rules[0].host}')
  cat <<EOF | kubectl apply -f - 1>> >(logit) 2>> >(logit)
apiVersion: triliovault.trilio.io/v1
kind: TrilioVaultManager
metadata:
  labels:
    triliovault: triliovault
  name: tvm
spec:
  trilioVaultAppVersion: ${triliovault_manager_version}
  componentConfiguration:
    ingress-controller:
      service:
        type: LoadBalancer
      host: "${get_host}"
  helmVersion:
    version: v3
  applicationScope: Cluster
EOF
          retcode=$?
          if [ "$retcode" -ne 0 ];then
            echo "There is error upgrading triliovault manager,please resolve and try again" 2>> >(logit)
            exit 1
	  else
	    echo "Triliovault manager upgraded successfully"
          fi
          return
	 fi
      fi
    fi
    
  fi
    
  # Create TrilioVaultManager CR
  sleep 10
  cat <<EOF | kubectl apply -f - 1>> >(logit) 2>> >(logit) 
apiVersion: triliovault.trilio.io/v1
kind: TrilioVaultManager
metadata:
  labels:
    triliovault: triliovault
  name: tvm
spec:
  trilioVaultAppVersion: ${triliovault_manager_version}
  helmVersion:
    version: v3
  applicationScope: Cluster
EOF
  retcode=$?
  if [ "$retcode" -ne 0 ];then 
    echo "There is error in installing triliovault manager,please resolve and try again" 2>> >(logit)
    exit 1
  fi
  sleep 2
  echo "Installing Triliovault manager...."
  cmd="kubectl get pods -l app=k8s-triliovault-control-plane 2>/dev/null | grep Running"
  wait_install "10 minute" "$cmd"
  cmd="kubectl get pods -l app=k8s-triliovault-admission-webhook 2>/dev/null | grep Running"
  wait_install "10 minute" "$cmd"
  if ! kubectl get pods -l app=k8s-triliovault-control-plane 2>/dev/null | grep -q Running && ! kubectl get pods -l app=k8s-triliovault-admission-webhook 2>/dev/null | grep -q Running; then
      echo "TVM installation failed"
      exit 1
  fi
  echo "TVK Manager is installed"
  install_license
}


#This module is use to install license
install_license(){
  echo "Installing Freetrial license..."
  #Install required packages
  {
    sudo apt update
    yes | sudo apt install python3-pip
    pip3 install beautifulsoup4 
    pip3 install lxml 
  } 1>> >(logit) 2>> >(logit)
  cat <<EOF | python3
#!/usr/bin/python3

from bs4 import BeautifulSoup
import requests
import sys
import subprocess

headers = {'Content-type': 'application/x-www-form-urlencoded; charset=utf-8'}
endpoint="https://doc.trilio.io:5000/8d92edd6-514d-4acd-90f6-694cb8d83336/0061K00000fwkzU"
result = subprocess.check_output("kubectl get ns kube-system -o=jsonpath='{.metadata.uid}'", shell=True)
kubeid = result.decode("utf-8")
data = "kubescope=clusterscoped&kubeuid={0}".format(kubeid)
r = requests.post(endpoint, data=data, headers=headers)
contents=r.content
soup = BeautifulSoup(contents, 'lxml')
sys.stdout = open("license_file1.yaml", "w")
print(soup.body.find('div', attrs={'class':'yaml-content'}).text)
sys.stdout.close()
result = subprocess.check_output("kubectl apply -f license_file1.yaml", shell=True)
EOF
}


#This module is used to configure TVK UI
configure_ui()
{
 if  [[ -z ${input_config} ]];then
   echo -e "TVK UI can be accessed using \n1.Loadbalancer \n2.Nodeport \n3.PortForwarding"
   read -r -p "Please enter option: " ui_access_type
 else
   if [[ $ui_access_type == 'Loadbalancer' ]];then
     ui_access_type=1
   elif [[ $ui_access_type == 'Nodeport' ]];then
     ui_access_type=2
   elif [[ $ui_access_type == 'PortForwarding' ]];then
     ui_access_type=3
   else
     echo "Wrong option selected for ui_access_type"
     exit 1
   fi
 fi
 if [[ -z "$ui_access_type" ]]; then
      ui_access_type=2
 fi
 case $ui_access_type in
   3)
     echo "kubectl port-forward --address 0.0.0.0 svc/k8s-triliovault-ingress-gateway 80:80 &"
     echo "The above command will start forwarding TVK management console traffic to the localhost IP of 127.0.0.1 via port 80"
     ;;
   2)
     configure_nodeport_for_tvkui
     return 0
     ;;
   1)
     configure_loadbalancer_for_tvkUI
     return 0
     ;;
   *)
     echo "Incorrect choice"
     exit 1
     ;;
   esac
   shift

}

#This function is used to configure TVK UI through nodeport
configure_nodeport_for_tvkui()
{
  if  [[ -z ${input_config} ]];then
    read -r -p "Please enter hostname for a cluster: " tvkhost_name
  fi
  gateway=$(kubectl get pods --no-headers=true 2>/dev/null | awk '/k8s-triliovault-ingress-gateway/{print $1}')
  if [[ -z "$gateway" ]]; then
    echo "Not able to find k8s-triliovault-ingress-gateway resource,TVK UI configuration failed"
    exit 1
  fi
  node=$(kubectl get pods "$gateway" -o jsonpath='{.spec.nodeName}' 2>> >(logit))
  ip=$(kubectl get node "$node"  -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}' 2>> >(logit))
  port=$(kubectl get svc k8s-triliovault-ingress-gateway  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>> >(logit))
  if ! kubectl patch ingress k8s-triliovault-ingress-master -p '{"spec":{"rules":[{"host":"'"${tvkhost_name}-tvk.com"'"}]}}';then
    echo "TVK UI configuration failed, please check ingress"
    exit 1
  fi
  echo "For accesing UI, create an entry in /etc/hosts file for the IPs like '$ip  $tvkhost_name-tvk.com'"
  echo "After creating an entry,TVK UI can be accessed through http://$tvkhost_name-tvk.com:$port"
  echo "For https access, please refer - https://docs.trilio.io/kubernetes/management-console/user-interface/accessing-the-ui" 
}

#This function is used to configure TVK UI through Loadbalancer
configure_loadbalancer_for_tvkUI()
{
 if  [[ -z ${input_config} ]];then
   read -r -p "Please enter domainname for cluster: " domain
   read -r -p "Please enter host name  for a cluster: " tvkhost_name
   read -r -p "Please enter cluster name: " cluster_name 
 fi
 if ! kubectl patch svc k8s-triliovault-ingress-gateway -p '{"spec": {"type": "LoadBalancer"}}' 1>> >(logit) 2>> >(logit) ; then
   echo "TVK UI configuration failed, please check ingress"
   exit 1
 fi
 echo "Configuring UI......This may take some time"
 cmd="kubectl get svc k8s-triliovault-ingress-gateway -o 'jsonpath={.status.loadBalancer}'"
 wait_install "20 minute" "$cmd"
 val_status=$(kubectl get svc k8s-triliovault-ingress-gateway -o 'jsonpath={.status.loadBalancer}')
 if [[ $val_status == '{}' ]]
 then
    echo "Loadbalancer taking time to get External IP"
    exit 1
 fi
 external_ip=$(kubectl get svc k8s-triliovault-ingress-gateway -o 'jsonpath={.status.loadBalancer.ingress[0].ip}' 2>> >(logit))
 kubectl patch ingress k8s-triliovault-ingress-master -p '{"spec":{"rules":[{"host":"'"${tvkhost_name}.${domain}"'"}]}}' 1>> >(logit) 2>> >(logit)
 doctl compute domain records create "${domain}" --record-type A --record-name "${tvkhost_name}" --record-data "${external_ip}" 1>> >(logit) 2>> >(logit)
 retCode=$?
 if [[ "$retCode" -ne 0 ]]; then
   echo "Failed to create record, please check domain name"
   exit 1
 fi

 doctl kubernetes cluster kubeconfig show "${cluster_name}" > config_"${cluster_name}" 2>> >(logit)
 link="http://${tvkhost_name}.${domain}/login"
 echo "You can access TVK UI: $link"
 echo "provide config file stored at location: $PWD/config_${cluster_name}"
 echo "Info:UI may take 30 min to come up"
}



#This module is used to create target to be used for TVK backup and restore
create_target()
{
   if  [[ -z ${input_config} ]];then
     echo -e "Target can be created on NFS or s3 compatible storage\n1.NFS(default) \n2.DOKs_S3"
     read -r -p "select option: " target_type
   else
     if [[ $target_type == 'NFS' ]];then
       target_type=1
     elif [[ $target_type == 'DOKs_S3' ]];then
       target_type=2
     else
       echo "Wrong value provided for target"
     fi
   fi
   if [[ -z "$target_type" ]]; then
      target_type=2
   fi
   case $target_type in
     2)
	yes | sudo apt-get install s3cmd 1>> >(logit) 2>> >(logit)
	#Create s3cfg_confg file for target creation
	cat > s3cfg_config <<- EOM
[default]
access_key = access_key
access_token =
add_encoding_exts =
add_headers =
bucket_location = US
ca_certs_file =
cache_file =
check_ssl_certificate = True
check_ssl_hostname = True
cloudfront_host = cloudfront.amazonaws.com
default_mime_type = binary/octet-stream
delay_updates = False
delete_after = False
delete_after_fetch = False
delete_removed = False
dry_run = False
enable_multipart = True
encoding = UTF-8
encrypt = False
expiry_date =
expiry_days =
expiry_prefix =
follow_symlinks = False
force = False
get_continue = False
gpg_command = /usr/bin/gpg
gpg_decrypt = %(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_encrypt = %(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase = trilio
guess_mime_type = True
host_base = nyc3.digitaloceanspaces.com
host_bucket = %(bucket)s.nyc3.digitaloceanspaces.com
human_readable_sizes = False
invalidate_default_index_on_cf = False
invalidate_default_index_root_on_cf = True
invalidate_on_cf = False
kms_key =
limit = -1
limitrate = 0
list_md5 = False
log_target_prefix =
long_listing = False
max_delete = -1
mime_type =
multipart_chunk_size_mb = 15
multipart_max_chunks = 10000
preserve_attrs = True
progress_meter = True
proxy_host =
proxy_port = 0
put_continue = False
recursive = False
recv_chunk = 65536
reduced_redundancy = False
requester_pays = False
restore_days = 1
restore_priority = Standard
secret_key = secret_key
send_chunk = 65536
server_side_encryption = False
signature_v2 = False
signurl_use_https = False
simpledb_host = sdb.amazonaws.com
skip_existing = False
socket_timeout = 300
stats = False
stop_on_error = False
storage_class =
urlencoding_mode = normal
use_http_expect = False
use_https = True
use_mime_magic = True
verbosity = WARNING
website_endpoint = http://%(bucket)s.s3-website-%(location)s.amazonaws.com/
website_error =
website_index = index.html
EOM
	if  [[ -z ${input_config} ]];then
          echo "for creation of bucket, please provide input"
          read -r -p "Access_key: " access_key
          read -r -p "Secret_key: " secret_key
          read -r -p "Host Base(nyc3.digitaloceanspaces.com): " host_base
	  read -r -p "Host Bucket(%(bucket)s.nyc3.digitaloceanspaces.com): " host_bucket
	  read -r -p "gpg_passphrase(trilio): " gpg_passphrase
          read -r -p "Bucket Name: " bucket_name
          read -r -p "Target Name: " target_name
          read -r -p "Target Namespace: " target_namespace
	  read -r -p "thresholdCapacity(1000Gi): " thresholdCapacity
	  read -r -p "Proceed even if resource exists(True): " if_resource_exists_still_proceed
        fi
	if [[ -z "$if_resource_exists_still_proceed" ]];then
          if_resource_exists_still_proceed=True
        fi
	if [[ $(kubectl get target "$target_name" -n "$target_namespace" 2>> >(logit)) ]];
        then
	  echo "Target with same name already exists"
	  if ! [[ $if_resource_exists_still_proceed ]]
	  then
	    exit 1
	  else
	    return 0
          fi
	fi
	if [[ -z "$gpg_passphrase" ]];then
	  gpg_passphrase="trilio"
	fi
	if [[ -z "$thresholdCapacity" ]];then
	  thresholdCapacity='1000Gi'
	fi
        if [[ -z "$host_base" ]]; then
          host_base="nyc3.digitaloceanspaces.com"
        fi
        if [[ -z "$host_bucket" ]]; then
          host_bucket="%(bucket)s.nyc3.digitaloceanspaces.com"
        fi
        region="$( cut -d '.' -f 1 <<< "$host_base" )"
        for i in access_key secret_key host_base host_bucket gpg_passphrase 
        do
          sed -i "s/^\($i\s*=\s*\).*$/\1${!i}/" s3cfg_config
          sudo cp s3cfg_config "$HOME"/.s3cfg
        done
        #create bucket
	ret_val=$(s3cmd mb s3://"$bucket_name" 2>> >(logit))
        ret_code=$(echo "$ret_val" | grep 'Bucket already exists')
	if [[ "$ret_code" ]]; then 
          echo "WARNING: Bucket already exists"
	else
	  echo "$ret_val"
        fi
        #create S3 target
        url="https://$host_base"
	cat <<EOF | kubectl apply -f - 1>> >(logit) 2>> >(logit)
apiVersion: triliovault.trilio.io/v1
kind: Target
metadata:
  name: ${target_name}
  namespace: ${target_namespace}
spec:
  type: ObjectStore
  vendor: Other
  objectStoreCredentials:
    url: "$url"
    accessKey: "$access_key"
    secretKey: "$secret_key"
    bucketName: "$bucket_name"
    region: "$region"
  thresholdCapacity: $thresholdCapacity
EOF
        retcode=$?
        if [ "$retcode" -ne 0 ];then
          echo "Target creation failed"
          #exit 1
	  return
        fi
	;;
     1)
	if  [[ -z ${input_config} ]];then
          read -r -p "Target Name: " target_name
          read -r -p "NFSserver: " nfs_server
          read -r -p "namespace: " target_namespace
          read -r -p "Export Path: " nfs_path
          read -r -p "NFSoption(nfsvers=4): " nfs_options
          read -r -p "thresholdCapacity(1000Gi): " thresholdCapacity
	  read -r -p "Proceed even if resource exists(True): " if_resource_exists_still_proceed
	fi
        if [[ -z "$if_resource_exists_still_proceed" ]];then
          if_resource_exists_still_proceed=True
        fi
	if [[ $(kubectl get target "$target_name" -n "$target_namespace" 2>/dev/null) ]];
        then
          echo "Target with same name already exists"
          if ! [[ $if_resource_exists_still_proceed ]]
          then
            exit 1
          else
            return 0
          fi
        fi
	if [[ -z "$thresholdCapacity" ]];then
          thresholdCapacity='1000Gi'
        fi
        if [[ -z "$nfs_options" ]]; then
          nfs_options='nfsvers=4'
        fi
	echo "Creating target..."
	cat <<EOF | kubectl apply -f - 1>> >(logit) 2>> >(logit)
apiVersion: triliovault.trilio.io/v1
kind: Target
metadata:
  name: ${target_name}
  namespace: ${target_namespace}
spec:
  type: NFS
  vendor: Other
  nfsCredentials:
    nfsExport: ${nfs_server}:${nfs_path}
    nfsOptions: ${nfs_options}
  thresholdCapacity: ${thresholdCapacity}
EOF
        retcode=$?
	if [ "$retcode" -ne 0 ];then
	  echo "Target creation failed"
	  exit
	fi
	;;
    *)
	echo "Wrong selection"
	exit 1
	;;
    esac
    shift
   cmd="kubectl get target $target_name -n  $target_namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep -e Available -e Unavailable"
   wait_install "15 minute" "$cmd"
   if ! kubectl get target "$target_name"  -n  "$target_namespace" -o 'jsonpath={.status.status}' 2>/dev/null | grep -q Available; then
     echo "Failed to create target"
     return
   else
     echo "Target is Available to use"
   fi

}


#This module is used to test TVK backup and restore for user.
sample_test()
{
   if  [[ -z ${input_config} ]];then
     echo "Please provide input for test demo"
     read -r -p "Target Name: " target_name
     read -r -p "Target Namespace: "  target_namespace
     read -r -p "Backupplan name(trilio-test-backup): " bk_plan_name
     read -r -p "Backup Name(trilio-test-backup): " backup_name
     read -r -p "Backup Namespace Name(trilio-test-backup): " backup_namespace
     read -r -p "Proceed even if resource exists(True): " if_resource_exists_still_proceed
   fi
   if [[ -z "$if_resource_exists_still_proceed" ]];then
      if_resource_exists_still_proceed=True
   fi
   if [[ -z "$backup_namespace" ]]; then
      backup_namespace=trilio-test-backup
   fi
   if [[ -z "$backup_name" ]]; then
      backup_name="trilio-test-backup"
   fi
   if [[ -z "$bk_plan_name" ]]; then
      bk_plan_name="trilio-test-backup"
   fi
   res=$(kubectl get ns $backup_namespace 2>/dev/null)
   if [[ -z "$res" ]]; then
     kubectl create ns $backup_namespace 2>/dev/null
   fi
   #Add stable helm repo
   helm repo add stable https://charts.helm.sh/stable 1>> >(logit) 2>> >(logit)
   helm repo update 1>> >(logit) 2>> >(logit)
   echo "User can take backup in multiple ways"
   if  [[ -z ${input_config} ]];then
     echo -e "Select an the backup way\n1.Label based(MySQL)\n2.Namespace based(Wordpress)\n3.Operator based(Postgres Operator)\n4.Helm based(Mongodb)"
     read -r -p "Select option: " backup_way
   else
     if [[ $backup_way == "Label_based" ]];then
       backup_way=1
     elif [[ $backup_way == "Namespace_based" ]];then
       backup_way=2
     elif [[ $backup_way == "Operator_based" ]];then
       backup_way=3
     elif [[ $backup_way == "Helm_based" ]];then
       backup_way=4
     else
       echo "Backup way is wrong/not defined"
       exit 1
     fi
   fi
   #Create backupplan template
   cat > backupplan.yaml <<- EOM
apiVersion: triliovault.trilio.io/v1
kind: BackupPlan
metadata:
  name: trilio-test-label
  namespace: trilio-test-backup
spec:
  backupNamespace: trilio-test-backup
  backupConfig:
    target:
      name: demo-target
      namespace: default
    schedulePolicy:
      incrementalCron:
        schedule: "* 0 * * *"
    retentionPolicy:
      name: sample-policy
      namespace: default
  backupPlanComponents:
    custom:
      - matchLabels:
          app: mysql-qa
EOM
   case $backup_way in
      1)
        ## Install mysql helm chart
	#check if app is already installed with same name
        if helm list -n "$backup_namespace" | grep -w -q mysql-qa;
        then
          echo "Application exists"
          if ! [[ $if_resource_exists_still_proceed ]]
          then
            exit 1
	  fi
        else
          helm install mysql-qa stable/mysql -n $backup_namespace 1>> >(logit) 2>> >(logit)
          echo "Installing Application"
          cmd="kubectl get pods -l app=mysql-qa -n $backup_namespace 2>/dev/null | grep Running"
          wait_install "10 minute" "$cmd"
          if ! kubectl get pods -l app=mysql-qa -n $backup_namespace 2>/dev/null | grep -q Running; then
            echo "Application installation failed"
            exit 1
          fi
	  echo "Requested application is installed successfully"
          yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml 1>> >(logit) 2>> >(logit)
          yq eval -i '.spec.backupPlanComponents.custom[0].matchLabels.app="mysql-qa"' backupplan.yaml 1>> >(logit) 2>> >(logit)
        fi
	;;
      2)
	if helm list -n $backup_namespace | grep -w -q my-wordpress 2>> >(logit);
	then
	  echo "Application exists"
	  if ! [[ $if_resource_exists_still_proceed ]]
          then
            exit 1
          fi
	else
	  #Add bitnami helm repo
	  helm repo add bitnami https://charts.bitnami.com/bitnami 1>> >(logit) 2>> >(logit)
          helm install my-wordpress bitnami/wordpress -n $backup_namespace 1>> >(logit) 2>> >(logit)
	  echo "Installing Application"
	  runtime="10 minute"
          spin='-\|/'
          i=0
          endtime=$(date -ud "$runtime" +%s)
	  while [[ $(date -u +%s) -le $endtime ]] && kubectl get pod -l  app.kubernetes.io/instance=my-wordpress -n $backup_namespace -o  jsonpath="{.items[*].status.conditions[*].status}" | grep -q False
          do
            i=$(( (i+1) %4 ))
            printf "\r %s" "${spin:$i:1}"
            sleep .1
          done 
	  if kubectl get pod -l  app.kubernetes.io/instance=my-wordpress -n $backup_namespace -o  jsonpath="{.items[*].status.conditions[*].status}" | grep -q False;then
            echo "Wordpress installation failed"
	    exit 1
	  fi
	  echo "Requested application is installed successfully"
	  yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml 1>> >(logit) 2>> >(logit)
	fi
	;;

      3)
        echo "MySQL operator will require enough resources, else the deployment will fail"
        helm repo add presslabs https://presslabs.github.io/charts 1>> >(logit) 2>> >(logit)
        errormessage=$(helm install mysql-operator presslabs/mysql-operator -n $backup_namespace 2>> >(logit))
        if echo "$errormessage"  | grep -Eq 'Error:|error:'; then
          echo "Mysql operator Installation failed with error: $errormessage"
          exit 1
        fi
        echo "Installing MySQL Operator..."
        runtime="10 minute"
        spin='-\|/'
        i=0
        endtime=$(date -ud "$runtime" +%s)
        while [[ $(date -u +%s) -le $endtime ]] && kubectl get pod -l app=mysql-operator -n $backup_namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep -q False
        do
          i=$(( (i+1) %4 ))
          printf "\r %s" "${spin:$i:1}"
          sleep .1
        done
        if kubectl get pod -l app=mysql-operator -n $backup_namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep -q False;then
          echo "MySQL operator installation failed"
          exit 1
        fi
        #Create a MySQL cluster
        kubectl apply -f https://raw.githubusercontent.com/bitpoke/mysql-operator/master/examples/example-cluster-secret.yaml -n $backup_namespace 2>> >(logit)
        kubectl apply -f https://raw.githubusercontent.com/bitpoke/mysql-operator/master/examples/example-cluster.yaml -n $backup_namespace 2>> >(logit)
        runtime="15 minute"
        spin='-\|/'
        i=0
        endtime=$(date -ud "$runtime" +%s)
        echo "Installing MySQL cluster..."
        sleep 10
        while [[ $(date -u +%s) -le $endtime ]] && kubectl get pods -l mysql.presslabs.org/cluster=my-cluster -n $backup_namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep -q False
        do
          i=$(( (i+1) %4 ))
          printf "\r %s" "${spin:$i:1}"
          sleep .1
        done
        if kubectl get pods -l mysql.presslabs.org/cluster=my-cluster -n $backup_namespace  -o  jsonpath="{.items[*].status.conditions[*].status}" | grep -q False;then
          echo "MySQL cluster installation failed"
          exit 1
        fi
	#Creating backupplan
	{
 	  yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml
          yq eval -i '.spec.backupPlanComponents.operators[0].operatorId="my-cluster"' backupplan.yaml
          yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.group="mysql.presslabs.org" | .spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.group style="double"' backupplan.yaml
          yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.version="v1alpha1" | .spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.version style="double"' backupplan.yaml
          yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.kind="MysqlCluster" | .spec.backupPlanComponents.operators[0].customResources[0].groupVersionKind.kind style="double"' backupplan.yaml
          yq eval -i '.spec.backupPlanComponents.operators[0].customResources[0].objects[0]="my-cluster"' backupplan.yaml
          yq eval -i '.spec.backupPlanComponents.operators[0].operatorResourceSelector[0].matchLabels.name="mysql-operator"' backupplan.yaml
	  yq eval -i '.spec.backupPlanComponents.operators[0].applicationResourceSelector[0].matchLabels.app="mysql-operator"' backupplan.yaml
        } 1>> >(logit) 2>> >(logit)
	;;
      4)
	if helm list -n $backup_namespace | grep -q -w mongotest
        then
          echo "Application exists"
          if ! [[ $if_resource_exists_still_proceed ]]
          then
            exit 1
          fi
        else
          {
	    helm repo add bitnami https://charts.bitnami.com/bitnami
            helm repo update 1>> >(logit)
            helm install mongotest bitnami/mongodb -n $backup_namespace
	  } 2>> >(logit)
	  echo "Installing App..."
	  runtime="15 minute"
          spin='-\|/'
          i=0
          endtime=$(date -ud "$runtime" +%s)
	  while [[ $(date -u +%s) -le $endtime ]] && kubectl get pod -l app.kubernetes.io/name=mongodb -n $backup_namespace -o  jsonpath="{.items[*].status.conditions[*].status}" | grep -w False
          do
            i=$(( (i+1) %4 ))
            printf "\r %s" "${spin:$i:1}"
            sleep .1
          done
	  if kubectl get pod -l app.kubernetes.io/name=mongodb -n $backup_namespace -o  jsonpath="{.items[*].status.conditions[*].stat}" | grep -q False;then
            echo "Mongodb installation failed"
            exit 1
          fi
	  echo "Requested application is installed successfully"
          yq eval -i 'del(.spec.backupPlanComponents)' backupplan.yaml 1>> >(logit) 2>> >(logit)
	  yq eval -i '.spec.backupPlanComponents.helmReleases[0]="mongotest"' backupplan.yaml 1>> >(logit) 2>> >(logit)
	fi
	;;
      *)
    	echo "Wrong choice"
        ;;
  esac
   #check if backupplan with same name already exists
   if [[ $(kubectl get backupplan $bk_plan_name  -n  $backup_namespace 2>/dev/null) ]];
      then
        echo "Backupplan with same name already exists"
        if ! [[ $if_resource_exists_still_proceed ]]
        then
          exit 1
        fi
   else
     #Applying backupplan manifest
     {
       yq eval -i '.metadata.name="'$bk_plan_name'"' backupplan.yaml
       yq eval -i '.metadata.namespace="'$backup_namespace'"' backupplan.yaml
       yq eval -i '.spec.backupNamespace="'$backup_namespace'"' backupplan.yaml
       yq eval -i '.spec.backupConfig.target.name="'"$target_name"'"' backupplan.yaml
       yq eval -i '.spec.backupConfig.target.namespace="'"$target_namespace"'"' backupplan.yaml
     } 1>> >(logit) 2>> >(logit)
     echo "Creating backupplan..."
     cat <<EOF | kubectl apply -f - 1>> >(logit) 2>> >(logit)
apiVersion: triliovault.trilio.io/v1
kind: Policy
metadata:
  name: sample-policy
spec:
  type: Retention
  default: false
  retentionConfig:
    latest: 30
    weekly: 7
    monthly: 30
EOF
     retcode=$?
     if [ "$retcode" -ne 0 ];then
       echo "Erro while applying policy"
       exit
     fi
     if ! kubectl apply -f backupplan.yaml -n $backup_namespace;then
          echo "Backupplan creation failed"
          exit 1
     fi
     cmd="kubectl get backupplan $bk_plan_name  -n  $backup_namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep -e Available -e Unavailable"
     wait_install "10 minute" "$cmd"
     if ! kubectl get backupplan $bk_plan_name  -n  $backup_namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep -q Available; then
       echo "Backupplan creation failed"
       exit 1
     else
       echo "Backupplan is in Available state"
     fi

   fi
   rm -f backupplan.yaml
   if [[ $(kubectl get backup $backup_name  -n  $backup_namespace 2>> >(logit)) ]];
      then
        echo "Backup with same name already exists"
        if ! [[ $if_resource_exists_still_proceed ]]
        then
          exit 1
        fi
   else
     echo "Creating Backup..."
     #Applying backup manifest
     cat <<EOF | kubectl apply -f - 1>> >(logit) 2>> >(logit)
apiVersion: triliovault.trilio.io/v1
kind: Backup
metadata:
  name: ${backup_name}
  namespace: ${backup_namespace}
spec:
  type: Full
  scheduleType: Periodic
  backupPlan:
    name: ${bk_plan_name}
    namespace: ${backup_namespace}
EOF
     retcode=$?
     if [ "$retcode" -ne 0 ];then
       echo "Error while creating backup"
       exit 1
     fi
     cmd="kubectl get backup $backup_name -n  $backup_namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep -e Available -e Failed"
     wait_install "60 minute" "$cmd"
     if ! kubectl get backup $backup_name -n $backup_namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep -w Available; then
       echo "Backup Failed"
       exit 1
     else
       echo "Backup is Available Now"
     fi
   fi
   if  [[ -z ${input_config} ]];then
     read -r -p "whether restore test should also be done?y/n: " restore
   fi
   if [[ ${restore} == "Y" ]] || [[ ${restore} == "y" ]] || [[ ${restore} == "True" ]]
   then
     if  [[ -z ${input_config} ]];then
       read -r -p "Restore Namepsace(trilio-test-rest): " restore_namespace
       read -r -p "Restore name(trilio-test-restore): " restore_name
     fi
     if [[ -z "$restore_namespace" ]]; then
	restore_namespace="trilio-test-rest"
     fi
     if ! kubectl create ns "$restore_namespace" 1>> >(logit) 2>> >(logit) 
     then 
       echo "Error while creating $restore_namespace namespace"
       exit 1
     fi  
     if [[ -z "$restore_name" ]]; then
	restore_name="trilio-test-restore"
     fi
     if [[ $(kubectl get restore $restore_name  -n  $restore_namespace 2>/dev/null) ]];
      then
        echo "Restore with same name already exists"
        if ! [[ $if_resource_exists_still_proceed ]]
        then
          exit 1
        fi
     else
     echo "Creating restore..."
     #Applying restore manifest
     cat <<EOF | kubectl apply -f - 1>> >(logit) 2>> >(logit)
apiVersion: triliovault.trilio.io/v1
kind: Restore
metadata:
  name: ${restore_name}
  namespace: ${restore_namespace}
spec:
  backupPlan:
    name: ${bk_plan_name}
  source:
    type: Backup
    backup:
      namespace: ${backup_name}
      name: ${backup_namespace}
    target:
      name: ${target_name}
      namespace: ${target_namespace}
  restoreNamespace: ${restore_namespace}
  skipIfAlreadyExists: true
EOF
       retcode=$?
       if [ "$retcode" -ne 0 ];then
         echo "Error while restoring"
	 exit 1
       fi
       cmd="kubectl get restore $restore_name -n $restore_namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep -e Completed -e Failed"
       wait_install "60 minute" "$cmd"
       if ! kubectl get restore $restore_name -n $restore_namespace -o 'jsonpath={.status.status}' 2>/dev/null | grep -w 'Completed'; then
         echo "Restore Failed"
         exit 1
       else
         echo "Restore is Completed"
       fi
     fi
   fi
}




print_usage(){
  echo "
--------------------------------------------------------------
tvk-oneclick - Installs, Configures UI, Create sample backup/restore test
Usage:
kubectl tvk-oneclick [options] [arguments]
Options:
        -h, --help                show brief help
        -n, --noninteractive      run script in non-interactive mode.for this you need to provide config file
        -i, --install_tvk         Installs TVK and it's free trial license.
        -c, --configure_ui        Configures TVK UI
        -t, --target              Created Target for backup and restore jobs
        -s, --sample_test         Create sample backup and restore jobs
	-p, --preflight           Checks if all the pre-requisites are satisfied
-----------------------------------------------------------------------
"
}

main()
{
  for i in "$@"; do
    #key="$1"
    case $i in
      -h|--help)
        print_usage
        exit 0
        ;;
      -n|--noninteractive)
        export Non_interact=True
        echo "Flag set to run cleanup in non-interactive mode"
        echo
        ;;
      -i|--install_tvk)
	export TVK_INSTALL=True
	#echo "Flag set to install TVK product"
	shift
	echo
	;;
      -c|--configure_ui)
	export CONFIGURE_UI=True
	#echo "flag set to configure ui"
	echo
	;;
      -t|--target)
	export TARGET=True
        #echo "flag set to create backup target"
	shift
	echo
	;;
      -s|--sample_test)
        export SAMPLE_TEST=True
	#echo "flag set to test sample  backup and restore of application "
	echo
	;;
      -p|--preflight)
	export PREFLIGHT=True
	echo
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
  export input_config=""
  if [ ${Non_interact} ]
  then
    read -r -p "Please enter path for config file: " input_config
    # shellcheck source=/dev/null
    . "$input_config"
    export input_config=$input_config
  fi
  if [[ ${PREFLIGHT} == 'True'  ]]
  then
    preflight_checks
  fi
  if [[ ${TVK_INSTALL} == 'True' ]]
  then  
    install_tvk
  fi
  if [[ ${CONFIGURE_UI} == 'True' ]]
  then
    configure_ui
  fi
  if [[ ${TARGET} == 'True' ]]
  then
    create_target   
  fi
  if [[ ${SAMPLE_TEST} == 'True' ]]
  then
    sample_test
  fi
    
}

logit() {
     # shellcheck disable=SC2162
    while read
    do
        printf "%(%Y-%m-%d %T)T %s\n" -1 "$REPLY"  >> "${LOG_FILE}"
    done
}

LOG_FILE="/tmp/tvk_oneclick_stderr"

# --- End Definitions Section ---
# check if we are being sourced by another script or shell
[[ "${#BASH_SOURCE[@]}" -gt "1" ]] && { return 0; }
# --- Begin Code Execution Section ---

main "$@"
