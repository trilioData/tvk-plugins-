#!/usr/bin/env bash

# This script verifies that a cleanup build can be installed to a system using
# krew local testing method

set -euo pipefail

[[ -n "${DEBUG:-}" ]] && set -x

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
cd "$SRC_ROOT"

build_dir="build"

cleanup_manifest="${build_dir}/tvk-cleanup.yaml"
if [[ ! -f "${cleanup_manifest}" ]]; then
  echo >&2 "Could not find manifest ${cleanup_manifest}."
  exit 1
fi

cleanup_archive="${build_dir}/cleanup.tar.gz"
if [[ ! -f "${cleanup_archive}" ]]; then
  echo >&2 "Could not find archive ${cleanup_archive}."
  exit 1
fi

# test for linux OS
kubectl krew install --manifest=$cleanup_manifest --archive=$cleanup_archive
kubectl krew uninstall tvk-cleanup

# test for darwin OS
KREW_OS=darwin KREW_ARCH=amd64 kubectl krew install --manifest=$cleanup_manifest --archive="$cleanup_archive"
KREW_OS=darwin KREW_ARCH=amd64 kubectl krew uninstall tvk-cleanup

echo >&2 "Successfully tested cleanup plugin locally"
