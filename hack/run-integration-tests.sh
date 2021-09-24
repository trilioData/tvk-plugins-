#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -x

COMPONENTS=("$@")

export STORAGE_CLASS="csi-gce-pd"
export APP_SCOPE="Namespaced"
export JOB_TYPE="github-actions"

cleanup() {
  local rc=$?

  # cleanup namespaces and helm release
  #shellcheck disable=SC2143
  if [[ $(helm list -n "${INSTALL_NAMESPACE}" | grep "${INSTALL_NAMESPACE}") ]]; then
    helm delete "${HELM_RELEASE_NAME}" --namespace "${INSTALL_NAMESPACE}"
  fi

  kubectl get validatingwebhookconfigurations -A | grep "${INSTALL_NAMESPACE}" | awk '{print $1}' | xargs -r kubectl delete validatingwebhookconfigurations || true
  kubectl get mutatingwebhookconfigurations -A | grep "${INSTALL_NAMESPACE}" | awk '{print $1}' | xargs -r kubectl delete mutatingwebhookconfigurations || true

  # NOTE: need sleep for resources to be garbage collected by api-controller
  sleep 20

  kubectl delete ns "${INSTALL_NAMESPACE}" --request-timeout 2m || true

  kubectl get po,rs,deployment,pvc,svc,sts,cm,secret,sa,role,rolebinding,job,target,backup,backupplan,policy,restore,cronjob -n "${INSTALL_NAMESPACE}" || true

  kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -A | grep -E "${INSTALL_NAMESPACE}" || true

  exit ${rc}
}

prepare_namespaces() {
  # shellcheck disable=SC2154
  install_ns="${JOB_TYPE}"-"${build_id}"
  kubectl create namespace "${install_ns}"

  # shellcheck disable=SC2154
  kubectl label namespace "${install_ns}" trilio-label="${install_ns}" job-name="${job_name}" job-type=${JOB_TYPE}

  helm_release_name="triliovault-${install_ns}"

  export INGRESS_HOST="${install_ns}.k8s-tvk.com"
  export INSTALL_NAMESPACE="${install_ns}"
  export BACKUP_NAMESPACE="${install_ns}"
  export HELM_RELEASE_NAME="${helm_release_name}"
}

helm_install() {

  install_namespace=${INSTALL_NAMESPACE}

  echo "Installing TVK application in namespace - ${install_namespace}"

  common_args="applicationScope=Namespaced"
  resources_args="web-backend.resources.limits.memory=1024Mi,web-backend.livenessProbeEnable=false,web-backend.resources.requests.memory=10Mi,control-plane.resources.limits.memory=1024Mi"
  ARGS="imagePullPolicy=Always,${common_args},${resources_args}"

  DEV_REPO="http://charts.k8strilio.net/trilio-dev/k8s-triliovault"
  helm repo add k8s-triliovault-dev "${DEV_REPO}"

  helm install --debug "${HELM_RELEASE_NAME}" --namespace "${install_namespace}" --set "${ARGS}" k8s-triliovault-dev/k8s-triliovault --wait --timeout=10m

  kubectl patch svc k8s-triliovault-ingress-gateway -p '{"spec": {"type": "LoadBalancer"}}' -n "${install_namespace}"
  node_external_ip=""
  SECONDS=0
  while [[ -z "$node_external_ip" && ($SECONDS -le 300) ]]; do
    node_external_ip=$(kubectl get svc k8s-triliovault-ingress-gateway -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' -n "${install_namespace}")
    sleep 5
  done
  if [[ -n "${node_external_ip}" ]]; then
    sudo -- bash -c "echo \"${node_external_ip} ${INGRESS_HOST}\" >>/etc/hosts"
  else
    exit 1
  fi

}

run_tests() {
  components=("$@")

  # will be required to run test-cases
  sudo apt-get install -y nfs-common

  GO111MODULE=off go get -u github.com/onsi/ginkgo/ginkgo
  ginkgo -r -keepGoing "${components[@]}"
}

trap "cleanup" EXIT

# change permission of kubeconfig file to suppress it's warning
sudo chmod 600 "${KUBECONFIG}"

prepare_namespaces
helm_install

run_tests "${COMPONENTS[@]}"
