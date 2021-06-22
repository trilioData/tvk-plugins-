package targetbrowser

import (
	"bytes"
	"fmt"
	"net/http"

	"github.com/google/go-querystring/query"
	"github.com/thedevsaddam/gojsonq"
)

const (
	backupEndPoint = "backup"
	Results        = "results"
)

// BackupListOptions for backup
type BackupListOptions struct {
	Page          int    `url:"page"`
	PageSize      int    `url:"pageSize"`
	Ordering      string `url:"ordering"`
	BackupPlanUID string `url:"backupPlanUID"`
	BackupStatus  string `url:"status"`
}

// GetBackups returns backup with available options
func (c *Client) GetBackups(options *BackupListOptions) error {
	values, err := query.Values(options)
	if err != nil {
		return err
	}
	queryParam := values.Encode()
	return c.TriggerAPI(backupEndPoint, queryParam, backupSelector)

}

func (c *Client) TriggerAPI(apiEndPoint, queryParam string, selector []string) error {
	req, err := http.NewRequest(MethodGet, fmt.Sprintf("%s/%s?%s", c.baseURL, apiEndPoint, queryParam), nil)
	if err != nil {
		return err
	}

	res, err := c.sendRequest(req)
	if err != nil {
		return err
	}
	var backupBytes bytes.Buffer
	gojsonq.New().FromString(res).From(Results).Select(selector...).Writer(&backupBytes)
	fmt.Println(backupBytes.String())
	return nil
}