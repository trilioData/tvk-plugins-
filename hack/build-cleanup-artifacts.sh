#!/usr/bin/env bash

set -euo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

# create cleanup tar package
cleanup_tar_archive="cleanup.tar.gz"
echo >&2 "Creating ${cleanup_tar_archive} archive."

cd "$SRC_ROOT"
build_dir="build"
mkdir $build_dir
cp -r tools/cleanup $build_dir
cp LICENSE.md $build_dir/cleanup
cd $build_dir
mv cleanup/cleanup.sh cleanup/cleanup

# consistent timestamps for files in build dir to ensure consistent checksums
while IFS= read -r -d $'\0' f; do
  echo "modifying atime/mtime for $f"
  TZ=UTC touch -at "0001010000" "$f"
  TZ=UTC touch -mt "0001010000" "$f"
done < <(find . -print0)

tar -cvzf ${cleanup_tar_archive} cleanup/
echo >&2 "Created ${cleanup_tar_archive} archive successfully"

# create preflight tar sha256 file
echo >&2 "Compute sha256 of ${cleanup_tar_archive} archive."

checksum_cmd="shasum -a 256"
if hash sha256sum 2>/dev/null; then
  checksum_cmd="sha256sum"
fi

cleanup_sha256_file=cleanup-sha256.txt
"${checksum_cmd[@]}" "${cleanup_tar_archive}" >$cleanup_sha256_file
echo >&2 "Successfully written sha256 of ${cleanup_tar_archive} into $cleanup_sha256_file"
