package targetbrowsertest

// nolint // ignore dot import lint errors
import (
	"context"
	cryptorand "crypto/rand"
	"fmt"
	"io/ioutil"
	"math/big"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/api/networking/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	. "github.com/onsi/gomega"
	log "github.com/sirupsen/logrus"

	"github.com/trilioData/tvk-plugins/internal"
	"github.com/trilioData/tvk-plugins/internal/utils/shell"
)

const (
	timeout         = time.Second * 300
	interval        = time.Second * 1
	apiRetryTimeout = time.Second * 5

	NFSServerIP               = "nfs_server_ip"
	NFSServerBasePath         = "NFS_SERVER_BASE_PATH"
	ControlPlaneContainerName = "triliovault-control-plane"
	TargetBrowserDataPath     = "/src/nfs/targetbrowsertesting"
	InstallNamespace          = "INSTALL_NAMESPACE"
	TargetName                = "sample-target"
	TargetLocation            = "/triliodata"
	TargetBrowserDir          = "target-browser_linux_amd64"
	TargetBrowserBinaryName   = "target-browser"
	DistDir                   = "dist"
	PollingPeriod             = "POLLING_PERIOD"
	kubernetesInstanceKey     = "app.kubernetes.io/instance"
)

var (
	NfsIPAddress    = getNFSIPAddr()
	randomDirectory string
)

func getInstallNamespace() string {
	namespace, present := os.LookupEnv(InstallNamespace)
	if !present {
		panic("Install Namespace not found in environment")
	}
	return namespace
}
func getNFSIPAddr() string {
	nfsIPAddr, isNFSIPAddrPresent := os.LookupEnv(NFSServerIP)
	if !isNFSIPAddrPresent {
		panic("NFS IP address not found in environment.")
	}
	return nfsIPAddr
}
func generateRandomString(n int, isOnlyAlphabetic bool) string {
	letters := "abcdefghijklmnopqrstuvwxyz"
	numbers := "1234567890"
	rand.Seed(time.Now().UnixNano())
	letterRunes := []rune(letters)
	if !isOnlyAlphabetic {
		letterRunes = []rune(letters + numbers)
	}
	b := make([]rune, n)
	for i := range b {
		randNum, _ := cryptorand.Int(cryptorand.Reader, big.NewInt(int64(len(letterRunes))))
		b[i] = letterRunes[randNum.Int64()]
	}
	return string(b)
}

func unMountTarget() {
	c := fmt.Sprintf("sudo umount %s", TargetLocation)
	command := exec.Command("bash", "-c", c)
	_, err := command.CombinedOutput()
	if err != nil {
		log.Errorf("error %s", err.Error())
	}
	Expect(err).NotTo(HaveOccurred())
}

func makeRandomDirAndMount() {

	var err error
	randomDirectory = generateRandomString(5, false)

	// making directory of random name
	err = os.MkdirAll(filepath.Join(TargetLocation, randomDirectory), 0777)
	Expect(err).To(BeNil())
	_, err = shell.ChmodR(filepath.Join(TargetLocation, randomDirectory), "777")
	Expect(err).To(BeNil())
	log.Info("directory created:", randomDirectory)

	// unmounting from default target path
	unMountTarget()
	log.Info("unmounted from default path")

	time.Sleep(time.Second * 10)

	// setting "NFS_SERVER_BASE_PATH" to newly formed directory and mounting to it
	Expect(os.Setenv(NFSServerBasePath, filepath.Join(TargetBrowserDataPath, randomDirectory))).To(BeNil())
	mountTarget()
	log.Info("mounted to new path")
	Expect(err).To(BeNil())

	time.Sleep(time.Second * 20)
}

func mountTarget() {
	targetBrowserPath := os.Getenv(NFSServerBasePath)
	c := fmt.Sprintf("sudo mount -t nfs -o  nfsvers=4 %s:%s %s", NfsIPAddress, targetBrowserPath, TargetLocation)
	fmt.Printf("Mount command %s\n", c)
	command := exec.Command("bash", "-c", c)
	_, err := command.CombinedOutput()
	if err != nil {
		log.Errorf("error %s", err.Error())
	}
	Expect(err).NotTo(HaveOccurred())

}

func removeRandomDirAndUnmount() {

	// unmounting from random named directory
	unMountTarget()
	log.Info("unmounted from random named directory ", randomDirectory)

	time.Sleep(time.Second * 10)

	// setting "NFS_SERVER_BASE_PATH" to default target path and mounting to it
	Expect(os.Setenv(NFSServerBasePath, TargetBrowserDataPath)).To(BeNil())
	mountTarget()
	log.Info("mounted to default path")

	time.Sleep(time.Second * 10)

	// removing random named directory
	_, err := shell.RmRf(filepath.Join(TargetLocation, randomDirectory))
	Expect(err).To(BeNil())
	log.Info("removed directory")
}

