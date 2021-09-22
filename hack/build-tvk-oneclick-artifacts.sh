#!/usr/bin/env bash

set -euo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

# create preflight tar package
tvk_oneclick_tar_archive="tvk-oneclick.tar.gz"
echo >&2 "Creating ${tvk_oneclick_tar_archive} archive."

cd "$SRC_ROOT"
build_dir="build"
mkdir $build_dir
cp -r tools/tvk-oneclick $build_dir
cp LICENSE.md $build_dir/tvk-oneclick
cd $build_dir
mv tvk-oneclick/tvk-oneclick.sh tvk-oneclick/tvk-oneclick

# consistent timestamps for files in build dir to ensure consistent checksums
while IFS= read -r -d $'\0' f; do
  echo "modifying atime/mtime for $f"
  TZ=UTC touch -at "0001010000" "$f"
  TZ=UTC touch -mt "0001010000" "$f"
done < <(find . -print0)

tar -cvzf ${tvk_oneclick_tar_archive} tvk-oneclick/
echo >&2 "Created ${tvk_oneclick_tar_archive} archive successfully"

# create preflight tar sha256 file
echo >&2 "Compute sha256 of ${tvk_oneclick_tar_archive} archive."

checksum_cmd="shasum -a 256"
if hash sha256sum 2>/dev/null; then
  checksum_cmd="sha256sum"
fi

tvk_oneclick_sha256_file=tvk-oneclick-sha256.txt
"${checksum_cmd[@]}" "${tvk_oneclick_tar_archive}" >$tvk_oneclick_sha256_file
echo >&2 "Successfully written sha256 of ${tvk_oneclick_tar_archive} into $tvk_oneclick_sha256_file"
