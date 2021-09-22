#!/usr/bin/env bash

create_vcluster()
{
  JOB_NAME=$1
  install_ns=$2
  sudo curl -L -o /usr/local/bin/vcluster https://github.com/loft-sh/vcluster/releases/download/v0.4.0-beta.1/vcluster-linux-amd64 \
    && sudo chmod +x /usr/local/bin/vcluster
  vcluster create "${JOB_NAME}" -n "${install_ns}" -f tests/tvk-oneclick/vcluster.yaml
  ## Connect vcluster
  sleep 120
  vcluster connect "${JOB_NAME}"  -n "${install_ns}" --update-current > /dev/null 2>&1 & disown
  sleep 120
  kubectl config use-context "vcluster_${install_ns}_${JOB_NAME}"
  retcode=$?
  if [ $retcode -ne 0 ];then
    echo "Cannot change context, please check create_cluster"
    exit 1
  fi
  kubectl get ns
  echo "vcluster setup is activated."

  ## Install CSI CRDs
  kubectl apply -f tests/tvk-oneclick/csi-crd.yaml
  echo "csi crds installation is completed."

  ## Fix for random api server failure
  kubectl rollout restart deployment coredns --namespace kube-system
  sleep 30
}

create_vcluster "$1" "$2"
