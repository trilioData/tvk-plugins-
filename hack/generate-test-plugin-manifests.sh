#!/usr/bin/env bash

set -e -o pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_PATH"/generate-test-preflight-plugin-manifest.sh
"$SCRIPT_PATH"/generate-test-log-collector-plugin-manifest.sh
"$SCRIPT_PATH"/generate-test-target-browser-plugin-manifest.sh
"$SCRIPT_PATH"/generate-test-tvk-oneclick-plugin-manifest.sh
