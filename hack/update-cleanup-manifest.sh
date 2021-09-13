#!/bin/bash

set -e -o pipefail

if [[ -z "${CLEANUP_VERSION}" ]]; then
  echo >&2 "CLEANUP_VERSION (required) is not set"
  exit 1
else
  echo "CLEANUP_VERSION is set to ${CLEANUP_VERSION}"
fi

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
# shellcheck disable=SC2164
cd "$SRC_ROOT"

plugins_dir="$SRC_ROOT"/plugins
build_dir="$SRC_ROOT"/build
template_manifest_dir="$SRC_ROOT"/.krew
cleanup_yaml="tvk-cleanup.yaml"
cleanup_template_manifest=$template_manifest_dir/$cleanup_yaml

mkdir -p "${build_dir}"

# shellcheck disable=SC2086
cp "$cleanup_template_manifest" $build_dir/$cleanup_yaml
cleanup_template_manifest=$build_dir/$cleanup_yaml

repoURL=$(git config --get remote.origin.url)
cleanupSha256File="cleanup-sha256.txt"

cleanupSha256URI="$repoURL/releases/download/${CLEANUP_VERSION}/$cleanupSha256File"
cleanupSha256FilePath=$build_dir/$cleanupSha256File

curl -fsSL "$cleanupSha256URI" >"${cleanupSha256FilePath}"

if [ -s "${cleanupSha256FilePath}" ]; then
  echo "File ${cleanupSha256FilePath} successfully downloaded and contains data"
else
  echo "File ${cleanupSha256FilePath} does not contain any data. Exiting..."
  exit 1
fi

cleanup_sha=$(awk '{print $1}' "$cleanupSha256FilePath")

sed -i "s/CLEANUP_VERSION/$CLEANUP_VERSION/g" "$cleanup_template_manifest"
sed -i "s/CLEANUP_TAR_CHECKSUM/$cleanup_sha/g" "$cleanup_template_manifest"

cp "$build_dir"/$cleanup_yaml "$plugins_dir"/$cleanup_yaml
echo >&2 "Updated cleanup plugin manifest '$cleanup_yaml' with 'version=$CLEANUP_VERSION' and new sha256sum"
