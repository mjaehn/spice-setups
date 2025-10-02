#!/bin/bash

set -e

source job_settings

# Set directories
BASE_DIR=/capstor/store/cscs/userlab/cwp06/mjaehn/ICON-CLM
ARCH_DIR=${BASE_DIR}/arch/${EXPID}
WORK_DIR=${BASE_DIR}/work/${EXPID}
POST_DIR=${WORK_DIR}/post
DEST_DIR=/work/bb1364/ext_production_runs/work/${EXPID}
#!/bin/bash

set -e

source job_settings

# Set directories
BASE_DIR=/capstor/store/cscs/userlab/cwp06/mjaehn/ICON-CLM
ARCH_DIR=${BASE_DIR}/arch/${EXPID}
WORK_DIR=${BASE_DIR}/work/${EXPID}
POST_DIR=${WORK_DIR}/post
DEST_DIR=/work/bb1364/ext_production_runs/work/${EXPID}

# Sync data

# Location of variables file (one pattern per line). Comments starting with '#' and blank lines are ignored.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIABLES_FILE="${SCRIPT_DIR}/variables_to_copy"

if [ ! -f "${VARIABLES_FILE}" ]; then
  echo "Error: variables file not found: ${VARIABLES_FILE}" >&2
  echo "Create a file named 'variables_to_copy' next to this script with one include pattern per line." >&2
  exit 1
fi

echo "Using variables file: ${VARIABLES_FILE}"

# Build include arguments for rsync from the variables file (variable names only)
# Always include the top-level yearly/ directory and any top-level *.nc files
include_args=("--include=yearly/" "--include=*.nc")
while IFS= read -r line || [ -n "$line" ]; do
  # trim leading/trailing whitespace
  var="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  # skip empty lines and comments
  case "${var}" in
    ""|#*) continue ;;
  esac
  # Add include for the variable directory and its .ncz files under yearly/
  include_args+=("--include=yearly/${var}/")
  include_args+=("--include=yearly/${var}/*.ncz")
done < "${VARIABLES_FILE}"

rsync -av "${include_args[@]}" --exclude='*' "${POST_DIR}/" "levante:${DEST_DIR}"

# Update permissions
echo "Updating permissions..."
chmod -R u=rwx,go=rx ${BASE_DIR}
echo "Done."

