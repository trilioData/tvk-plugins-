package preflight

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	goexec "os/exec"

	version "github.com/hashicorp/go-version"
	"github.com/trilioData/tvk-plugins/internal"
	"github.com/trilioData/tvk-plugins/tools/preflight/exec"
	"github.com/trilioData/tvk-plugins/tools/preflight/wait"
	"k8s.io/client-go/discovery"

	corev1 "k8s.io/api/core/v1"
	k8serrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// RunOptions input options required for running preflight.
type RunOptions struct {
	StorageClass                string            `json:"storageClass"`
	SnapshotClass               string            `json:"snapshotClass,omitempty"`
	LocalRegistry               string            `json:"localRegistry,omitempty"`
	ImagePullSecret             string            `json:"imagePullSecret,omitempty"`
	ServiceAccountName          string            `json:"serviceAccount,omitempty"`
	PerformCleanupOnFail        bool              `json:"cleanupOnFailure,omitempty"`
	PVCStorageRequest           resource.Quantity `json:"pvcStorageRequest,omitempty"`
	corev1.ResourceRequirements `json:"resources,omitempty"`
	PodSchedOps                 podSchedulingOptions `json:"podSchedulingOptions"`
}

type Run struct {
	RunOptions
	CommonOptions
}

// CreateResourceNameSuffix creates a unique 6-length hash for preflight check.
// All resources name created during preflight will have hash as suffix
func CreateResourceNameSuffix() (string, error) {
	suffix := make([]byte, 6)
	randRange := big.NewInt(int64(len(letterBytes)))
	for i := range suffix {
		randNum, err := rand.Int(rand.Reader, randRange)
		if err != nil {
			return "", err
		}
		idx := randNum.Int64()
		suffix[i] = letterBytes[idx]
	}

	return string(suffix), nil
}

func (o *Run) logPreflightOptions() {
	o.Logger.Infof("====PREFLIGHT RUN OPTIONS====")
	o.CommonOptions.logCommonOptions()
	o.Logger.Infof("STORAGE-CLASS=\"%s\"", o.StorageClass)
	o.Logger.Infof("VOLUME-SNAPSHOT-CLASS=\"%s\"", o.SnapshotClass)
	o.Logger.Infof("LOCAL-REGISTRY=\"%s\"", o.LocalRegistry)
	o.Logger.Infof("IMAGE-PULL-SECRET=\"%s\"", o.ImagePullSecret)
	o.Logger.Infof("SERVICE-ACCOUNT=\"%s\"", o.ServiceAccountName)
	o.Logger.Infof("CLEANUP-ON-FAILURE=\"%v\"", o.PerformCleanupOnFail)
	o.Logger.Infof("POD CPU REQUEST=\"%s\"", o.ResourceRequirements.Requests.Cpu().String())
	o.Logger.Infof("POD MEMORY REQUEST=\"%s\"", o.ResourceRequirements.Requests.Memory().String())
	o.Logger.Infof("POD CPU LIMIT=\"%s\"", o.ResourceRequirements.Limits.Cpu().String())
	o.Logger.Infof("POD MEMORY LIMIT=\"%s\"", o.ResourceRequirements.Limits.Memory().String())
	o.Logger.Infof("PVC STORAGE REQUEST=\"%s\"", o.PVCStorageRequest.String())
	o.Logger.Infof("====PREFLIGHT RUN OPTIONS END====")
}

