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

      JOBID=${SLURM_JOBID}

#################################################
#  Pre-Settings
#################################################
#... get the job_settings environment variables
source ${PFDIR}/${EXPID}/job_settings

#
#################################################
# batch settings for archiving run at CSCS-Alps
#################################################
module load cdo/${CDO_VERSION}
module load nco/${NCO_VERSION}
module load netcdf-c/4.9.2

#... load functions
source ${PFDIR}/${EXPID}/scripts/functions.inc

cd ${SCRATCHDIR}/${EXPID}/tmp

if [[ $# -eq 2 ]]
then
      CURRENT_DATE=${2:0:6}01${YDATE_START:8:6}  # just in case of an arch re-run for a specific month
fi
INPDIR=${SCRATCHDIR}/${EXPID}/input/arch
OUTDIR=${SCRATCHDIR}/${EXPID}/output/arch

NEXT_DATE=$(${CFU} get_next_dates ${CURRENT_DATE} 01:00:00 ${ITYPE_CALENDAR} | cut -c1-10)

YYYY=${CURRENT_DATE:0:4}
MM=${CURRENT_DATE:4:2}
YYYY_MM=${YYYY}_${MM}
HSTART=$(${CFU} get_hours ${YDATE_START} ${CURRENT_DATE} ${ITYPE_CALENDAR})
HNEXT=$(${CFU} get_hours ${YDATE_START} ${NEXT_DATE} ${ITYPE_CALENDAR})
HSTOP=$(${CFU} get_hours ${YDATE_START} ${YDATE_STOP} ${ITYPE_CALENDAR})
JOBLOGFILE=${WORKDIR}/${EXPID}/joblogs/arch/arch_${EXPID}_${YYYY_MM}.o
YDATE_NEXT=${NEXT_DATE}
YYYY_NEXT=${NEXT_DATE:0:4}
MM_NEXT=${NEXT_DATE:4:2}

# create output directory
if [ ! -d ${OUTDIR}/${YYYY_MM} ] 
then
  mkdir -p ${OUTDIR}/${YYYY_MM}
  NOUTDIR=1
  while [ ${NOUTDIR} -le ${#HOUT_INC[@]} ]
  do
    if [ ${NOUTDIR} -ne ${NESTING_STREAM} ]
    then
      mkdir -p ${OUTDIR}/${YYYY_MM}/out$(printf %02d ${NOUTDIR})
    fi
    ((NOUTDIR++))
  done
fi

# ZERO2ZERO is set to true for check_files, in case a month starts and ends with 00UTC
#           for ICON this is the case for the first month
ZERO2ZERO=F
if [[ ${CURRENT_DATE} -eq ${YDATE_START} ]]
then
   ZERO2ZERO=T
fi

#... set maximum number of parallel processes
(( MAXPP=TASKS_ARCH ))

#################################################
#  Main Part
#################################################

echo START ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/arch/finish_joblist
echo "arch      ${YYYY_MM} START    $(date)" >> ${PFDIR}/${EXPID}/chain_status.log

DATE_START=$(date +%s)
DATE1=${DATE_START}
#################################################
echo "start: check if all output files are available"
#################################################

NOUTDIR=1
while [[ ${NOUTDIR} -le ${#HOUT_INC[@]} ]]
do
  NOUTDIR2=$(printf %02d ${NOUTDIR})

# get the string before the dot of the first file in the input directory
# this works only if the file names are of the same kind!
  SUFFIX=$(ls -1 ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} | head -n 1 |  cut -d. -f1)

  if [ -z "$SUFFIX" ]  # $SUFFIX is empty, i.e. directory is empty
  then

    echo Error in arch  > ${PFDIR}/${EXPID}/error_message
    echo Date ${YYYY} / ${MM} out${NOUTDIR2} >> ${PFDIR}/${EXPID}/error_message
    echo Error during archiving >> ${PFDIR}/${EXPID}/error_message
    echo Not all ICON-CLM output files found >> ${PFDIR}/${EXPID}/error_message
    echo ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} is empty >> ${PFDIR}/${EXPID}/error_message
    if [ -n "${NOTIFICATION_ADDRESS}" ]
    then
      ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
    fi
    DATE2=$(date +%s)
    SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")
    echo "arch      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
    exit 1

  else  # directory is not empty

    case ${SUFFIX: -1} in
      p)
        SUFFIX=p.nc
        ;;
      z)
        SUFFIX=z.nc
        ;;
      *)
        SUFFIX=.nc
        ;;
    esac

    START_CHECK=${CURRENT_DATE}
    if [ ${ZERO2ZERO} == "F" ]
    then
      START_CHECK=$(${CFU} add_hours ${CURRENT_DATE} ${HOUT_INC[$((${NOUTDIR}-1))]:0:2} ${ITYPE_CALENDAR})
    fi

    if [[ ${NOUTDIR} -ne 5 ]] && [[ $(${CFU} check_files_iso ${START_CHECK}0000 ${NEXT_DATE}0000  ${HOUT_INC[$((${NOUTDIR}-1))]} icon_ icon_ ${SUFFIX} ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} ${ZERO2ZERO} ${ITYPE_CALENDAR}) -eq 1 ]]
#    if [[ $(${CFU} check_files_iso ${START_CHECK}0000 ${NEXT_DATE}0000  ${HOUT_INC[$((${NOUTDIR}-1))]} icon_ icon_ ${SUFFIX} ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} ${ZERO2ZERO} ${ITYPE_CALENDAR}) -eq 1 ]]
      then
        mv check_files.log ${WORKDIR}/${EXPID}/joblogs/arch/arch_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log
        echo Error in arch  > ${PFDIR}/${EXPID}/error_message
        echo Date ${YYYY} / ${MM} out${NOUTDIR2} >> ${PFDIR}/${EXPID}/error_message
        echo Error during archiving >> ${PFDIR}/${EXPID}/error_message
        echo Not all ICON-CLM output files found >> ${PFDIR}/${EXPID}/error_message
        echo check ${WORKDIR}/${EXPID}/joblogs/arch/arch_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log >> ${PFDIR}/${EXPID}/error_message
        if [ -n "${NOTIFICATION_ADDRESS}" ]
        then
          ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
        fi
        DATE2=$(date +%s)
        SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")
	
	echo ${CURRENT_DATE:6:2}
        if [ ${CURRENT_DATE:6:2} == "01" ];
         then
          echo "Warning: No data on first timestamp in " ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} >> ${PFDIR}/${EXPID}/error_message
        else
	   echo "exit now"
           echo "arch      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
           exit 1
        fi
      fi

  fi
  ((NOUTDIR++))
