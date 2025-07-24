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

############################################################
# Post-processing ICON data
# Trang Van Pham, DWD 20.03.2018 initial version adapted from COSMO-CLM post-processing script (Burkhardt Rockel, Hereon)
# Burkhardt Rockel, Hereon, 2020, included in SPICE (Starter Package for ICON Experiments)
############################################################

#################################################
#  Pre-Settings
#################################################

#... get the job_settings environment variables
source ${PFDIR}/${EXPID}/job_settings

# load the necessary modules
module load cdo/${CDO_VERSION}
module load nco/${NCO_VERSION}
module load netcdf-c/4.9.2

  INPDIR=${SCRATCHDIR}/${EXPID}/input/post
  OUTDIR=${WORKDIR}/${EXPID}/post
  if [[ ${#CURRENT_DATE} -eq 10 ]]
  then
    NEXT_DATE=$(${CFU} get_next_dates ${CURRENT_DATE} 01:00:00 ${ITYPE_CALENDAR} | cut -c1-10)
  else
    NEXT_DATE=$(${CFU} get_next_dates ${CURRENT_DATE} 01:00:00 ${ITYPE_CALENDAR} | cut -c1-14)
  fi
  PREV_DATE=$(${CFU} get_prev_date  ${CURRENT_DATE} 01:00:00 ${ITYPE_CALENDAR} | cut -c1-10)

  YYYY=${CURRENT_DATE:0:4}
  MM=${CURRENT_DATE:4:2}
  YYYY_MM=${YYYY}_${MM}
  YDATE_NEXT=${NEXT_DATE}
  YYYY_NEXT=${NEXT_DATE:0:4}
  MM_NEXT=${NEXT_DATE:4:2}
  YYYY_PREV=${PREV_DATE:0:4}
  MM_PREV=${PREV_DATE:4:2}

  ISO_NEXT_DATE=${NEXT_DATE:0:8}T${NEXT_DATE:8:2}0000Z

#... set maximum number of parallel processes
  (( MAXPP=TASKS_POST ))

#################################################
#  Main part
#################################################

echo "post      ${YYYY_MM} START    $(date)" >> ${PFDIR}/${EXPID}/chain_status.log
echo START ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/post/finish_joblist
DATE_START=$(date +%s)
ERROR_delete=0 # error flag for deletion of output in ${SCRATCHDIR}

#... load the functions to calculate timeseries and additional parameters
export CURRENT_DATE
export INPDIR
export OUTDIR
export YYYY_MM
source ${PFDIR}/${EXPID}/scripts/functions.inc


# post processing for ICON
#
#################################################
# post processing the data (e.g. daily, monthly means, creating time series etc.)
#################################################

##################################################################################################
# build time series
##################################################################################################

if [[ ${ITYPE_TS} -ne 0 ]] # if no time series are required skip a lot
then

if [[ ${ONLY_YEARLY} -eq 0 ]]  # if ONLY_YEARLY=1 no calculation of time series are needed
then
#set -xv
#... create some files and directories (needed to be done just once at the beginning of the simulation)
if [[ ${CURRENT_DATE} -eq ${YDATE_START} ]]
then
  #... save the constant file
  if [[ ! -f ${OUTDIR}/icon_c.nc ]]
  then
    cp ${INPDIR}/icon_c.nc ${OUTDIR}/icon_c.nc
   #   rm ${INPDIR}/icon_${YDATE_START:0:8}T${YDATE_START:8:2}0000Zc.nc
      ${NCO_BINDIR}/ncks -h -v clon,clat,clon_bnds,clat_bnds ${OUTDIR}/icon_c.nc ${OUTDIR}/icon_grid.nc
      ${NCO_BINDIR}/ncatted -h -a ,global,d,, ${OUTDIR}/icon_grid.nc
  fi
  if [[ ! -f ${OUTDIR}/icon_c.nc ]]
  then
    echo ERROR, file not exists: ${OUTDIR}/icon_c.nc
    DATE_END=$(date +%s)
    SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
    echo "post      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
    exit
  fi
  iconcor 0 00:00:00 ${OUTDIR}/icon_c.nc

  if [[ ${CURRENT_DATE} -eq ${YDATE_START} ]]
  then
    #... Field capacity, pore volume and wilting point is written to the constant file
    timeseries FIELDCAP
  fi

  #weights with source mask by using usual icon output
  ${CDO} -P ${OMP_THREADS_POST} gennn,${TARGET_GRID} ${OUTDIR}/icon_c.nc ${OUTDIR}/remapnn_weights.nc

  ${CDO} -s -P ${OMP_THREADS_POST} remap,${TARGET_GRID},${OUTDIR}/remapnn_weights.nc ${OUTDIR}/icon_c.nc ${OUTDIR}/${EXPID}_c.nc
  ${CDO} -s setmissval,-1.E20 ${OUTDIR}/${EXPID}_c.nc tmp.nc
  mv tmp.nc ${OUTDIR}/${EXPID}_c.nc
  

  if [[ ${ITYPE_TS} -eq 2 ]] || [[ ${ITYPE_TS} -eq 3 ]]    # in case of yearly time series
  then
    [[ -d ${OUTDIR}/yearly/HSURF ]] || mkdir -p  ${OUTDIR}/yearly/HSURF
    if [ ! -f ${OUTDIR}/yearly/HSURF/HSURF.nc ]
    then
      ${NCO_BINDIR}/ncks -h -v HSURF ${OUTDIR}/${EXPID}_c.nc ${OUTDIR}/yearly/HSURF/HSURF.nc
    fi
    [[ -d ${OUTDIR}/yearly/FR_LAND ]] || mkdir -p  ${OUTDIR}/yearly/FR_LAND
    if [ ! -f ${OUTDIR}/yearly/FR_LAND/FR_LAND.nc ]
    then
      ${NCO_BINDIR}/ncks -h -v FR_LAND ${OUTDIR}/${EXPID}_c.nc ${OUTDIR}/yearly/FR_LAND/FR_LAND.nc
    fi
  fi
fi
    ####
    ##For repairment-runs: in case the data are coming from archieved tar-file they have to be unzipped
    ####
    mkdir -p ${INPDIR}/${YYYY_MM}
    cd ${INPDIR}/${YYYY_MM}/
##BG    if [[ -n "$(ls -A  */icon_*.ncz 2>/dev/null)" ]] && [[ $(ls -A */*nc | wc -l) -ne $(ls -A */*ncz | wc -l) ]];
    if [[ -n "$(ls -A  out*/icon_*.ncz 2>/dev/null)" ]] && [[ $(ls -A */*nc | wc -l) -ne $(ls -A */*ncz | wc -l) ]];
    then
	export COUNTPP=0
	echo  ${INPDIR}/${YYYY_MM}/ contains ncz-files which have to be unzipped befores timeseries can be build
##BG      for file in */icon_*.ncz ; do
      for file in out*/icon_*.ncz ; do
        ofile=${file%ncz}nc
        nccopy -k 4 -d 0 $file $ofile &
        (( COUNTPP=COUNTPP+1 ))
        if [[ ${COUNTPP} -ge ${MAXPP} ]]
        then
          COUNTPP=0
          wait
        fi
        wait
     done
	echo unzipping of ncz-files in ${INPDIR}/${YYYY_MM}/ done
	rm ${INPDIR}/${YYYY_MM}/*/*ncz
     fi 

#################################################
# run conv2icon_nest to preprocess nesting data
#################################################
if [[ ${LCONV_NEST} -eq 1 ]]; then

  echo 'run conv2icon_nest to produce input data for the nest'
  cd ${PFDIR}/${EXPID} ; ./subchain conv2icon_nest ${YYYY}${MM}0100

fi

if [[ ! -d ${OUTDIR}/${YYYY_MM} ]]
then
  mkdir ${OUTDIR}/${YYYY_MM}
fi
cd ${OUTDIR}/${YYYY_MM}

#... time series part 1
echo time series part 1  --- build time series for selected variables
# --- build time series for selected variables
ts_command_list=(
#'timeseries W_I       out01 remapnn'
#
'timeseries ASOB_S    out02 remapnn' #sob_s
'timeseries ASODIFU_S out02 remapnn' #sou_s						 
'timeseries ATHB_S    out02 remapnn' #thb_s
'timeseries ATHU_S    out02 remapnn' #thu_s						
'timeseries ASODIFD_S out02 remapnn' #sodifd_s
'timeseries ALHFL_S   out02 remapnn' #lhfl_s
'timeseries ASHFL_S   out02 remapnn' #shfl_s
'timeseries AEVAP_S   out02 remapnn' #qhfl_s
'timeseries ACLCT_MOD out02 remapnn' #clct_mod
'timeseries ACLCT     out02 remapnn' #clct
'timeseries ATHB_T    out02 remapnn' #thb_t							
'timeseries ASOB_T    out02 remapnn' #sob_t
'timeseries ASOD_T    out02 remapnn' #sod_t
'timeseries AT_2M     out02 remapnn' #t_2m
'timeseries ARELHUM_2M  out02 remapnn' #rh_2m
#
'timeseries AUMFL_S   out02 remapnn' #umfl_s
'timeseries AVMFL_S   out02 remapnn' #vmfl_s

'timeseries ACLCH     out03 remapnn' #clch
'timeseries ACLCM     out03 remapnn' #clcm
'timeseries ACLCL     out03 remapnn' #clcl
'timeseries ASP_10M   out02 remapnn' #sp_10m - hourly for pot. evap calculation
'timeseries ASWFLX_DN_CS   out03 remapnn' #swflx_dn_clr
'timeseries ASWFLX_UP_CS   out03 remapnn' #swflx_up_clr
'timeseries ALWFLX_DN_CS   out03 remapnn' #lwflx_dn_clr
'timeseries ALWFLX_UP_CS   out03 remapnn' #lwflx_up_clr
##'timeseries swflx_dn_clr   out03 remapnn' #swflx_dn_clr
##'timeseries swflx_up_clr   out03 remapnn' #swflx_up_clr
##'timeseries lwflx_dn_clr   out03 remapnn' #lwflx_dn_clr
##'timeseries lwflx_up_clr   out03 remapnn' #lwflx_up_clr
##'timeseries Z0        out03 remapnn' #lwflx_up_clr
#
'timeseries CIN_ML    out04 remapnn'
'timeseries CAPE_ML   out04 remapnn'
'timeseries HPBL      out04 remapnn' #boundary layer height above sea level [m]
'timeseries T_2M      out04 remapnn' #t_2m
'timeseries T_G       out04 remapnn' #t_g
'timeseries TOT_PREC  out04 remapnn' #tot_prec
'timeseries TQV       out04 remapnn' #tqv
'timeseries TQC       out04 remapnn' #tqc
'timeseries TQI       out04 remapnn' #tqi
'timeseries RAIN_CON  out04 remapnn' #rain_con
'timeseries RAIN_GSP  out04 remapnn' #rain_gsp
'timeseries SNOW_CON  out04 remapnn' #snow_con
'timeseries SLI       out04 remapnn' #surface lifted index
'timeseries SNOW_GSP  out04 remapnn' #snow_gsp
'timeseries QV_2M     out04 remapnn' #qv_2m
'timeseries RELHUM_2M out04 remapnn' #rh_2m
'timeseries PMSL      out04 remapnn' #pres_msl
'timeseries PS        out04 remapnn' #pres_sfc
'timeseries SP_10M    out04 remapnn' #sp_10m
'timeseries U_10M     out04 remapnn' #u_10m
'timeseries V_10M     out04 remapnn' #v_10m
'timeseries W_I       out04 remapnn'
'timeseries W_SO      out04 remapnn' #w_so
'timeseries W_SO_ICE  out04 remapnn' #w_so_ice
#
'timeseries SOBS_RAD  out05 remapnn' #sob_s
'timeseries SODIFU_S  out05 remapnn' #sou_s
'timeseries SODIFD_S  out05 remapnn' #sodifd_s
#
'timeseries RUNOFF_S  out06 remapnn' #runoff_s
'timeseries RUNOFF_S_T_8  out06 remapnn' #runoff_s
'timeseries RUNOFF_G  out06 remapnn' #runoff_g
'timeseries RESID_WSO out06 remapnn' #resid_wso
'timeseries W_SNOW    out06 remapnn' #w_snow
'timeseries H_SNOW    out06 remapnn' #h_snow
'timeseries FR_SNOW   out06 remapnn' #snowfrac
'timeseries SNOW_MELT out06 remapnn' #meltrate
#
'timeseries TMAX_2M   out07 remapnn' #tmax_2m
'timeseries TMIN_2M   out07 remapnn' #tmin_2m
'timeseries DURSUN    out07 remapnn' # sunshine duration [s]
'timeseries SPGUST_10M  out07 remapnn' #gust10
#
'timeseries CAPE_MLMAX out08 remapnn' #cape_ml daily max
'timeseries CIN_MLMAX out08 remapnn' #cin_ml
'timeseries LAIMAX    out08 remapnn' #lai
'timeseries PLCOVMAX  out08 remapnn' #plcov
#'timeseries ROOTDPMAX out08 remapnn' #rootdp
'timeseries SLIMAX    out08 remapnn' #gz0
'timeseries SPMAX_10M out08 remapnn' #sp_10m daily max
'timeseries Z0MAX     out08 remapnn' #gz0
#
'timeseries T_SO      out12 remapnn' #t_so
'timeseries H_ICE     out12 remapnn' #h_ice
'timeseries T_ICE     out12 remapnn' #t_ice
'timeseries T_SNOW    out12 remapnn' #t_snow
'timeseries T_SKIN    out12 remapnn' #t_sk
#
'timeseries AAOD_550NM out13 remapnn' #fr_seaice
'timeseries AFR_SEAICE out13 remapnn' #fr_seaice
'timeseries AZ0        out13 remapnn' #fr_seaice

)

NUMFILES=${#ts_command_list[@]}
echo NUMFILES after part 1 $NUMFILES .

export COUNTPP=0
for ts_command in "${ts_command_list[@]}"
do
  ${ts_command} &
  (( COUNTPP=COUNTPP+1 ))
  if [[ ${COUNTPP} -ge ${MAXPP} ]]
  then
    COUNTPP=0
    wait
  fi
done
wait

#... time series part 2
echo time series part 2 --- building a time series for a given quantity on pressure- and z-levels
#... building a time series for a given quantity on pressure- and z-levels

ts_command_list=(
'timeseriesz U        out09 HLEVS[@]     remapnn'
'timeseriesz V        out09 HLEVS[@]     remapnn'
'timeseriesz QV       out09 HLEVS[@]     remapnn'
'timeseriesz T        out09 HLEVS[@]     remapnn'
'timeseriesp FI       out10 PLEVS_NUK[@] remapnn'
'timeseriesp RELHUM   out10 PLEVS_NUK[@] remapnn'
'timeseriesp T        out10 PLEVS_NUK[@] remapnn'
'timeseriesp U        out10 PLEVS_NUK[@] remapnn'
'timeseriesp V        out10 PLEVS_NUK[@] remapnn'
'timeseriesp W        out10 PLEVS_NUK[@] remapnn'
'timeseriesp QV       out10 PLEVS_NUK[@] remapnn'
'timeseriesp FI       out11 PLEVS_COR[@] remapnn'
'timeseriesp T        out11 PLEVS_COR[@] remapnn'
'timeseriesp U        out11 PLEVS_COR[@] remapnn'
'timeseriesp V        out11 PLEVS_COR[@] remapnn'
'timeseriesp W        out11 PLEVS_COR[@] remapnn'
'timeseriesp QV       out11 PLEVS_COR[@] remapnn'
)

#... counting number of files to be created
for ts_command in "${ts_command_list[@]}"
do
  if ($(grep -q 'PLEVS_NUK' <<< ${ts_command}))
  then
    NUMFILES=$((${NUMFILES} + ${#PLEVS_NUK[@]}))
  elif ($(grep -q 'PLEVS_COR' <<< ${ts_command}))
  then
    NUMFILES=$((${NUMFILES} + ${#PLEVS_COR[@]}))
  elif ($(grep -q 'ZLEVS' <<< ${ts_command}))
  then
    NUMFILES=$((${NUMFILES} + ${#ZLEVS[@]}))
  elif ($(grep -q 'HLEVS' <<< ${ts_command}))
  then
    NUMFILES=$((${NUMFILES} + ${#HLEVS[@]}))
  fi
done
echo NUMFILES after part 2 $NUMFILES .

COUNTPP=0
for ts_command in "${ts_command_list[@]}"
do
  ${ts_command} &
  (( COUNTPP=COUNTPP+1 ))
  if [[ ${COUNTPP} -ge ${MAXPP} ]]
  then
    COUNTPP=0
    wait
  fi
done
wait

#... time series part 3
echo time series part 3 --- building additional time series for a given quantities on pressure- and z-levels
#... building additional time series for a given quantities on pressure- and z-levels
#...   these quantities are based on the time series in part 2
ts_command_list=(
#'timeseriesap SP            PLEVS[@] '
#'timeseriesap DD            PLEVS[@] '
#'timeseriesaz SP            ZLEVS[@]  NN '
#'timeseriesaz DD            ZLEVS[@]  NN '
'timeseriesaz SP            HLEVS[@] '
'timeseriesaz DD            HLEVS[@] '
)

#... counting number of files to be created
for ts_command in "${ts_command_list[@]}"
do
  if ($(grep -q 'PLEVS' <<< ${ts_command}))
  then
    NUMFILES=$((${NUMFILES} + ${#PLEVS[@]}))
  elif ($(grep -q 'ZLEVS' <<< ${ts_command}))
  then
    NUMFILES=$((${NUMFILES} + ${#ZLEVS[@]}))
  elif ($(grep -q 'HLEVS' <<< ${ts_command}))
  then
    NUMFILES=$((${NUMFILES} + ${#HLEVS[@]}))
  fi
done
echo NUMFILES after part 3 $NUMFILES .

COUNTPP=0
for ts_command in "${ts_command_list[@]}"
do
  ${ts_command} &
  (( COUNTPP=COUNTPP+1 ))
  if [[ ${COUNTPP} -ge ${MAXPP} ]]
  then
    COUNTPP=0
    wait
  fi
done
wait

#... time series part 4
echo time series part 4 --- building additional quantities calculated from the quantities in part 1
#... !!! any additional quantities calculated from the quantities in part 1
#... should be included here !!!
#... one has to split the list in two parts, if in case of parallel computation
#...    variables depend on other additional variables (e.g. ASOD_S depends on ASODIRD_S)

ts_command_list=(
'timeseries RUNOFF_S_corr'    # runoff_s correction for lake shores; arguments are outputintervals of RUNOFF_S, TOT_PREC, and AEVAP_S
'timeseries ASOD_S'      # sob_s + sou_s
'timeseries ASODIRD_S'   # sob_s + sou_s - sodifd_s
'timeseries ASOU_T'      # sod_t - sob_t
'timeseries ATHD_S'      # thb_s + thu_s
#'timeseries DD_10M'      #
'timeseries PREC_CON'    # rain_con + snow_con
'timeseries SOD_S'       # sob_s + sou_s
'timeseries SODIRD_S'    # sob_s +sou_s -sodifd_s
'timeseries TOT_SNOW'    # snow_gsp + snow_con
'timeseries TQW'         # tqc + tqi
'timeseries T_SNOW'      # set t_snow to _FillValue where fr_snow = 0 
#'timeseries APOTEVAP_S'  #
)
num_double_entries=1     # number of corrected quantities, which therefore occur twice in the ts_command_list

NUMFILES=$((${NUMFILES} + ${#ts_command_list[@]} - $num_double_entries))
echo NUMFILES after part 4 $NUMFILES .

export COUNTPP=0
for ts_command in "${ts_command_list[@]}"
do
  ${ts_command} &
  (( COUNTPP=COUNTPP+1 ))
  if [[ ${COUNTPP} -ge ${MAXPP} ]]
  then
    COUNTPP=0
    wait
  fi
done
wait
#... time series part 5
echo time series part 5 --- building additional quantities calculated from the quantities in part 1
#... !!! any additional quantities calculated from the quantities in part 4
#... should be included here !!!
#... one has to split the list in two parts, if in case of parallel computation
#...    variables depend on other additional variables (e.g. ASOD_S depends on ASODIRD_S)

ts_command_list=(
'timeseries RUNOFF_T'    # runoff_s + runoff_g
)

NUMFILES=$((${NUMFILES} + ${#ts_command_list[@]}))
echo NUMFILES after part 5 $NUMFILES .

export COUNTPP=0
for ts_command in "${ts_command_list[@]}"
do
  ${ts_command} &
  (( COUNTPP=COUNTPP+1 ))
  if [[ ${COUNTPP} -ge ${MAXPP} ]]
  then
    COUNTPP=0
    wait
  fi
done
wait
#chgrp $PROJECT_ACCOUNT ${OUTDIR}/${YYYY_MM}/*
#chgrp bg1155 ${OUTDIR}/${YYYY_MM}/*
###############################################################
# remove the icon output for YYYY_MM from the SCRATCH directory
# Safety check whether *tmp files exist. In that case something
# may have gone wrong and the directory is not deleted in order
# to run " subchain post YYYYMMDD00" again interactively
###############################################################

echo ... checking the number of files in ${WORKDIR}/${EXPID}/post/${YYYY_MM} - ${NUMFILES} files are expected
if [[ $(ls -1 ${WORKDIR}/${EXPID}/post/${YYYY_MM} | wc -l) -ne ${NUMFILES} ]]
then
   echo ... wrong number of files exist: $(ls -1 ${WORKDIR}/${EXPID}/post/${YYYY_MM} | wc -l)
   echo ... ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_MM} not deleted
   ERROR_delete=1
else
  echo "      OK, all time series files found"
  echo ... checking for corrupted tmp files
  set +e
  ls ${WORKDIR}/${EXPID}/post/${YYYY_MM}/*tmp  2> /dev/null
  ERROR=$?
  set -e
  if [[ ${ERROR} -eq 0 ]]
  then
     echo ... tmp files found in ${WORKDIR}/${EXPID}/post/${YYYY_MM}
     echo ... ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_MM} not deleted
     ERROR_delete=1
  else
  echo "      OK, no tmp file found"
  echo ... checking if time series are on rotated grid
    ERROR=0
    FILELIST=$(ls -1 ${WORKDIR}/${EXPID}/post/${YYYY_MM}) 
    for FILE in ${FILELIST}
    do
      if [[ "x$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'rotated')" == "x" ]]
      then
        ERROR=1
        echo ${FILE}
      fi
    done
    if [[ ${ERROR} -eq 1 ]]
    then
      echo ... not all time series files are on rotated grid
      echo ... ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_MM} not deleted
      ERROR_delete=1
    else
     echo "      OK, all files are on rotated grid"
      if [[ ITYPE_SAMOVAR_TS -eq 1 ]]
      then
        echo ... checking output variables for valid range - the limits are given in ${SAMOVAR_LIST_TS}
        set +e
        #FILELIST=$(ls -1 ${WORKDIR}/${EXPID}/post/${YYYY_MM}/*ts.nc)
	FILELIST=$(ls -1 ${WORKDIR}/${EXPID}/post/${YYYY_MM}/*ts.nc | grep -v uncorr) # exclude uncorrected timeseries from samovar check
        ${SAMOVAR_SH} F ${SAMOVAR_LIST_TS} ${WORKDIR}/${EXPID}/joblogs/post/samovar_${YYYY_MM}_ts.log "${FILELIST}"
        ERROR_STATUS=$?
        if [[ $ERROR_STATUS -eq 0 ]]
        then
          echo SAMOVAR check for time series -- OK -- log file ${WORKDIR}/${EXPID}/joblogs/post/samovar_${YYYY_MM}_ts.log deleted
	  rm ${WORKDIR}/${EXPID}/joblogs/post/samovar_${YYYY_MM}_ts.log
        else
          echo SAMOVAR check for time series -- FAILED --
          echo Error in post occured. > ${PFDIR}/${EXPID}/error_message
          echo Date: ${YYYY} / ${MM} >> ${PFDIR}/${EXPID}/error_message
          echo Error in checking time series by SAMOVAR >> ${PFDIR}/${EXPID}/error_message
          echo check ${WORKDIR}/${EXPID}/joblogs/post/samovar_${YYYY_MM}_ts.log >> ${PFDIR}/${EXPID}/error_message
          if [ -n "${NOTIFICATION_ADDRESS}" ]
          then
            ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
          fi
          DATE2=$(date +%s)
          SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")
          echo "post      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
          exit 2 # do not comment this line but edit the SAMOVAR limits in ${SAMOVAR_LIST_TS}
        fi
        set -e
      fi
    fi
  fi
fi

fi # ONLY_YEARLY

#################################################
# calculate yearly time series from the monthly ones
#################################################
if [[ ${ITYPE_TS} -eq 2 ]] || [[ ${ITYPE_TS} -eq 3 ]]    # yearly time series
then

  #... check whether a year is completed and perform the yearly time series in that case
  #... ATTENTION: the yearly time series will not work properly for the last simulation year,
  #...               if YDATE_STOP is the 1st of February
  if [[ ${MM#0*} -eq 1 ]] && [[ ${CURRENT_DATE} -ne ${YDATE_START} ]]
  then

    if [[ $(ls -d1 ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_PREV}* 2> /dev/null | wc -l) -gt 0 ]]
    then
      echo Not all post-processing jobs have run successfully for ${YYYY_PREV}
      echo Please check the following dates and run the \"subchain post YYYYMMDDHH\" manually for these months again
      echo   before re-running the yearly collection for ${YYYY_PREV}
      ls -d1 ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_PREV}*
      if [[ -n "${NOTIFICATION_ADDRESS}" ]]
      then
        echo Not all post-processing jobs have run successfully for ${YYYY_PREV}> ${PFDIR}/${EXPID}/finish_message
        echo Please check the following dates and run the \"subchain post YYYYMMDDHH\" manually for these months again >> ${PFDIR}/${EXPID}/finish_message
        echo   before re-running the yearly collection for ${YYYY_PREV} >> ${PFDIR}/${EXPID}/finish_message
        ls -d1 ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_PREV}*  >> ${PFDIR}/${EXPID}/finish_message
        ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "ICON-CLM ${EXPID} job finished" ${PFDIR}/${EXPID}/finish_message
      fi
    else
      echo building yearly time series
       
      source ${PFDIR}/${EXPID}/scripts/post_yearly_cmor.inc
      ## check if all yearly files for ${YYYY_PREV} were produced properly
      NFILES=$(ls -1 ${OUTDIR}/${YYYY_PREV}_12 | wc -l)
      NFILES_yearly=$(ls -1 ${OUTDIR}/yearly/*/*_${YYYY_PREV}* | wc -l)
      let "YYYY_PREV_PREV = YYYY-2"
      if [ ${YYYY_PREV_PREV} -ge ${YDATE_START:0:4} ]; then
	  ##echo "ls -1 ${OUTDIR}/yearly/SODIFD_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SOD_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SODIRD_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SODIFU_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SOBS_RAD/*_${YYYY_PREV_PREV}* | wc -l"
        NFILES_yearly_rad=$(ls -1 ${OUTDIR}/yearly/SODIFD_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SOD_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SODIRD_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SODIFU_S/*_${YYYY_PREV_PREV}* ${OUTDIR}/yearly/SOBS_RAD/*_${YYYY_PREV_PREV}* | wc -l) ## yearly time series of SODIFD_S,SODIRD_S,SODIFU_S,SOD_S,SOBS_RAD are produced for the previous year
      else
	NFILES_yearly_rad=0  
      fi
      ((NFILES_y=NFILES_yearly_rad+NFILES_yearly))
	if [[ ${NFILES} -ne ${NFILES_y} ]]
      then
        echo ERROR: Not the same number of yearly files for ${YYYY_PREV} as files in ${YYYY_PREV}_12 are produced.

        if [ -n "${NOTIFICATION_ADDRESS}" ]
        then
          echo Error in post before building yearly time series > ${PFDIR}/${EXPID}/error_message
          echo Not all directories of ${OUTDIR}/yearly contain the same number of files for ${YYYY_PREV} as ${OUTDIR}/${YYYY_PREV}_${MM} >> ${PFDIR}/${EXPID}/error_message
          ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors in post" ${PFDIR}/${EXPID}/error_message
          rm ${PFDIR}/${EXPID}/error_message
        fi
      else
	echo checking readability of the yearly files
        ERROR_delete=0
        FILELIST=$(ls -1 ${OUTDIR}/yearly/*/*_${YYYY_PREV}*)
        for FILE in ${FILELIST}
	do
	    [[ ! $($CDO showvar $FILE  2> /dev/null ) ]] &&  ERROR_delete=1
	done
	if [[ $ERROR_delete -eq 1 ]]
	then
	  echo ERROR: Not all yearly timeseries of ${YYYY} are readable - you have to redo the process!
	  if [ -n "${NOTIFICATION_ADDRESS}" ]
          then
            echo Error in post > ${PFDIR}/${EXPID}/error_message
            echo Not all files in  ${OUTDIR}/yearly for ${YYYY} are readable
            ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors in post" ${PFDIR}/${EXPID}/error_message
            rm ${PFDIR}/${EXPID}/error_message
	  fi
        else 
          echo yearly time series built successfully
        fi
        if [[ ${ITYPE_TS} -eq 2 ]]
        then
##          rm -rf ${OUTDIR}/${YYYY_PREV}_??
          rm -rf ${OUTDIR}/${YYYY_PREV}_0[2-9] ${OUTDIR}/${YYYY_PREV}_1[01] # January and december might be needed later on for repair jobs
        fi
      fi
    fi
  elif [[ ${NEXT_DATE} -eq ${YDATE_STOP} ]]
  then

    if [[ $(ls -d1 ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY}_0[1-9]* ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY}_1[01]*  2> /dev/null | wc -l) -gt 0 ]]
    then
      ERROR_delete=1
      echo Not all post-processing jobs have run successfully for ${YYYY}
      echo Please check the following dates and run the \"subchain post YYYYMMDDHH\" manually for these months again
      echo   before re-running the yearly collection for ${YYYY}
      ls -d1 ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY}*
      if [[ -n "${NOTIFICATION_ADDRESS}" ]]
      then
        echo Not all post-processing jobs have run successfully for ${YYYY}.> ${PFDIR}/${EXPID}/finish_message
        echo Please, check the following dates and run the \"subchain post YYYYMMDDHH\" manually for these months again >> ${PFDIR}/${EXPID}/finish_message
        echo   before re-running the yearly collection for ${YYYY} >> ${PFDIR}/${EXPID}/finish_message
        ls -d1 ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY}*  >> ${PFDIR}/${EXPID}/finish_message
        ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "ICON-CLM ${EXPID} job finished" ${PFDIR}/${EXPID}/finish_message
      fi
    else

      echo building yearly time series
      source ${PFDIR}/${EXPID}/scripts/post_yearly_cmor.inc
      ## check if all yearly files were produced properly
      NFILES=$(ls -1 ${OUTDIR}/${YYYY}_${MM} | wc -l)
      if [ ${NFILES} -ne $(ls -1 ${OUTDIR}/yearly/*/*_${YYYY}* | wc -l) ]
      then
        ERROR_delete=1
        echo ERROR: Not all monthly directories of ${YYYY} contain the same number of files
        if [ -n "${NOTIFICATION_ADDRESS}" ]
        then
          echo Error in post > ${PFDIR}/${EXPID}/error_message
          echo Not all directories of ${OUTDIR}/yearly contain the same number of files for ${YYYY} as ${OUTDIR}/${YYYY}_${MM}
          ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors in post" ${PFDIR}/${EXPID}/error_message
          rm ${PFDIR}/${EXPID}/error_message
        fi
      else
	echo checking readability of the yearly files
        ERROR_delete=0
        FILELIST=$(ls -1 ${OUTDIR}/yearly/*/*_${YYYY}*)
        for FILE in ${FILELIST}
	do
	    [[ ! $(cdo showvar $FILE  2> /dev/null ) ]] &&  ERROR_delete=1
	done
	if [[ $ERROR_delete -eq 1 ]]
	then
	  echo ERROR: Not all yearly timeseries of ${YYYY} are readable - you have to redo the process!
	  if [ -n "${NOTIFICATION_ADDRESS}" ]
          then
            echo Error in post > ${PFDIR}/${EXPID}/error_message
            echo Not all files in  ${OUTDIR}/yearly for ${YYYY} are readable
            ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors in post" ${PFDIR}/${EXPID}/error_message
            rm ${PFDIR}/${EXPID}/error_message
	  fi
      else
          echo yearly time series built successfully
        if [[ ${ITYPE_TS} -eq 2 ]]
        then
          rm -rf ${OUTDIR}/${YYYY}_0[2-9] ${OUTDIR}/${YYYY}_1[01] # January and december might be needed later on for repair jobs
	  set +e
          DIRNN=$(ls -df ${OUTDIR}/????_0[2-9] ${OUTDIR}/????_1[01] |wc -l) # check whether all yearly files were produced successfully
	  set -e
          if [[ $DIRNN -ne 0 ]]
          then
            echo Number of unexpected directories in ${OUTDIR}: $DIRNN - please check the completeness of yearly files
##neu            echo Unexpected directories in ${OUTDIR} found: $DIRLIST - please check the completeness of yearly files
	    echo These data and the all data from Januaries and Decembers are still available for repair yearly fiels.
            echo Unexpected directories in ${OUTDIR} found > ${PFDIR}/${EXPID}/error_message
            ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} found errors in post-yearly" ${PFDIR}/${EXPID}/error_message
            rm ${PFDIR}/${EXPID}/error_message
          else
            rm -rf ${OUTDIR}/????_01 ${OUTDIR}/????_12
          fi	    
        fi
	fi
      fi
    fi
  fi

  if [[ ${ONLY_YEARLY} -eq 1 ]]  # if ONLY_YEARLY=1 no calculation of time series are needed
  then
    DATE_END=$(date +%s)
    SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
    echo total time for postprocessing: ${SEC_TOTAL} s

    echo "post      ${YYYY_MM} FINISHED $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
    exit
  fi

