#!/bin/bash

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and catch errors in pipelines.
set -euo pipefail

# Source job settings
source job_settings

# Argument parsing: detect year argument and flags
analyze_arch=true
analyze_post=true
year_arg=""

for arg in "$@"; do
  if [[ "$arg" =~ ^[0-9]{4}$ ]]; then
    year_arg="$arg"
  elif [[ "$arg" == "--arch" ]]; then
    analyze_post=false
  elif [[ "$arg" == "--post" ]]; then
    analyze_arch=false
  fi
done

if [[ -z "$year_arg" ]]; then
  echo "No year argument given. Checking yearly file consistency..."
  if $analyze_arch; then
    # ARCHIVE: Check all folders ${ARCHIVE_OUTDIR}/${EXPID}/????_?? contain the same number of files
    archive_dir="${ARCHIVE_OUTDIR}/${EXPID}"
    echo "=== ARCH yearly folder file count ==="
    declare -A archive_counts
    for d in "$archive_dir"/[0-9][0-9][0-9][0-9]_[0-9][0-9]; do
      if [[ -d "$d" ]]; then
        count=$(find "$d" -type f | wc -l)
        archive_counts[$d]=$count
        echo "$d: $count"
      fi
    done
    # Check if all counts are the same
    unique_counts=($(printf "%s\n" "${archive_counts[@]}" | sort -u))
    if [[ ${#unique_counts[@]} -eq 1 ]]; then
      echo "All ARCHIVE folders have the same number of files: ${unique_counts[0]}"
    else
      echo "ARCHIVE folders have differing file counts: ${unique_counts[*]}"
    fi
    echo
  fi

  if $analyze_post; then
    # Check if all folders ${WORKDIR}/${EXPID}/post/yearly/*/ contain the same number of files
    post_yearly_root="${WORKDIR}/${EXPID}/post/yearly"
    echo "=== Check: yearly subfolder file count summary ==="
    declare -A yearly_counts
    max_count=0
    for subdir in "$post_yearly_root"/*/; do
      if [[ -d "$subdir" ]]; then
        count=$(find "$subdir" -type f | wc -l)
        yearly_counts[$subdir]=$count
        if (( count > max_count )); then
          max_count=$count
        fi
      fi
    done
    # Also check T_2M folder
    t2m_dir="${post_yearly_root}/T_2M"
    if [[ -d "$t2m_dir" ]]; then
      t2m_count=$(find "$t2m_dir" -type f | wc -l)
      yearly_counts[$t2m_dir]=$t2m_count
      if (( t2m_count > max_count )); then
        max_count=$t2m_count
      fi
    fi
    # List only folders with less than max_count
    less_than_max=()
    for folder in "${!yearly_counts[@]}"; do
      if (( yearly_counts[$folder] < max_count )); then
        less_than_max+=("$folder (${yearly_counts[$folder]})")
      fi
    done
    echo "Maximum file count in yearly subfolders: $max_count"
    if [[ ${#less_than_max[@]} -gt 0 ]]; then
      echo "Folders with less than maximum file count:"
      for entry in "${less_than_max[@]}"; do
        echo "  $entry"
      done
    else
      echo "All yearly subfolders (including T_2M) have the maximum file count."
    fi

    # POST: Check yearly files in T_2M
    post_yearly_dir="${WORKDIR}/${EXPID}/post/yearly/T_2M"
    echo "=== POST yearly file count ==="
    # Get expected number of years from YDATE_START and YDATE_STOP
    ystart=${YDATE_START:0:4}
    # Read ystop from date.log (first 4 digits)
    if [[ -f date.log ]]; then
      ystop=$(( $(head -c 4 date.log) - 1 ))
    else
      echo "date.log not found!" >&2
      exit 1
    fi
    expected_years=$((ystop - ystart + 1))
    file_count=$(ls "$post_yearly_dir"/*.nc* 2>/dev/null | wc -l)
    echo "Files in $post_yearly_dir: $file_count"
    echo "Expected number of years: $expected_years"
    if [[ $file_count -eq $expected_years ]]; then
      echo "POST yearly files match expected count."
    else
      echo "POST yearly files do NOT match expected count!"
      # Find missing years
      # Get years from filenames (extract year after T_2M_)
      present_years=()
      for f in "$post_yearly_dir"/T_2M_*.nc*; do
        [[ -e "$f" ]] || continue
        # Extract year after T_2M_
        fname=$(basename "$f")
        year=$(echo "$fname" | sed -n 's/^T_2M_\([0-9]\{4\}\)[0-9]\{6\}.*$/\1/p')
        if [[ -n "$year" ]]; then
          present_years+=("$year")
        fi
      done
      # Build expected years array
      missing_years=()
      for ((y=ystart; y<=ystop; y++)); do
        if [[ ! " ${present_years[@]} " =~ " $y " ]]; then
          missing_years+=("$y")
        fi
      done
      if [[ ${#missing_years[@]} -gt 0 ]]; then
        echo "Missing years: ${missing_years[*]}"
      fi
    fi
    echo
  fi
  exit 0
fi

YYYY="$year_arg"

# Function to count files per month in a given base directory
count_files() {
  local label="$1"
  local base_dir="$2"

  echo "=== $label ==="
  for mm in {1..12}; do
    MM=$(printf "%02d" "$mm")
    dir="${base_dir}/${YYYY}_${MM}"

    if [[ -d "$dir" ]]; then
      file_count=$(find "$dir" -type f | wc -l)
      echo "$dir: $file_count"
    else
      echo "$dir: Directory not found"
    fi
  done
  echo
}

# ARCHIVE output
archive_dir="${ARCHIVE_OUTDIR}/${EXPID}"
count_files "ARCH" "$archive_dir"

# POST output
post_dir="${WORKDIR}/${EXPID}/post"
count_files "POST" "$post_dir"

