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
rsync -av \
  --include='yearly/' \
  --include='yearly/*_2M/' \
  --include='yearly/*_2M/*.ncz' \
  --include='yearly/TOT_PREC/' \
  --include='yearly/TOT_PREC/*.ncz' \
  --include='yearly/PMSL/' \
  --include='yearly/PMSL/*.ncz' \
  --include='yearly/FI500*/' \
  --include='yearly/FI500*/*.ncz' \
  --include='yearly/ACLCT/' \
  --include='yearly/ACLCT/*.ncz' \
  --include='yearly/T_G/' \
  --include='yearly/T_G/*.ncz' \
  --include='yearly/W_SO/' \
  --include='yearly/W_SO/*.ncz' \
  --include='*.nc' \
  --exclude='*' \
  ${POST_DIR}/ levante:${DEST_DIR}

# Update permissions
echo "Updating permissions..."
chmod -R u=rwx,go=rx ${BASE_DIR}
echo "Done."

