#!/bin/bash

# Usage: ./untar_monthly_data.sh 1961_09

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 YYYY_MM"
  exit 1
fi

date="$1"

source job_settings

src_dir="${ARCHIVE_OUTDIR}/${EXPID}/${date}"
out_dir="${SCRATCHDIR}/${EXPID}/input/post/$date"

# Untar each file into its corresponding subdirectory, stripping the top-level folder
for tarfile in "$src_dir"/*.tar; do
  fname=$(basename "$tarfile")
  if [[ "$fname" == *_nesting.tar ]]; then
    target="$out_dir/nesting"
  elif [[ "$fname" =~ _out([0-9]{2})\.tar$ ]]; then
    num="${BASH_REMATCH[1]}"
    target="$out_dir/out$num"
  else
    echo "Skipping unknown tar file: $fname"
    continue
  fi
  mkdir -p $target
  echo "Untarring $fname to $target"
  tar --strip-components=1 -xf "$tarfile" -C "$target"
done

echo "All tar files for $date have been extracted to $out_dir."