else  # no yearly time series

#################################################
# compress data
#################################################
case ${ITYPE_COMPRESS_POST} in

0)        #... no compression

  echo "**** no compression ****"
  ;;

1)        #... internal netCDF compression

  echo "**** internal netCDF compression"
  cd ${OUTDIR}/${YYYY_MM}

  FORMAT_SUFFIX=ncz
  COUNTPP=0
  FILELIST=$(ls -1)
  for FILE in ${FILELIST}
  do
    (
      ${NC_BINDIR}/nccopy -d 1 -s ${FILE} $(basename ${FILE} .nc).${FORMAT_SUFFIX}
      rm ${FILE}
    )&
    (( COUNTPP=COUNTPP+1 ))
    if [[ ${COUNTPP} -ge ${MAXPP} ]]
    then
      COUNTPP=0
      wait
    fi
  done
  wait
  ;;

2)       #... gzip compression

  echo "**** gzip compression"
  cd ${OUTDIR}/${YYYY_MM}

  COUNTPP=0
  FILELIST=$(ls -1)
  for FILE in ${FILELIST}
  do
    gzip ${FILE} &
    (( COUNTPP=COUNTPP+1 ))
    if [[ ${COUNTPP} -ge ${MAXPP} ]]
    then
      COUNTPP=0
      wait
    fi
  done
  wait
  ;;