// PerformPreflightChecks performs all preflight checks.
func (o *Run) PerformPreflightChecks(ctx context.Context) error {
	o.logPreflightOptions()
	var err error
	preflightStatus := true
	resNameSuffix, err = CreateResourceNameSuffix()
	if err != nil {
		o.Logger.Errorf("Error generating resource name suffix :: %s", err.Error())
		return err
	}
	storageSnapshotSuccess := true

	o.Logger.Infof("Generated UID for preflight check - %s\n", resNameSuffix)

	//  check kubectl
	o.Logger.Infoln("Checking for kubectl")
	err = o.checkKubectl(kubectlBinaryName)
	if err != nil {
		o.Logger.Errorf("%s Preflight check for kubectl utility failed :: %s\n", cross, err.Error())
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for kubectl utility is successful\n", check)
	}

	o.Logger.Infoln("Checking access to the default namespace of cluster")
	err = o.checkClusterAccess(ctx)
	if err != nil {
		o.Logger.Errorf("%s Preflight check for cluster access failed :: %s\n", cross, err.Error())
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for kubectl access is successful\n", check)
	}

	o.Logger.Infof("Checking for required Helm version (>= %s)\n", MinHelmVersion)
	err = o.checkHelmVersion(HelmBinaryName)
	if err != nil {
		o.Logger.Errorf("%s Preflight check for helm version failed :: %s\n", cross, err.Error())
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for helm version is successful\n", check)
	}

	o.Logger.Infof("Checking for required kubernetes server version (>=%s)\n", MinK8sVersion)
	err = o.checkKubernetesVersion(MinK8sVersion)
	if err != nil {
		o.Logger.Errorf("%s Preflight check for kubernetes version failed :: %s\n", cross, err.Error())
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for kubernetes version is successful\n", check)
	}

	o.Logger.Infoln("Checking Kubernetes RBAC")
	err = o.checkKubernetesRBAC(RBACAPIGroup, RBACAPIVersion)
	if err != nil {
		o.Logger.Errorf("%s Preflight check for kubernetes RBAC failed :: %s\n", cross, err.Error())
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for kubernetes RBAC is successful\n", check)
	}

	//  Check storage snapshot class
	o.Logger.Infoln("Checking if a StorageClass and VolumeSnapshotClass are present")
	err = o.checkStorageSnapshotClass(ctx)
	if err != nil {
		o.Logger.Errorf("%s Preflight check for SnapshotClass failed :: %s\n", cross, err.Error())
		storageSnapshotSuccess = false
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for SnapshotClass is successful\n", check)
	}

	//  Check CSI installation
	o.Logger.Infoln("Checking if CSI APIs are installed in the cluster")
	err = o.checkCSI(ctx)
	if err != nil {
		o.Logger.Errorf("Preflight check for CSI failed :: %s\n", err.Error())
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for CSI is successful\n", check)
	}

	//  Check DNS resolution
	o.Logger.Infoln("Checking if DNS resolution is working in k8s cluster")
	err = o.checkDNSResolution(ctx, execDNSResolutionCmd, resNameSuffix)
	if err != nil {
		o.Logger.Errorf("%s Preflight check for DNS resolution failed :: %s\n", cross, err.Error())
		preflightStatus = false
	} else {
		o.Logger.Infof("%s Preflight check for DNS resolution is successful\n", check)
	}

	//  Check volume snapshot and restore
	if storageSnapshotSuccess {
		o.Logger.Infoln("Checking if volume snapshot and restore is enabled in cluster")
		err = o.checkVolumeSnapshot(ctx, resNameSuffix)
		if err != nil {
			o.Logger.Errorf("%s Preflight check for volume snapshot and restore failed :: %s\n", cross, err.Error())
			preflightStatus = false
		} else {
			o.Logger.Infof("%s Preflight check for volume snapshot and restore is successful\n", check)
		}
	} else {
		o.Logger.Errorf("Skipping volume snapshot and restore check as preflight check for SnapshotClass failed")
	}

	co := &Cleanup{
		CommonOptions: CommonOptions{
			Kubeconfig: o.Kubeconfig,
			Namespace:  o.Namespace,
			Logger:     o.Logger,
		},
		CleanupOptions: CleanupOptions{
			UID: resNameSuffix,
		},
	}
	if !preflightStatus {
		o.Logger.Warnln("Some preflight checks failed")
	} else {
		o.Logger.Infoln("All preflight checks succeeded!")
	}
	if preflightStatus || o.PerformCleanupOnFail {
		err = co.CleanupPreflightResources(ctx)
		if err != nil {
			o.Logger.Errorf("%s Failed to cleanup preflight resources :: %s\n", cross, err.Error())
		}
	}

	if !preflightStatus {
		return fmt.Errorf("some preflight checks failed. Check logs for more details")
	}

	return nil
}