func verifyBackupPlansAndBackupsOnNFS(backupPlans, backups int) (backupPlanUIDs []string) {

	var (
		err                        error
		tempBackupUIDs, backupUIDs []string
	)

	Eventually(func() []string {
		return InterceptGomegaFailures(func() {
			backupPlanUIDs, err = shell.ReadChildDir(TargetLocation)
			Expect(err).To(BeNil())
			log.Info(len(backupPlanUIDs), " backupplans present on target location")
			Expect(len(backupPlanUIDs)).To(Equal(backupPlans))
		})
	}, timeout, interval).Should(BeEmpty())

	Eventually(func() []string {
		return InterceptGomegaFailures(func() {
			for i := range backupPlanUIDs {
				tempBackupUIDs, err = shell.ReadChildDir(TargetLocation + "/" + backupPlanUIDs[i])
				Expect(err).To(BeNil())
				backupUIDs = append(backupUIDs, tempBackupUIDs...)
			}
			log.Info(len(backupUIDs), " backups present on target location")
			Expect(len(backupUIDs)).To(Equal(backups))
		})
	}, timeout, interval).Should(BeEmpty())

	return backupPlanUIDs

}

func getTarget(ctx context.Context, installNs string, cl client.Client) *unstructured.Unstructured {
	// get target
	target := &unstructured.Unstructured{}
	target.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   internal.TriliovaultGroup,
		Version: internal.V1Version,
		Kind:    internal.TargetKind,
	})

	Eventually(func() error {
		log.Infof("Getting target %s namespace %s", TargetName, installNs)
		err := cl.Get(ctx, types.NamespacedName{Namespace: installNs, Name: TargetName},
			target)
		return err
	}, timeout, interval).Should(Not(HaveOccurred()))
	return target
}

func verifyTargetBrowsingEnabled(ctx context.Context, installNs string, cl client.Client) {
	Eventually(func() bool {
		target := getTarget(ctx, installNs, cl)
		browsingEnabled, _, err := unstructured.NestedBool(target.Object, "status", "browsingEnabled")
		Expect(err).To(BeNil())
		log.Infof("Wait till target browsing is enabled - current status=%v", browsingEnabled)
		return browsingEnabled
	}, timeout, interval).Should(BeTrue())

	log.Info("target browsing is enabled successfully")
}

func verifyTargetStatus(ctx context.Context, installNs string, cl client.Client) {
	// get target
	Eventually(func() bool {
		target := getTarget(ctx, installNs, cl)
		targetStatus, _, err := unstructured.NestedString(target.Object, "status", "status")
		Expect(err).To(BeNil())
		log.Infof("Wait till target becomes 'Available' - current status=%s", targetStatus)
		return targetStatus == "Available"
	}, timeout, interval).Should(BeTrue())

	log.Info("target CR is in Available state")
}

func getNFSCredentials() (nfsIPAddr, nfsServerPath string) {
	nfsIPAddr, isNFSIPAddrPresent := os.LookupEnv(NFSServerIP)
	nfsServerPath, isNFSServerPathPresent := os.LookupEnv(NFSServerBasePath)
	if !isNFSIPAddrPresent || !isNFSServerPathPresent {
		panic("NFS Credentials not present in env")
	}

	return nfsIPAddr, nfsServerPath
}

// updateYAMLs Update old YAML values with new values
// kv is map of old value to new value
func updateYAMLs(kv map[string]string, yamlPath string) error {
	read, readErr := ioutil.ReadFile(yamlPath)
	if readErr != nil {
		return readErr
	}
	updatedFile := string(read)
	for placeholder, value := range kv {
		if strings.Contains(updatedFile, placeholder) && placeholder != "" {
			updatedFile = strings.ReplaceAll(updatedFile, placeholder, value)
			log.Infof("Updated the old value: [%s] with new value: [%s] in file [%s]",
				placeholder, value, yamlPath)
		}
	}

	return ioutil.WriteFile(yamlPath, []byte(updatedFile), 0)
}

func GetSecret(ctx context.Context, k8sClient client.Client, name, ns string) *corev1.Secret {
	secret := &corev1.Secret{}
	Eventually(func() error {
		log.Info("getting secret")
		return k8sClient.Get(ctx, types.NamespacedName{Name: name, Namespace: ns}, secret)
	}, timeout, interval).ShouldNot(HaveOccurred())

	return secret
}

func GetIngress(ctx context.Context, k8sClient client.Client, name, ns string) *v1beta1.Ingress {
	ing := &v1beta1.Ingress{}
	Eventually(func() error {
		log.Info("getting Ingress")
		return k8sClient.Get(ctx, types.NamespacedName{Name: name, Namespace: ns}, ing)
	}, timeout, interval).ShouldNot(HaveOccurred())

	return ing
}

func UpdateIngress(ctx context.Context, k8sClient client.Client, ing *v1beta1.Ingress) {
	Eventually(func() error {
		log.Info("Updating ingress")
		return k8sClient.Update(ctx, ing)
	}, timeout, interval).ShouldNot(HaveOccurred())
	log.Infof("Updated ingress %s successfully", ing.Name)
}

func checkPvcDeleted(ctx context.Context, k8sClient client.Client, ns string) {
	Eventually(func() bool {
		log.Info("Waiting for PVC to be deleted")
		pvcList := corev1.PersistentVolumeClaimList{}
		selectors, err := metav1.LabelSelectorAsSelector(&metav1.LabelSelector{
			MatchLabels: map[string]string{kubernetesInstanceKey: TargetName},
		})
		Expect(err).To(BeNil())
		err = k8sClient.List(ctx, &pvcList, client.MatchingLabelsSelector{Selector: selectors}, client.InNamespace(ns))
		Expect(err).To(BeNil())
		return pvcList.Items == nil
	}, timeout, interval).Should(BeTrue())
}
