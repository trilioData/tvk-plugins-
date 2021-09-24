package cmd

import (
	"time"

	"github.com/araddon/dateparse"
	"k8s.io/apimachinery/pkg/util/sets"
)

func removeDuplicates(uids []string) []string {
	uniqueUIDs := sets.String{}
	for _, uid := range uids {
		if !uniqueUIDs.Has(uid) {
			uniqueUIDs.Insert(uid)
		}
	}

	return uniqueUIDs.List()

}

func parseTimestamp(timestamp string) (*time.Time, error) {
	ts, err := dateparse.ParseAny(timestamp)
	if err != nil {
		return &time.Time{}, err
	}
	return &ts, nil
}