// checkKubectl checks whether kubectl utility is installed.
func (o *Run) checkKubectl(binaryName string) error {
	path, err := goexec.LookPath(binaryName)
	if err != nil {
		return fmt.Errorf("error finding '%s' binary in $PATH of the system :: %s", binaryName, err.Error())
	}
	o.Logger.Infof("kubectl found at path - %s\n", path)

	return nil
}

// checkClusterAccess Checks whether access to kubectl utility is present on the client machine.
func (o *Run) checkClusterAccess(ctx context.Context) error {
	_, err := clientSet.CoreV1().Namespaces().Get(ctx, internal.DefaultNs, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("unable to access default namespace of cluster :: %s", err.Error())
	}

	return nil
}

// checkHelmVersion checks whether minimum helm version is present.
func (o *Run) checkHelmVersion(binaryName string) error {
	err := o.validateHelmBinary(binaryName)
	if err != nil {
		return err
	}

	curVersion, err := GetHelmVersion(HelmBinaryName)
	if err != nil {
		return err
	}
	return o.validateHelmVersion(curVersion)
}

func (o *Run) validateHelmVersion(curVersion string) error {
	helmVersion, err := GetHelmVersion(HelmBinaryName)
	if err != nil {
		return err
	}
	v1, err := version.NewVersion(MinHelmVersion)
	if err != nil {
		return err
	}
	v2, err := version.NewVersion(curVersion)
	if err != nil {
		return err
	}
	if v2.LessThan(v1) {
		return fmt.Errorf("helm does not meet minimum version requirement.\nUpgrade helm to minimum version - %s", MinHelmVersion)
	}

	o.Logger.Infof("%s Helm version %s meets required version\n", check, helmVersion)

	return nil
}

func (o *Run) validateHelmBinary(binaryName string) error {
	if internal.CheckIsOpenshift(discClient, internal.OcpAPIVersion) {
		o.Logger.Infof("%s Running OCP cluster. Helm not needed for OCP clusters\n", check)
		return nil
	}
	o.Logger.Infof("APIVersion - %s not found on cluster, not an OCP cluster\n", internal.OcpAPIVersion)
	// check whether helm exists
	path, err := goexec.LookPath(binaryName)
	if err != nil {
		return fmt.Errorf("error finding '%s' binary in $PATH of the system :: %s", binaryName, err.Error())
	}
	o.Logger.Infof("helm found at path - %s\n", path)
	return nil
}

// checkKubernetesVersion checks whether minimum k8s version requirement is met
func (o *Run) checkKubernetesVersion(minVersion string) error {
	serverVer, err := clientSet.ServerVersion()
	if err != nil {
		return err
	}

	v1, err := version.NewVersion(minVersion)
	if err != nil {
		return err
	}
	v2, err := version.NewVersion(serverVer.GitVersion)
	if err != nil {
		return err
	}
	if v2.LessThan(v1) {
		return fmt.Errorf("kubernetes server version does not meet minimum requirements")
	}

	return nil
}

// checkKubernetesRBAC fetches the apiVersions present on k8s server.
// And checks whether api group and version are present.
// 'ExtractGroupVersions' func call is taken from kubectl mirror repo.
func (o *Run) checkKubernetesRBAC(apiGroup, apiVersion string) error {
	groupList, err := discClient.ServerGroups()
	if err != nil {
		if !discovery.IsGroupDiscoveryFailedError(err) {
			o.Logger.Errorf("Unable to fetch groups from server :: %s\n", err.Error())
			return err
		}
		o.Logger.Warnf("The Kubernetes server has an orphaned API service. Server reports: %s\n", err.Error())
		o.Logger.Warnln("To fix this, kubectl delete api service <service-name>")
	}
	apiVersions := metav1.ExtractGroupVersions(groupList)
	found := false
	for _, apiver := range apiVersions {
		gv, err := schema.ParseGroupVersion(apiver)
		if err != nil {
			return nil
		}
		if gv.Group == apiGroup && gv.Version == apiVersion {
			found = true
			o.Logger.Infof("%s Kubernetes RBAC is enabled\n", check)
			break
		}
	}
	if !found {
		return fmt.Errorf("not enabled kubernetes RBAC")
	}

	return nil
}

