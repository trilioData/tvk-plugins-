#!/usr/bin/env bash

# This script verifies that a tvk-oneclick build can be installed to a system using
# krew local testing method

set -euo pipefail

[[ -n "${DEBUG:-}" ]] && set -x

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
cd "$SRC_ROOT"

build_dir="build"

tvk_oneclick_manifest="${build_dir}/tvk-oneclick.yaml"
if [[ ! -f "${tvk_oneclick_manifest}" ]]; then
  echo >&2 "Could not find manifest ${tvk_oneclick_manifest}."
  exit 1
fi

tvk_oneclick_archive="${build_dir}/tvk-oneclick.tar.gz"
if [[ ! -f "${tvk_oneclick_archive}" ]]; then
  echo >&2 "Could not find archive ${tvk_oneclick_archive}."
  exit 1
fi

# test for linux OS
kubectl krew install --manifest=$tvk_oneclick_manifest --archive=$tvk_oneclick_archive
kubectl krew uninstall tvk-oneclick

# test for darwin OS
KREW_OS=darwin KREW_ARCH=amd64 kubectl krew install --manifest=$tvk_oneclick_manifest --archive="$tvk_oneclick_archive"
KREW_OS=darwin KREW_ARCH=amd64 kubectl krew uninstall tvk-oneclick

echo >&2 "Successfully tested Tvk-oneclick plugin locally"