3)       #... pigz compression

  echo "**** pigz compression"
  cd ${OUTDIR}/${YYYY_MM}

  FILELIST=$(ls -1)
  for FILE in ${FILELIST}
  do
echo    ${PIGZ} --fast -p ${MAXPP} ${FILE}
    ${PIGZ} --fast -p ${MAXPP} ${FILE}
  done
  ;;

*)

  echo "**** invalid value for  ITYPE_COMPRESS_ARCH: "${ITYPE_COMPRESS_POST}
  echo "**** no compression applied"
  ;;

esac

fi  # end of ITYPE_TS if clause

fi  # end of [[ ITYPE_TS -ne 0 ]] loop
###################
if [[ $ERROR_delete -eq 0 ]] ; then
  echo ... deleting icon output and arch output of current month on scratch
  rm -rf ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_MM}
  rm -rf ${SCRATCHDIR}/${EXPID}/output/arch/${YYYY_MM}/out*
fi

cd ${OUTDIR}

DATE_END=$(date +%s)
SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
echo total time for postprocessing: ${SEC_TOTAL} s

echo "post      ${YYYY_MM} FINISHED $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log

cd ${OUTDIR}

echo NEXT_DATE: ${NEXT_DATE}  / YDATE_STOP: ${YDATE_STOP}
### at the end of the model chain clear up the SCRATCH directories
if [[ ${NEXT_DATE} -eq ${YDATE_STOP} ]]
then
  echo ... checking if all post-processing jobs run successfully