// checkStorageSnapshotClass checks whether storageclass is present.
// Checks whether storageclass and volumesnapshotclass provisioner are same.
func (o *Run) checkStorageSnapshotClass(ctx context.Context) error {
	sc, err := clientSet.StorageV1().StorageClasses().Get(ctx, o.StorageClass, metav1.GetOptions{})
	if err != nil {
		if k8serrors.IsNotFound(err) {
			return fmt.Errorf("not found storageclass - %s on cluster", o.StorageClass)
		}
		return err
	}
	o.Logger.Infof("%s Storageclass - %s found on cluster\n", check, o.StorageClass)
	provisioner := sc.Provisioner
	if o.SnapshotClass == "" {
		storageVolSnapClass, err = o.checkSnapshotclassForProvisioner(ctx, provisioner)
		if err != nil {
			o.Logger.Errorf("%s %s\n", cross, err.Error())
			return err
		}
		o.Logger.Infof("%s Extracted volume snapshot class - %s found in cluster", check, storageVolSnapClass)
		o.Logger.Infof("%s Volume snapshot class - %s driver matches with given StorageClass's provisioner=%s\n",
			check, storageVolSnapClass, provisioner)
	} else {
		storageVolSnapClass = o.SnapshotClass
		vssc, err := clusterHasVolumeSnapshotClass(ctx, o.SnapshotClass, runtimeClient)
		if err != nil {
			o.Logger.Errorf("%s %s\n", cross, err.Error())
			return err
		}
		if vssc.Object["driver"] == provisioner {
			o.Logger.Infof("%s Volume snapshot class - %s driver matches with given storage class provisioner\n", check, o.SnapshotClass)
		} else {
			return fmt.Errorf("volume snapshot class - %s "+
				"driver does not match with given StorageClass's provisioner=%s", o.SnapshotClass, provisioner)
		}
	}

	return nil
}

//  checkSnapshotclassForProvisioner checks whether snapshot-class exist for a provisioner
func (o *Run) checkSnapshotclassForProvisioner(ctx context.Context, provisioner string) (string, error) {
	var (
		prefVersion string
		err         error
	)
	prefVersion, err = GetServerPreferredVersionForGroup(StorageSnapshotGroup, clientSet)
	if err != nil {
		return "", err
	}

	vsscList := unstructured.UnstructuredList{}
	vsscList.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   StorageSnapshotGroup,
		Version: prefVersion,
		Kind:    internal.VolumeSnapshotClassKind,
	})
	err = runtimeClient.List(ctx, &vsscList)
	if err != nil {
		return "", err
	} else if len(vsscList.Items) == 0 {
		return "", fmt.Errorf("no volume snapshot class for APIVersion - %s/%s found on cluster",
			StorageSnapshotGroup, prefVersion)
	}

	sscName := ""
	for _, vssc := range vsscList.Items {
		if vssc.Object["driver"] == provisioner {
			if vssc.Object["snapshot.storage.kubernetes.io/is-default-class"] == "true" {
				return vssc.GetName(), nil
			}
			sscName = vssc.GetName()
		}
	}
	if sscName == "" {
		return "", fmt.Errorf("no matching volume snapshot class having driver "+
			"same as provisioner - %s found on cluster", provisioner)
	}

	o.Logger.Infof("volume snapshot class having driver "+
		"same as provisioner - %s found on cluster for version - %s", provisioner, prefVersion)
	return sscName, nil
}

