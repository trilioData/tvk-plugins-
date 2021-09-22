#!/bin/bash

set -e -o pipefail

if [[ -z "${TVK_ONECLICK_VERSION}" ]]; then
  echo >&2 "TVK_ONECLICK_VERSION (required) is not set"
  exit 1
else
  echo "TVK_ONECLICK_VERSION is set to ${TVK_ONECLICK_VERSION}"
fi

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
# shellcheck disable=SC2164
cd "$SRC_ROOT"

plugins_dir="$SRC_ROOT"/plugins
build_dir="$SRC_ROOT"/build
template_manifest_dir="$SRC_ROOT"/.krew
tvk_oneclick_yaml="tvk-oneclick.yaml"
tvk_oneclick_template_manifest=$template_manifest_dir/$tvk_oneclick_yaml

mkdir -p "${build_dir}"

# shellcheck disable=SC2086
cp "$tvk_oneclick_template_manifest" $build_dir/$tvk_oneclick_yaml
tvk_oneclick_template_manifest=$build_dir/$tvk_oneclick_yaml

repoURL=$(git config --get remote.origin.url)
tvkoneclickSha256File="tvk-oneclick-sha256.txt"

tvkoneclickSha256URI="$repoURL/releases/download/${TVK_ONECLICK_VERSION}/$tvkoneclickSha256File"
tvkoneclickSha256FilePath=$build_dir/$tvkoneclickSha256File

curl -fsSL "$tvkoneclickSha256URI" >"${tvkoneclickSha256FilePath}"

if [ -s "${tvkoneclickSha256FilePath}" ]; then
  echo "File ${tvkoneclickSha256FilePath} successfully downloaded and contains data"
else
  echo "File ${tvkoneclickSha256FilePath} does not contain any data. Exiting..."
  exit 1
fi

tvk_oneclick_sha=$(awk '{print $1}' "$tvkoneclickSha256FilePath")

sed -i "s/TVK_ONECLICK_VERSION/$TVK_ONECLICK_VERSION/g" "$tvk_oneclick_template_manifest"
sed -i "s/TVK_ONECLICK_TAR_CHECKSUM/$tvk_oneclick_sha/g" "$tvk_oneclick_template_manifest"

cp "$build_dir"/$tvk_oneclick_yaml "$plugins_dir"/$tvk_oneclick_yaml
echo >&2 "Updated tvk-oneclick plugin manifest '$tvk_oneclick_yaml' with 'version=$TVK_ONECLICK_VERSION' and new sha256sum"