done

DATE2=$(date +%s)
SEC_CHECK=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}

#################################################
echo "end:   check if all output files are available"
#################################################

if [ ${ITYPE_SAMOVAR} -ne 0 ]
then
  ##########################################################################
  echo "start: check if data contains reasonable values by applying SAMOVAR"
  ##########################################################################

  echo ---- SAMOVAR output for ${EXPID} ${YYYY_MM} > ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log
  SAMOVAR_ERROR=0
  NOUTDIR=1
  while [[ ${NOUTDIR} -le ${#HOUT_INC[@]} ]]
  do
    NOUTDIR2=$(printf %02d ${NOUTDIR})
    echo ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} >> ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log
    echo --------------------------------------------- >> ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log
    set +e
    if [[ ${ITYPE_SAMOVAR} -eq 1 ]]
    then
      NOD=$(cal ${MM} ${YYYY} | grep -v '[A-Za-z]' | wc -w)
      ${SAMOVAR_SH} T ${SAMOVAR_LIST} ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log "${INPDIR}/${YYYY_MM}/out${NOUTDIR2}/icon_*${NOD}T*.nc"
    else
      FILELIST=$(ls -1 ${INPDIR}/${YYYY_MM}/out${NOUTDIR2}/*)
      ${SAMOVAR_SH} T ${SAMOVAR_LIST} ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log "${FILELIST}"
    fi
    ERROR_STATUS=$?
    if [[ $ERROR_STATUS -eq 0 ]]
    then
      echo SAMOVAR check for out${NOUTDIR2} -- OK
    else
      SAMOVAR_ERROR=1
      echo SAMOVAR check for out${NOUTDIR2} -- FAILED
    fi
    set -e
    echo --------------------------------------------- >> ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log

    ((NOUTDIR++))
  done

  if [ ${SAMOVAR_ERROR} -ne 0 ]
  then
    echo Error in arch  > ${PFDIR}/${EXPID}/error_message
    echo Date ${YYYY} / ${MM} >> ${PFDIR}/${EXPID}/error_message
    echo Error in checking by SAMOVAR >> ${PFDIR}/${EXPID}/error_message
    echo check ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log >> ${PFDIR}/${EXPID}/error_message
    if [ -n "${NOTIFICATION_ADDRESS}" ]
    then
      ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
    fi
    DATE2=$(date +%s)
    SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")
    echo "arch      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
    exit 2
  else
    rm ${WORKDIR}/${EXPID}/joblogs/arch/samovar_${YYYY_MM}.log  # uncomment this line and the else, if you do not want to keep the logs
  fi

  ##########################################################################
  echo "end:   check if data contains reasonable values by applying SAMOVAR"
  ##########################################################################
fi

DATE2=$(date +%s)
SEC_SAMOVAR=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}

######################################################################
if  [ ${HLEV_STREAM} -eq 0 ]
then
  echo "start: correct data files"
else
  echo "start: correct data files to fulfill CF-conventions and perform height interpolation over terrain for output stream ${HLEV_STREAM}"
fi
### This is a temporal fix and should be corrected in the ICON source code in future
######################################################################

if [ ${CURRENT_DATE} -eq ${YDATE_START} ] && [ ${HLEV_STREAM} -ne 0 ]
then
  #... in case of height interpolation over terrain build a new z_mc which is defined as z_mc-topography_c
  ${CDO} -s sellevidx,${UL}/${LL} -sub -selvar,z_mc ${SCRATCHDIR}/${EXPID}/output/icon/icon_c.nc -selvar,topography_c  ${SCRATCHDIR}/${EXPID}/output/icon/icon_c.nc ${WORKDIR}/${EXPID}/post/z_mc-topography_c.nc
  #... copy the c file to the arch output directory
  cp ${SCRATCHDIR}/${EXPID}/output/icon/icon_c.nc ${OUTDIR}/.
fi

#... looping over all output streams and files
NOUTDIR=1
while [[ ${NOUTDIR} -le ${#HOUT_INC[@]} ]]
do
  NOUTDIR2=$(printf %02d ${NOUTDIR})

  #... in case of height interpolation over terrain
  if [ ${NOUTDIR} -eq ${HLEV_STREAM} ]
  then
    COUNTPP=0
    for FILE in $(ls -1 ${INPDIR}/${YYYY_MM}/out${NOUTDIR2}/*)
    do
      if [ ! -d ${OUTDIR}/${YYYY_MM}/out${NOUTDIR2} ] ; then mkdir ${OUTDIR}/${YYYY_MM}/out${NOUTDIR2} ;fi
      #echo height_interpolation ${COUNTPP} HLEVS[@] ${OUTDIR}/${YYYY_MM}/out${NOUTDIR2} ${FILE}
      height_interpolation ${COUNTPP} HLEVS[@] ${OUTDIR}/${YYYY_MM}/out${NOUTDIR2} ${FILE} &
#     ( height_interpolation ${COUNTPP} HLEVS[@] ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} ${FILE} ; echo 'hallo' ${COUNTPP}  > ${SCRATCHDIR}/${EXPID}/height_inter.${COUNTPP}.es )&

      (( COUNTPP=COUNTPP+1 ))
      if [ ${COUNTPP} -ge ${MAXPP} ]
      then
        COUNTPP=0
        wait
      fi

    done
  wait
  fi
  #... end of height interpolation

  if [ ${NOUTDIR} -ne ${NESTING_STREAM} ]
  then
    if [ ${NOUTDIR} -ne ${HLEV_STREAM} ]
    then
	#echo cp -r ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} ${OUTDIR}/${YYYY_MM}/.
	cp -r ${INPDIR}/${YYYY_MM}/out${NOUTDIR2} ${OUTDIR}/${YYYY_MM}/.&
    fi
    wait	
    COUNTPP=0
    #echo ${OUTDIR}/${YYYY_MM}/out${NOUTDIR2}
    for FILE in $(ls -1 ${OUTDIR}/${YYYY_MM}/out${NOUTDIR2}/*)
    do
    
      iconcor ${COUNTPP} ${HOUT_INC[$((${NOUTDIR}-1))]} ${FILE} ${OPERATION[$((${NOUTDIR}-1))]}  &
    
      (( COUNTPP=COUNTPP+1 ))
      if [ ${COUNTPP} -ge ${MAXPP} ]
      then
        COUNTPP=0
        wait
      fi
    
    done
    wait

  fi

  ((NOUTDIR++))
done

DATE2=$(date +%s)
SEC_COR=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}

######################################################################
echo "end:   correct data files"
######################################################################

DATE_LOG_DATE=$(cat ${PFDIR}/${EXPID}/date.log | cut -c1-14)
if [[ ${ITYPE_ICON_ARCH_PAR} -eq 1 ]] && [[ ${CURRENT_DATE} -eq ${DATE_LOG_DATE} ]]
then

  ###############################################
  # all data from ICON-CLM are checked, ICON-CLM can run the next month in parallel to arch and post
  # update the date in date.log
  ###############################################
#  cat ${PFDIR}/${EXPID}/date.log
  echo ${YDATE_NEXT} > ${PFDIR}/${EXPID}/date.log
#  cat ${PFDIR}/${EXPID}/date.log

  #################################################
  # submit the next ICON-CLM job
  #   in case the conv2icon job for the next month has
  #   not finished yet, do not submit the icon-clm job.
  #   The icon-clm job will be submitted by conv2icon in
  #   this case
  #################################################
  if [ ${YDATE_NEXT} != ${YDATE_STOP} ]
  then
    if [[ ${ITYPE_CONV2ICON} -eq 1 ]]
    then
      YDATE_NEXT=${YDATE_NEXT}
      if grep  "END ${YDATE_NEXT:0:4} ${YDATE_NEXT:4:2}"  ${WORKDIR}/${EXPID}/joblogs/conv2icon/finish_joblist > /dev/null
      then
        cd ${PFDIR}/${EXPID} ; ./subchain icon
      else
        echo prep/conv2icon jobs are not yet finished for ${YDATE_NEXT:0:4}_${YDATE_NEXT:4:2}
        echo the icon job will be started at the end of the conv2icon job \(if the conv2icon job does not crash\)
      fi
    else
      cd ${PFDIR}/${EXPID} ; ./subchain icon
    fi
  fi

fi

DATE1=$(date +%s)

#################################################
# compress data
  echo "start: compress data files"
#################################################

#... in case of compression the nesting data can only be internally compressed
#... this is because of the special use in the prep.job.sh in the fine nesting
if [[ ${NESTING_STREAM} -gt 0 ]] ; then
  cp -r ${INPDIR}/${YYYY_MM}/out$(printf %02d ${NESTING_STREAM}) ${OUTDIR}/${YYYY_MM}/nesting
if [[ ${ITYPE_COMPRESS_ARCH} -ne 0 ]]
then

  echo "**** internal netCDF compression of the nesting output stream"
  FORMAT_SUFFIX=ncz
  cd ${OUTDIR}/${YYYY_MM}
#... parallel execution of nccopy call

  cd nesting
  echo 'working in directory' $(pwd)
  FILELIST=$(ls -1 icon_*.nc)
  COUNTPP=0
  for FILE in ${FILELIST}
  do
   ${NC_BINDIR}/nccopy -d 1 -s ${FILE} $(basename ${FILE} .nc).${FORMAT_SUFFIX} &
   (( COUNTPP=COUNTPP+1 ))
   if [ ${COUNTPP} -ge ${MAXPP} ]
   then
     COUNTPP=0
     wait
   fi
  done
  cd ..

fi
fi

FORMAT_SUFFIX=nc
case ${ITYPE_COMPRESS_ARCH} in

0)        #... no compression

  echo "**** no compression ****"
  ;;

1)        #... internal netCDF compression

  echo "**** internal netCDF compression"
  FORMAT_SUFFIX=ncz
  cd ${OUTDIR}/${YYYY_MM}
#... parallel execution of nccopy call

  DIRLIST=$(ls -1d out*)
  for DIRECTORY in ${DIRLIST}
  do
    cd ${DIRECTORY}
    echo 'working in directory' $(pwd)
    FILELIST=$(ls -1 icon_*.nc)
    COUNTPP=0
    for FILE in ${FILELIST}
    do
     #echo ${NC_BINDIR2}/nccopy -d 1 -s ${FILE} $(basename ${FILE} .nc).${FORMAT_SUFFIX}
	${NC_BINDIR}/nccopy -d 1 -s ${FILE} $(basename ${FILE} .nc).${FORMAT_SUFFIX} &
     (( COUNTPP=COUNTPP+1 ))
     if [ ${COUNTPP} -ge ${MAXPP} ]
     then
       COUNTPP=0
       wait
     fi
    done
    wait
    cd ..
  done
  ;;

2)       #... gzip compression (-k option works only for gzip version from 1.6 onwards)
         #...      maybe written more elegant with -r option, but might be not robust

  echo "**** gzip compression"
  FORMAT_SUFFIX=gz
  cd ${OUTDIR}/${YYYY_MM}
#... parallel execution of gzip call

  DIRLIST=$(ls -1d out*)
  for DIRECTORY in ${DIRLIST}
  do
    cd ${DIRECTORY}
    FILELIST=$(ls -1 icon_*.nc)
    COUNTPP=0
    for FILE in ${FILELIST}
    do
     gzip -k ${FILE} &
     (( COUNTPP=COUNTPP+1 ))
     if [ ${COUNTPP} -ge ${MAXPP} ]
     then
       COUNTPP=0
       wait
     fi
    done
    wait
    cd ..
  done
  ;;

3)       #... pigz compression
         #...      maybe written more elegant with -r option, but might be not robust

  echo "**** pigz compression"
  FORMAT_SUFFIX=gz
  cd ${OUTDIR}/${YYYY_MM}

  DIRLIST=$(ls -1d out*)
  for DIRECTORY in ${DIRLIST}
  do
    cd ${DIRECTORY}
    FILELIST=$(ls -1)
    for FILE in ${FILELIST}
    do
     ${PIGZ} -k --fast -p ${MAXPP} ${FILE}
    done
    cd ..
  done
  ;;

*)

  echo **** invalid value for  ITYPE_COMPRESS_ARCH: ${ITYPE_COMPRESS_ARCH}
  echo **** no compression applied
  ;;

esac

#################################################
# end compress data
  echo "end:   compress data files"
#################################################

DATE2=$(date +%s)
SEC_ZIP=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}
#################################################
# tar and archive data
  echo "start: tar data files"
#################################################

cd ${OUTDIR}/${YYYY_MM}

mkdir -p ${ARCHIVE_OUTDIR}/${EXPID}/${YYYY_MM}
NOUTDIR=1
COUNTPP=0
while [[ ${NOUTDIR} -le ${#HOUT_INC[@]} ]]
do
  NOUTDIR2=$(printf %02d ${NOUTDIR})
(
  if [[ ${NESTING_STREAM} -eq ${NOUTDIR} ]]
  then
    mkdir out${NOUTDIR2} # necessary in case of a re-run of icon for the same date
    if [[ ${ITYPE_COMPRESS_ARCH} -gt 0  ]]
    then
      tar -chf ${ARCHIVE_OUTDIR}/${EXPID}/${YYYY_MM}/${EXPID}_${YYYY_MM}_nesting.tar nesting/*.ncz 2> /dev/null
      ERROR=$?
      #rm nesting/*.ncz
    else
      tar -chf ${ARCHIVE_OUTDIR}/${EXPID}/${YYYY_MM}/${EXPID}_${YYYY_MM}_nesting.tar nesting/*.nc 2> /dev/null
      ERROR=$?
    fi
    if [[ ${ERROR} -eq 1 ]]
    then
      echo ERROR: tar of nesting stream failed.
      DATE_END=$(date +%s)
      SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
      echo "arch      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
      exit
    fi
  else
    cd ${OUTDIR}/${YYYY_MM}
#KK    tar -uhf ${ARCHIVE_OUTDIR}/${EXPID}/${YYYY_MM}/${EXPID}_${YYYY_MM}_out.tar out${NOUTDIR2}/*.${FORMAT_SUFFIX}
    tar -chf ${ARCHIVE_OUTDIR}/${EXPID}/${YYYY_MM}/${EXPID}_${YYYY_MM}_out${NOUTDIR2}.tar out${NOUTDIR2}/*.${FORMAT_SUFFIX} 2> /dev/null
    ERROR=$?
    if [[ ${ERROR} -eq 1 ]]
    then
      echo ERROR, tar of out${NOUTDIR2} failed.
      DATE_END=$(date +%s)
      SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
      echo "arch      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
      exit
    fi    
    if [ ${FORMAT_SUFFIX} != "nc" ]
    then
      echo "remove line reached: rm ${OUTDIR}/${YYYY_MM}/out${NOUTDIR2}/*.${FORMAT_SUFFIX}"
      rm out${NOUTDIR2}/*.${FORMAT_SUFFIX}
    fi
  fi
)&

  ((NOUTDIR++))

  (( COUNTPP=COUNTPP+1 ))
  if [ ${COUNTPP} -ge ${MAXPP} ]
  then
    COUNTPP=0
    wait
  fi
done
wait

#KK The following lines are only required, if forcing files should be archived
#KK to drive further simulations with existing forcing-files using ITYPE_CONV2ICON=0
#  echo "start: tar forcing files"
  #################################################
#if [ ${CURRENT_DATE} -eq ${YDATE_START} ];then
#  cd ${INIDIR}
#  tar -cf ${ARCHIVE_INPDIR}/${GCM_PREFIX}${YYYY}${MM}_ERA5_europe011_v1_inidata.tar *.nc
#fi
#mkdir -p ${ARCHIVE_INPDIR}/year${YYYY}
#cd ${SCRATCHDIR}/${EXPID}/output/conv2icon/${YYYY_MM}
#tar cf ${ARCHIVE_INPDIR}/year${YYYY}/${GCM_PREFIX}${YYYY}${MM}_ERA5_europe011_v1_lbc.tar *.nc
#KK end of add-on
  
#################################################
  echo "end:   tar data files"
# END tar and archive data
#################################################

# transfer output tar files to DKRZ tape archive
if [ "${ITYPE_ARCH_SLK:-0}" -eq 1 ]
then
  cd ${PFDIR}/${EXPID} ; ./subchain arch-slk ${CURRENT_DATE}
fi

DATE2=$(date +%s)
SEC_TAR=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")

printf '%-30s %8s s\n'  'time used for checking data:'  ${SEC_CHECK}
printf '%-30s %8s s\n' 'time used for samovar check:' ${SEC_SAMOVAR}
printf '%-30s %8s s\n'  'time used for correcting data:'  ${SEC_COR}
printf '%-30s %8s s\n'  'time used for zip data:'  ${SEC_ZIP}
printf '%-30s %8s s\n' 'time used for tar data:' ${SEC_TAR}
printf '%-30s %8s s\n' 'total time for archiving:' ${SEC_TOTAL}

###############################################
# remove the preprocessing and conv2icon
#   output for YYYY_MM from the SCRATCH directory
###############################################
rm -rf ${SCRATCHDIR}/${EXPID}/output/prep/${YYYY_MM}
rm -rf ${SCRATCHDIR}/${EXPID}/output/conv2icon/${YYYY_MM}

echo ${YYYY} ${MM} arch job finished >> ${WORKDIR}/${EXPID}/joblogs/finish_joblist

#################################################
# submit post-processing job
#################################################
cd ${PFDIR}/${EXPID} ; ./subchain post ${CURRENT_DATE}

if [[ ${ITYPE_ICON_ARCH_PAR} -eq 0 ]] && [[ ${CURRENT_DATE} -eq ${DATE_LOG_DATE} ]]
then

  ###############################################
  # update the date in date.log
  ###############################################
  cat ${PFDIR}/${EXPID}/date.log
  echo ${YDATE_NEXT} > ${PFDIR}/${EXPID}/date.log
  cat ${PFDIR}/${EXPID}/date.log

  if [ ${YDATE_NEXT} != ${YDATE_STOP} ]
  then

  ###################################################
  # submit the next ICON job
  #   in case the conv2icon job for the next month has
  #   not finished yet, do not submit the icon job.
  #   The icon job will be submitted by conv2icon in
  #   this case
  ###################################################
    if [[ ${ITYPE_CONV2ICON} -eq 1 ]]
    then
      YDATE_NEXT=${YDATE_NEXT}
      if grep  "END ${YDATE_NEXT:0:4} ${YDATE_NEXT:4:2}"  ${WORKDIR}/${EXPID}/joblogs/conv2icon/finish_joblist
      then
        cd ${PFDIR}/${EXPID} ; ./subchain icon
      else
        echo prep/conv2icon jobs are not yet finished for ${YDATE_NEXT:0:4}_${YDATE_NEXT:4:2}
        echo the icon job will be started at the end of the conv2icon job \(if the conv2icon job does not crash\)
      fi
    else #ITYPE_CONV2ICON=0
      cd ${PFDIR}/${EXPID} ; ./subchain icon noprep
    fi
  fi
fi

#-----------------------------------------------------------------------------
echo ----- arch finished
echo "END  " ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/arch/finish_joblist
echo "arch      ${YYYY_MM} FINISHED $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log

exit
#-----------------------------------------------------------------------------