//  checkCSI checks whether CSI APIs are installed in the k8s cluster
func (o *Run) checkCSI(ctx context.Context) error {
	prefVersion, err := GetServerPreferredVersionForGroup(apiExtenstionsGroup, clientSet)
	if err != nil {
		return err
	}
	var apiFoundCnt = 0
	u := &unstructured.Unstructured{}
	u.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   apiExtenstionsGroup,
		Version: prefVersion,
		Kind:    customResourceDefinition,
	})
	for _, api := range CsiApis {
		err := runtimeClient.Get(ctx, client.ObjectKey{Name: api}, u)
		if err != nil && !k8serrors.IsNotFound(err) {
			return err
		} else if k8serrors.IsNotFound(err) {
			o.Logger.Errorf("%s Not found CSI API - %s\n", cross, api)
		} else {
			o.Logger.Infof("%s Found CSI API - %s on cluster\n", check, api)
			apiFoundCnt++
		}
	}

	if apiFoundCnt != len(CsiApis) {
		return fmt.Errorf("some CSI APIs not found in cluster. Check logs for details")
	}
	return nil
}

//  checkDNSResolution checks whether DNS resolution is working on k8s cluster
func (o *Run) checkDNSResolution(ctx context.Context, execCommand []string, podNameSuffix string) error {
	pod := createDNSPodSpec(o, podNameSuffix)
	_, err := clientSet.CoreV1().Pods(o.Namespace).Create(ctx, pod, metav1.CreateOptions{})
	if err != nil {
		return err
	}
	o.Logger.Infof("Pod %s created in cluster\n", pod.GetName())

	waitOptions := &wait.PodWaitOptions{
		Name:      pod.GetName(),
		Namespace: o.Namespace,
		RetryBackoffParams: getDefaultRetryBackoffParams(),
		PodCondition:       corev1.PodReady,
		ClientSet:          clientSet,
	}
	o.Logger.Infoln("Waiting for dns pod to become ready")
	err = waitUntilPodCondition(ctx, waitOptions)
	if err != nil {
		o.Logger.Errorf("DNS pod - %s hasn't reached into ready state", pod.GetName())
		return err
	}

	pod, err = clientSet.CoreV1().Pods(o.Namespace).Get(ctx, pod.GetName(), metav1.GetOptions{})
	if err != nil {
		return err
	}
	logPodScheduleStmt(pod, o.Logger)

	op := exec.Options{
		Namespace: o.Namespace,
		//Command:       []string{"nslookup", "kubernetes.default"},
		Command:       execCommand,
		PodName:       pod.GetName(),
		ContainerName: dnsContainerName,
		Executor:      &exec.DefaultRemoteExecutor{},
		Config:        restConfig,
		ClientSet:     clientSet,
	}
	err = execInPod(&op, o.Logger)
	if err != nil {
		return fmt.Errorf("not able to resolve DNS '%s' service inside pods", execCommand[1])
	}

	// Delete DNS pod when resolution is successful
	err = deleteK8sResource(ctx, pod)
	if err != nil {
		o.Logger.Warnf("Problem occurred deleting DNS pod - '%s' :: %s", pod.GetName(), err.Error())
	} else {
		o.Logger.Infof("Deleted DNS pod - '%s' successfully", pod.GetName())
	}

	return nil
}

