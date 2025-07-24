#!/usr/bin/env bash
# ICON-CLM Starter Package (SPICE_v2.3)
#
# ---------------------------------------------------------------
# Copyright (C) 2009-2025, Helmholtz-Zentrum Hereon
# Contact information: https://www.clm-community.eu/
#
# See AUTHORS.TXT for a list of authors
# See LICENSES/ for license information
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SPICE docs: https://hereon-coast.atlassian.net/wiki/spaces/SPICE/overview
# ---------------------------------------------------------------
set -e
# ============================================================================

##################################################
# batch settings for ICLM run on Alps at CSCS
##################################################
#
# Purpose: This script interpolates reanalyses or GCM data for initial and boundary condition
#

echo ----- start CONV2ICON

#... get the job_settings environment variables
source ${PFDIR}/${EXPID}/job_settings

#
# load the necessary modules
module load cdo/${CDO_VERSION}
module load nco/${NCO_VERSION}

ulimit -s 102400

#-------------------------------------------------------------------------------
#  Pre-Settings
#-------------------------------------------------------------------------------

INPDIR=${SCRATCHDIR}/${EXPID}/input/conv2icon
OUTDIR=${SCRATCHDIR}/${EXPID}/output/conv2icon

# the following parameters change during job chaining
NEXT_DATE=$(${CFU} get_next_dates ${CURRENT_DATE} 01:00:00 ${ITYPE_CALENDAR} | cut -c1-10)
YYYY=${CURRENT_DATE:0:4}
MM=${CURRENT_DATE:4:2}
YYYY_MM=${YYYY}_${MM}

#... Create the run directory:
mkdir -p ${WORKDIR}/${EXPID}/joboutputs/conv2icon/${YYYY_MM}

#... Create the output directory:
mkdir -p ${OUTDIR}/${YYYY_MM}

#... Set maximum number of parallel processes:
(( MAXPP=TASKS_CONV2ICON ))

#-------------------------------------------------------------------------------
#  Main Part
#-------------------------------------------------------------------------------

echo START ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/conv2icon/finish_joblist
echo "conv2icon ${YYYY_MM} START    $(date)" >> ${PFDIR}/${EXPID}/chain_status.log

DATE_START=$(date +%s)

cd ${WORKDIR}/${EXPID}/joboutputs/conv2icon/${YYYY_MM}

#-------------------------------------------------------------------------------
# SETTINGS: DIRECTORIES AND INPUT/OUTPUT FILE NAMES
#-------------------------------------------------------------------------------
#... Global data:
DATAFILELIST=$(find ${INPDIR}/${YYYY_MM}/${GCM_PREFIX}??????????.nc)

#-------------------------------------------------------------------------------
# PART I: Extract initial data
#-------------------------------------------------------------------------------