#  if [[ $(ls -1 ${SCRATCHDIR}/${EXPID}/output/icon | wc -l) -gt 0 ]]
  set +e
  if [[ $(ls -1 ${SCRATCHDIR}/${EXPID}/output/icon/[12]???_?? | wc -l) -gt 0 ]]
  then
    if [[ -n "${NOTIFICATION_ADDRESS}" ]]
    then
      echo Not all post-processing jobs have run successfully > ${PFDIR}/${EXPID}/finish_message
      echo Please check the following dates and run the \"subchain post YYYYMMDDHH\" manually for these months again >> ${PFDIR}/${EXPID}/finish_message
      echo after successfully finish of all post jobs start the evaluation manually by \"subchain eva-suite\"  >> ${PFDIR}/${EXPID}/finish_message
      ls -1 ${SCRATCHDIR}/${EXPID}/output/icon  >> ${PFDIR}/${EXPID}/finish_message
      ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "ICON-CLM ${EXPID} job finished" ${PFDIR}/${EXPID}/finish_message
      DATE_END=$(date +%s)
      SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
      echo "post      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
      exit
    else
      echo Not all post-processing jobs have run successfully
      echo Please check the following dates and run the \"subchain post YYYYMMDDHH\" manually for these months again
      echo after successfully finish of all post jobs start the evaluation manually by \"subchain eva-suite\"
      ls -1 ${SCRATCHDIR}/${EXPID}/output/icon
      DATE_END=$(date +%s)
      SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
      echo "post      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
      exit
    fi
  else
    echo ... deleting the whole ${EXPID} directory on scratch
    rm -rf ${SCRATCHDIR}/${EXPID}
    if [ ${ITYPE_EVAL} -eq 1 ]
    then
      cd ${PFDIR}/${EXPID} ; ./subchain eva-suite ${NEXT_DATE}
    fi
    set -e
  fi

  #... calculate total time for the job
  FIRST_LINE=$(head -n 1 ${PFDIR}/${EXPID}/chain_status.log)
  START=${FIRST_LINE:27:30}
  TOTAL_TIME=$(($(date +%s) - $(date -d "${START}" +%s)))
  set +e
  #... find days