// checkVolumeSnapshot checks if volume snapshot and restore is enabled in the cluster
func (o *Run) checkVolumeSnapshot(ctx context.Context, nameSuffix string) error {
	var (
		execOp exec.Options
		err    error
	)

	// create source pod, pvc and volume snapshot
	pvc, srcPod, err := o.createSourcePodAndPVC(ctx, nameSuffix)
	if err != nil {
		return err
	}
	volSnap, err := o.createSnapshotFromPVC(ctx, VolumeSnapSrcNamePrefix+nameSuffix,
		storageVolSnapClass, pvc.GetName(), nameSuffix)
	if err != nil {
		return err
	}

	// create restore pod, pvc from source snapshot
	restorePod, err := o.createRestorePodFromSnapshot(ctx, volSnap,
		RestorePvcNamePrefix+nameSuffix, RestorePodNamePrefix+nameSuffix, nameSuffix)
	if err != nil {
		return err
	}
	execOp = exec.Options{
		Namespace:     o.Namespace,
		Command:       execRestoreDataCheckCommand,
		PodName:       restorePod.GetName(),
		ContainerName: restorePod.Spec.Containers[0].Name,
		Executor:      &exec.DefaultRemoteExecutor{},
		Config:        restConfig,
		ClientSet:     clientSet,
	}
	err = execInPod(&execOp, o.Logger)
	if err != nil {
		return err
	}
	o.Logger.Infof("Restored pod - %s has expected data\n", restorePod.GetName())

	// remove source pod
	srcPodName := srcPod.GetName()
	srcPod, err = clientSet.CoreV1().Pods(o.Namespace).Get(ctx, srcPod.GetName(), metav1.GetOptions{})
	if err != nil {
		return err
	}
	o.Logger.Infof("Deleting source pod - %s\n", srcPod.GetName())
	err = deleteK8sResource(ctx, srcPod)
	if err != nil {
		return err
	}
	o.Logger.Infof("Deleted source pod - %s\n", srcPodName)

	// create unmounted pod, pvc and  snapshot from source pvc
	unmountedVolSnapSrc, err := o.createSnapshotFromPVC(ctx, UnmountedVolumeSnapSrcNamePrefix+nameSuffix,
		storageVolSnapClass, pvc.GetName(), nameSuffix)
	if err != nil {
		return err
	}
	unmountedPodSpec, err := o.createRestorePodFromSnapshot(ctx, unmountedVolSnapSrc,
		UnmountedRestorePvcNamePrefix+nameSuffix, UnmountedRestorePodNamePrefix+nameSuffix, nameSuffix)
	if err != nil {
		return err
	}
	execOp.PodName = unmountedPodSpec.GetName()
	execOp.ContainerName = unmountedPodSpec.Spec.Containers[0].Name
	err = execInPod(&execOp, o.Logger)
	if err != nil {
		return err
	}
	o.Logger.Infof("%s restored pod from volume snapshot of unmounted pv has expected data\n", check)

	return nil
}

// createSourcePodAndPVC creates source pod and pvc for volume snapshot check
func (o *Run) createSourcePodAndPVC(ctx context.Context, nameSuffix string) (*corev1.PersistentVolumeClaim, *corev1.Pod, error) {
	var err error
	pvc := createVolumeSnapshotPVCSpec(o, SourcePvcNamePrefix+nameSuffix, nameSuffix)
	pvc, err = clientSet.CoreV1().PersistentVolumeClaims(o.Namespace).Create(ctx, pvc, metav1.CreateOptions{})
	if err != nil {
		return nil, nil, err
	}
	o.Logger.Infof("Created source pvc - %s", pvc.GetName())
	srcPod := createVolumeSnapshotPodSpec(pvc.GetName(), o, nameSuffix)
	srcPod, err = clientSet.CoreV1().Pods(o.Namespace).Create(ctx, srcPod, metav1.CreateOptions{})
	if err != nil {
		o.Logger.Errorln(err.Error())
		return pvc, nil, err
	}
	o.Logger.Infof("Created source pod - %s", srcPod.GetName())

	//  Wait for snapshot pod to become ready.
	waitOptions := &wait.PodWaitOptions{
		Name:      srcPod.GetName(),
		Namespace: o.Namespace,
		RetryBackoffParams: getDefaultRetryBackoffParams(),
		PodCondition:       corev1.PodReady,
		ClientSet:          clientSet,
	}
	o.Logger.Infof("Waiting for source pod - %s to become ready\n", srcPod.GetName())
	err = waitUntilPodCondition(ctx, waitOptions)
	if err != nil {
		return pvc, srcPod, fmt.Errorf("pod %s hasn't reached into ready state", srcPod.GetName())
	}
	o.Logger.Infof("Source pod - %s has reached into ready state\n", srcPod.GetName())

	srcPod, err = clientSet.CoreV1().Pods(o.Namespace).Get(ctx, srcPod.GetName(), metav1.GetOptions{})
	if err != nil {
		return pvc, srcPod, err
	}
	logPodScheduleStmt(srcPod, o.Logger)

	return pvc, srcPod, err
}