if [ ${CURRENT_DATE} -eq ${YDATE_START}  ]
then
  echo ----- start CONV2ICON for initial data

  #... Create ocean and land masks from external parameters:
  ${PYTHON} ${PFDIR}/${EXPID}/scripts/create_masks.py --input_path ${INPDIR} --inidir ${INIDIR} --input_file ${YYYY_MM}/${GCM_PREFIX}${YDATE_START}.nc --extpar_file ${EXTPAR}

  ${CDO} -L -s setctomiss,0. -ltc,0.5 ${INIDIR}/input_FR_LAND.nc ${INIDIR}/input_ocean_area.nc
  ${CDO} -L -s setctomiss,0. -gec,0.5 ${INIDIR}/input_FR_LAND.nc ${INIDIR}/input_land_area.nc
  ${CDO} -L -s setctomiss,0. -ltc,1. ${INIDIR}/output_FR_LAND.nc ${INIDIR}/output_ocean_area.nc
  ${CDO} -L -s setctomiss,0. -gtc,0. ${INIDIR}/output_FR_LAND.nc ${INIDIR}/output_land_area.nc
  ${CDO} -s setrtoc2,0.5,1.0,1,0 ${INIDIR}/output_FR_LAND.nc ${OUTDIR}/output_lsm.nc
  rm ${INIDIR}/input_FR_LAND.nc ${INIDIR}/output_FR_LAND.nc

  #... Create file with ICON grid information for CDO:
   ${CDO} -s selgrid,2 ${LAM_GRID} ${INIDIR}/triangular-grid.nc

  #... Remap land area only variables (ocean points are assumed to be undefined
  #    in the input data)
  ${CDO} -s setmisstodis -selname,SMIL1,SMIL2,SMIL3,SMIL4,STL1,STL2,STL3,STL4,W_SNOW,T_SNOW ${INPDIR}/${YYYY_MM}/${GCM_PREFIX}${YDATE_START}.nc  \
                                       ${OUTDIR}/${YYYY_MM}/tmpl1.nc
  ${CDO} -s -P ${OMP_THREADS_CONV2ICON} ${GCM_REMAP},${INIDIR}/triangular-grid.nc ${OUTDIR}/${YYYY_MM}/tmpl1.nc ${OUTDIR}/${YYYY_MM}/tmpl2.nc
  ${CDO} -s div ${OUTDIR}/${YYYY_MM}/tmpl2.nc ${INIDIR}/output_land_area.nc ${OUTDIR}/${YYYY_MM}/tmp_output_l.nc
  rm ${OUTDIR}/${YYYY_MM}/tmpl?.nc

  #... Remap land and ocean area differently for variables:
  #    Ocean part:
  ${CDO} -s selname,SKT ${INPDIR}/${YYYY_MM}/${GCM_PREFIX}${YDATE_START}.nc ${OUTDIR}/${YYYY_MM}/tmp_input_ls.nc
  ${CDO} -s div ${OUTDIR}/${YYYY_MM}/tmp_input_ls.nc ${INIDIR}/input_ocean_area.nc  ${OUTDIR}/${YYYY_MM}/tmpls1.nc
  ${CDO} -s setmisstodis ${OUTDIR}/${YYYY_MM}/tmpls1.nc ${OUTDIR}/${YYYY_MM}/tmpls2.nc
  ${CDO} -s -P ${OMP_THREADS_CONV2ICON} ${GCM_REMAP},${INIDIR}/triangular-grid.nc ${OUTDIR}/${YYYY_MM}/tmpls2.nc ${OUTDIR}/${YYYY_MM}/tmpls3.nc
  ${CDO} -s div ${OUTDIR}/${YYYY_MM}/tmpls3.nc ${INIDIR}/output_ocean_area.nc ${OUTDIR}/${YYYY_MM}/tmp_ocean_part.nc
  rm ${OUTDIR}/${YYYY_MM}/tmpls?.nc
  #    Land part:
  ${CDO} -s div ${OUTDIR}/${YYYY_MM}/tmp_input_ls.nc ${INIDIR}/input_land_area.nc  ${OUTDIR}/${YYYY_MM}/tmpls1.nc
  ${CDO} -s setmisstodis ${OUTDIR}/${YYYY_MM}/tmpls1.nc ${OUTDIR}/${YYYY_MM}/tmpls2.nc
  ${CDO} -s -P ${OMP_THREADS_CONV2ICON} ${GCM_REMAP},${INIDIR}/triangular-grid.nc ${OUTDIR}/${YYYY_MM}/tmpls2.nc ${OUTDIR}/${YYYY_MM}/tmpls3.nc
  ${CDO} -s div ${OUTDIR}/${YYYY_MM}/tmpls3.nc ${INIDIR}/output_land_area.nc ${OUTDIR}/${YYYY_MM}/tmp_land_part.nc
  rm ${OUTDIR}/${YYYY_MM}/tmpls?.nc
  #    Merge remapped land and ocean part:
  ${CDO} -s ifthenelse ${OUTDIR}/output_lsm.nc ${OUTDIR}/${YYYY_MM}/tmp_land_part.nc  ${OUTDIR}/${YYYY_MM}/tmp_ocean_part.nc ${OUTDIR}/${YYYY_MM}/tmp_output_ls.nc
  rm ${OUTDIR}/${YYYY_MM}/tmp_land_part.nc ${OUTDIR}/${YYYY_MM}/tmp_ocean_part.nc

  #    Remap the rest:
  ${NCO_BINDIR}/ncks -h -O -x -v W_SNOW,T_SNOW,STL1,STL2,STL3,STL4,SMIL1,SMIL2,SMIL3,SMIL4,SKT,LSM ${INPDIR}/${YYYY_MM}/${GCM_PREFIX}${YDATE_START}.nc ${OUTDIR}/${YYYY_MM}/tmp_input_rest.nc
  ${CDO} -s -P ${OMP_THREADS_CONV2ICON} ${GCM_REMAP},${INIDIR}/triangular-grid.nc ${OUTDIR}/${YYYY_MM}/tmp_input_rest.nc ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc

  #    Merge remapped files plus land sea mask from EXTPAR:
  ${NCO_BINDIR}/ncks -h -A ${OUTDIR}/${YYYY_MM}/tmp_output_l.nc ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  ${NCO_BINDIR}/ncks -h -A ${OUTDIR}/${YYYY_MM}/tmp_output_ls.nc ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  ${NCO_BINDIR}/ncks -h -A ${OUTDIR}/output_lsm.nc  ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  rm -f ${OUTDIR}/${YYYY_MM}/tmp_output_l.nc ${OUTDIR}/${YYYY_MM}/tmp_output_ls.nc ${OUTDIR}/${YYYY_MM}/tmp_input_ls.nc ${OUTDIR}/${YYYY_MM}/tmp_input_rest.nc

  #    Attribute modifications:
  ${NCO_BINDIR}/ncatted -h -a coordinates,FR_LAND,o,c,"clon clat" ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc

  #... Renamings:
  ${NCO_BINDIR}/ncrename -h -v FR_LAND,LSM ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  ${NCO_BINDIR}/ncrename -h -v SIC,CI ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  ${NCO_BINDIR}/ncrename -h -d level,lev ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  ${NCO_BINDIR}/ncrename -h -d cell,ncells ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  ${NCO_BINDIR}/ncrename -h -d nv,vertices ${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc

  #... The vertical coordinate coefficients has not been transfered by CDO. They
  #    have to be added here again:
  cd ${INIDIR}
  ${NCO_BINDIR}/ncks -h -O -C -v ak,bk ${INPDIR}/${YYYY_MM}/${GCM_PREFIX}${YYYY}${MM}0100.nc hyai_hybi.nc

  ${NCO_BINDIR}/ncatted -h -a ,global,d,,  hyai_hybi.nc
  ${NCO_BINDIR}/ncrename -d level1,nhyi hyai_hybi.nc
  ${NCO_BINDIR}/ncrename -v ak,hyai hyai_hybi.nc
  ${NCO_BINDIR}/ncrename -v bk,hybi hyai_hybi.nc
  ${NCO_BINDIR}/ncks -h -A ${INIDIR}/hyai_hybi.nc ${GCM_PREFIX}${YDATE_START}_ini.nc

fi # end remapping initial data

#-------------------------------------------------------------------------------
# PART II: Extract lower boundary data
#-------------------------------------------------------------------------------
rm -f ${OUTDIR}/${YYYY_MM}/${GCM_PREFIX}${YYYY}${MM}_tmp.nc

${NCO_BINDIR}/ncrcat -h -v SIC,SST ${INPDIR}/${YYYY_MM}/${GCM_PREFIX}??????????.nc  \
                 ${OUTDIR}/${YYYY_MM}/${GCM_PREFIX}${YYYY}${MM}_tmp.nc

${CDO} -s setmisstodis -selname,SIC ${OUTDIR}/${YYYY_MM}/${GCM_PREFIX}${YYYY}${MM}_tmp.nc \
                                ${OUTDIR}/${YYYY_MM}/SIC_${YYYY}${MM}_tmp.nc

#... We're using ERA5 T_SKIN as SST - take the ocean part only:
${CDO} -s div -selname,SST ${OUTDIR}/${YYYY_MM}/${GCM_PREFIX}${YYYY}${MM}_tmp.nc  ${INIDIR}/input_ocean_area.nc \
           ${OUTDIR}/${YYYY_MM}/SST_${YYYY}${MM}_tmp.nc

${CDO} -s setmisstodis  ${OUTDIR}/${YYYY_MM}/SST_${YYYY}${MM}_tmp.nc  \
            ${OUTDIR}/${YYYY_MM}/SST_${YYYY}${MM}_tmp2.nc

${CDO} -s merge ${OUTDIR}/${YYYY_MM}/SST_${YYYY}${MM}_tmp2.nc  \
             ${OUTDIR}/${YYYY_MM}/SIC_${YYYY}${MM}_tmp.nc  \
             ${OUTDIR}/${YYYY_MM}/SST-SIC_${YYYY}${MM}_tmp.nc

${CDO} -s -P ${OMP_THREADS_CONV2ICON} ${GCM_REMAP},${INIDIR}/triangular-grid.nc \
               ${OUTDIR}/${YYYY_MM}/SST-SIC_${YYYY}${MM}_tmp.nc  \
               ${OUTDIR}/${YYYY_MM}/LOWBC_${YYYY}_${MM}.nc

#... Clean up:
rm -f ${OUTDIR}/${YYYY_MM}/*_tmp*

#-------------------------------------------------------------------------------
# PART III: Extract lateral boundary data
#-------------------------------------------------------------------------------
echo ----- start CONV2ICON for LATBC

#... The vertical coordinate coefficients has not been transfered by iconremap
#    due to an error in the cdilib. They have to be added here again:
cd ${OUTDIR}

COUNTPP=0
for FILE in ${DATAFILELIST}
do
(
  FILEOUT=$(basename ${FILE} .nc)
#  ${CDO} -s -P ${OMP_THREADS_CONV2ICON} remap,${LAM_GRID},${WORKDIR}/${EXPID}/joboutputs/conv2icon/${GCM_REMAP}_weights.nc ${FILE} ${OUTDIR}/${YYYY_MM}/${FILEOUT}_lbc.nc
  ${CDO} -s -P ${OMP_THREADS_CONV2ICON} ${GCM_REMAP},${INIDIR}/triangular-grid.nc -selname,T,U,V,W,LNPS,GEOP_ML,QV,QC,QI${ICON_INPUT_OPTIONAL} ${FILE} ${OUTDIR}/${YYYY_MM}/${FILEOUT}_lbc.nc
  ${NCO_BINDIR}/ncks -h -A ${INIDIR}/hyai_hybi.nc ${OUTDIR}/${YYYY_MM}/${FILEOUT}_lbc.nc
  ${NCO_BINDIR}/ncrename -d level,lev ${OUTDIR}/${YYYY_MM}/${FILEOUT}_lbc.nc
  ${NCO_BINDIR}/ncrename -d cell,ncells ${OUTDIR}/${YYYY_MM}/${FILEOUT}_lbc.nc
  ${NCO_BINDIR}/ncrename -d nv,vertices ${OUTDIR}/${YYYY_MM}/${FILEOUT}_lbc.nc
)&
    (( COUNTPP=COUNTPP+1 ))
    if [ ${COUNTPP} -ge ${MAXPP} ]
    then
      COUNTPP=0
      wait
    fi
done
wait

if [ ${CURRENT_DATE} -eq ${YDATE_START}  ]
then
   cp ${OUTDIR}/${YYYY_MM}/${GCM_PREFIX}${YDATE_START}_lbc.nc ${INIDIR}
fi

#-------------------------------------------------------------------------------
# CLEAN-UP:
#-------------------------------------------------------------------------------
rm -r ${INPDIR}/${YYYY_MM}

#-------------------------------------------------------------------------------
# submit next jobs
#-------------------------------------------------------------------------------
DATELOG=$(cat ${PFDIR}/${EXPID}/date.log)
if [ ${CURRENT_DATE} -eq ${YDATE_START} ] || [ ${CURRENT_DATE} -eq ${DATELOG} ]
then

  #################################################
  # submit ICON job
  #################################################

  cd ${PFDIR}/${EXPID}
  ${PFDIR}/${EXPID}/subchain icon
fi

#-----------------------------------------------------------------------------
DATE_END=$(date +%s)
SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")

echo END ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/conv2icon/finish_joblist
echo "conv2icon ${YYYY_MM} FINISHED $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
#-----------------------------------------------------------------------------
echo ----- CONV2ICON finished

