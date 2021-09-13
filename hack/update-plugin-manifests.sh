#!/bin/bash

set -e -o pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_PATH"/update-preflight-manifest.sh
"$SCRIPT_PATH"/update-log-collector-manifest.sh
"$SCRIPT_PATH"/update-target-browser-manifest.sh
"$SCRIPT_PATH"/update-cleanup-manifest.sh
