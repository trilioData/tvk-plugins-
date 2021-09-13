#!/usr/bin/env bash

set -o pipefail

CLEANUP_TESTS_SUCCESS=true

# shellcheck source=/dev/null
source tools/cleanup/cleanup.sh --source-only

testDeleteRes() {
  delete_tvk_res
  rc=$?
  # shellcheck disable=SC2181
  if [ $rc != "0" ]; then
    # shellcheck disable=SC2082
    echo "Failed - test delete_tvk_res, Expected 0 got $rc"
  fi
  return $rc
}

testDeleteOp() {
  delete_tvk_op
  rc=$?
  # shellcheck disable=SC2181
  if [ $rc != "0" ]; then
    # shellcheck disable=SC2082
    echo "Failed - test delete_tvk_op, Expected 0 got $rc"
  fi
  return $rc
}

testDeleteCrd() {
  delete_tvk_crd
  rc=$?
  # shellcheck disable=SC2181
  if [ $rc != "0" ]; then
    # shellcheck disable=SC2082
    echo "Failed - test delete_tvk_crd, Expected 0 got $rc"
  fi
  return $rc
}

testDeleteRes
retCode=$?
if [[ $retCode -ne 0 ]]; then
  CLEANUP_TESTS_SUCCESS=false
fi

testDeleteOp
retCode=$?
if [[ $retCode -ne 0 ]]; then
  CLEANUP_TESTS_SUCCESS=false
fi

testDeleteCrd
retCode=$?
if [[ $retCode -ne 0 ]]; then
  CLEANUP_TESTS_SUCCESS=false
fi

# Check status of Pre-flight test-cases
if [ $CLEANUP_TESTS_SUCCESS == "true" ]; then
  echo -e "All Cleanup tests Passed!"
else
  echo -e "Some Cleanup tests Failed!"
  exit 1
fi