#  (( DD = ${TOTAL_TIME} / 86400  ))
  let "DD = TOTAL_TIME / 86400"
  #... find hours
#  (( HH = (${TOTAL_TIME} - ${DD} * 86400) / 3600 ))
  let "HH = (TOTAL_TIME - DD * 86400) / 3600"
  #... find minutes
#  (( MM = (${TOTAL_TIME} - (${DD} * 86400) - (${HH} * 3600)) / 60 ))
  let "MM = (TOTAL_TIME - (DD * 86400) - (HH * 3600)) / 60"
  #... find seconds
#  (( SS = ${TOTAL_TIME} - (${DD} * 86400) - (${HH} * 3600) -(${MM} * 60) ))
  let "SS = $TOTAL_TIME - ($DD * 86400) - ($HH * 3600) -($MM * 60)"
#  echo Total time: ${DD} days -- ${HH} hours -- ${MM} minutes -- ${SS} seconds
  echo "subchain          FINISHED $(date) --- ${DD}d ${HH}h ${MM}m ${SS}s" >> ${PFDIR}/${EXPID}/chain_status.log
  set -e

  ### send notification message that job has been finished
  if [[ -n "${NOTIFICATION_ADDRESS}" ]]
  then
    echo ICON-CLM job ${EXPID} finished `date` > ${PFDIR}/${EXPID}/finish_message
    echo afterburners may still not be finished, e.g. eva-suite or arch-slk > ${PFDIR}/${EXPID}/finish_message
    echo "Total time used for the experiment: ${DD}d ${HH}h ${MM}m ${SS}s" >> ${PFDIR}/${EXPID}/finish_message
    ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "ICON-CLM ${EXPID} job finished" ${PFDIR}/${EXPID}/finish_message
    rm ${PFDIR}/${EXPID}/finish_message
  fi
  echo ------------------------------------------
  echo  Job ${EXPID} finished
  echo ------------------------------------------

fi

echo "END  " ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/post/finish_joblist