func (o *Run) createSnapshotFromPVC(ctx context.Context, volSnapName,
	volSnapClass, pvcName, uid string) (*unstructured.Unstructured, error) {
	snapshotVer, err := GetServerPreferredVersionForGroup(StorageSnapshotGroup, clientSet)
	if err != nil {
		o.Logger.Errorln(err.Error())
		return nil, err
	}
	volSnap := createVolumeSnapsotSpec(volSnapName, volSnapClass, o.Namespace, snapshotVer, pvcName, uid)
	if err = runtimeClient.Create(ctx, volSnap); err != nil {
		return nil, fmt.Errorf("%s error creating volume snapshot from pvc :: %s", cross, err.Error())
	}
	o.Logger.Infof("Created volume snapshot - %s from pvc", volSnap.GetName())

	o.Logger.Infof("Waiting for volume snapshot - %s created from pvc to become 'readyToUse:true'", volSnap.GetName())
	err = waitUntilVolSnapReadyToUse(volSnap, snapshotVer, getDefaultRetryBackoffParams())
	if err != nil {
		return nil, err
	}
	o.Logger.Infof("%s volume snapshot - %s is ready-to-use", check, volSnap.GetName())

	return volSnap, err
}

func (o *Run) createRestorePodFromSnapshot(ctx context.Context, volSnapshot *unstructured.Unstructured,
	pvcName, podName, uid string) (*corev1.Pod, error) {
	var err error
	restorePVC := createRestorePVCSpec(pvcName, volSnapshot.GetName(), uid, o)
	restorePVC, err = clientSet.CoreV1().PersistentVolumeClaims(o.Namespace).
		Create(ctx, restorePVC, metav1.CreateOptions{})
	if err != nil {
		o.Logger.Errorln(err.Error())
		return nil, err
	}
	o.Logger.Infof("Created restore pvc - %s from volume snapshot - %s\n", restorePVC.GetName(), volSnapshot.GetName())
	restorePod := createRestorePodSpec(podName, restorePVC.GetName(), uid, o)
	restorePod, err = clientSet.CoreV1().Pods(o.Namespace).
		Create(ctx, restorePod, metav1.CreateOptions{})
	if err != nil {
		o.Logger.Errorln(err.Error())
		return nil, err
	}
	o.Logger.Infof("Created restore pod - %s\n", restorePod.GetName())

	//  Wait for snapshot pod to become ready.
	waitOptions := &wait.PodWaitOptions{
		Name:      restorePod.GetName(),
		Namespace: o.Namespace,
		RetryBackoffParams: getDefaultRetryBackoffParams(),
		PodCondition:       corev1.PodReady,
		ClientSet:          clientSet,
	}
	o.Logger.Infof("Waiting for restore pod - %s to become ready\n", restorePod.GetName())
	waitOptions.Name = restorePod.GetName()
	err = waitUntilPodCondition(ctx, waitOptions)
	if err != nil {
		return nil, err
	}
	o.Logger.Infof("%s Restore pod - %s has reached into ready state\n", check, restorePod.GetName())

	restorePod, err = clientSet.CoreV1().Pods(o.Namespace).Get(ctx, restorePod.GetName(), metav1.GetOptions{})
	if err != nil {
		return nil, err
	}
	logPodScheduleStmt(restorePod, o.Logger)

	return restorePod, nil
}
