#!/bin/bash
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

#################################################
#  Pre-Settings
#################################################

#... get the job_settings environment variables
source ${PFDIR}/${EXPID}/job_settings

#
# load the necessary modules
module load cdo/${CDO_VERSION}
module load nco/${NCO_VERSION}

#... set maximum number of parallel processes
  (( MAXPP=TASKS_PREP ))

      JOBID=${SLURM_JOBID}.log

#... setting addditional environment variables for the prep job

  #... check whether or not conv2icon needs to be run
  if [ ${ITYPE_CONV2ICON} -eq 1 ]
  then
    OUTDIR=${SCRATCHDIR}/${EXPID}/output/prep
    INPDIR=${SCRATCHDIR}/${EXPID}/input/prep
  else
    OUTDIR=${SCRATCHDIR}/${EXPID}/output/conv2icon
  fi
  YYYY=${CURRENT_DATE:0:4}
  MM=${CURRENT_DATE:4:2}
  YYYY_MM=${YYYY}_${MM}
  NEXT_DATE=$(${CFU} get_next_dates ${CURRENT_DATE} 01:00:00 ${ITYPE_CALENDAR} | cut -c1-10)
  YYYY_NEXT=${NEXT_DATE:0:4}
  MM_NEXT=${NEXT_DATE:4:2}

  # create the input and output directory
mkdir -p ${OUTDIR}/${YYYY_MM}

#################################################
#  Main part
#################################################

echo START ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/prep/finish_joblist
echo "prep      ${YYYY_MM} START    $(date)" >> ${PFDIR}/${EXPID}/chain_status.log

#################################################
# copy the restart file from
# /pool/data/CLMcom/ICON-CLM/data/rcm_new/europe011/.
# to ${WORKDIR}/${EXPID}/restarts/.
#################################################
cp -r ${DATADIR}/rcm_new/europe011/multifile_restart_ATMO_19500101T000000Z.mfr ${WORKDIR}/${EXPID}/restarts/.

#################################################
# transfer input from the archive
# and preprocess data if necessary
#################################################

#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
#  start ITYPE_CONV2ICON if clause
#
# if conv2icon needs to be run
if [ ${ITYPE_CONV2ICON} -eq 1 ]
then

mkdir -p ${INPDIR}/${YYYY}_${MM}

DATE_START=$(date +%s)
DATE1=$(date +%s)

echo ----------------------
echo ... untar
echo ----------------------

# extract data from tar files
case "$(printf %02d ${HINCBOUND})" in
    01) echo untar every hour
        tar -C ${INPDIR}/${YYYY}_${MM} -xvf ${GCM_DATADIR}/year${YYYY}/${GCM_NAME}_${GCM_SCENARIO}_${YYYY}_${MM}.tar
        ;;
    02|03|04|06) echo untar every ${HINCBOUND} hour
        COUNTPP=0
        for (( HOUR=0; HOUR<=23; HOUR=$((HOUR+HINCBOUND)) ))
        do
           tar --wildcards -C ${INPDIR}/${YYYY}_${MM} -xvf ${GCM_DATADIR}/year${YYYY}/${GCM_NAME}_${GCM_SCENARIO}_${YYYY}_${MM}.tar ${GCM_PREFIX}*$(printf %02d ${HOUR}).ncz &
           (( COUNTPP=COUNTPP+1 ))
           if [ ${COUNTPP} -ge ${MAXPP} ]
           then
             COUNTPP=0
             wait
           fi
        done
        wait
        ;;
    *) echo ERROR: Invalid HINCBOUND = $(printf %02d ${HINCBOUND})  must be 01, 02, 03, 04 or 06

       exit
        ;;
esac

DATE2=$(date +%s)
SEC_UNTAR=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}

#... perform a decompression of internal zipped netCDF4 files
echo ----------------------
echo ... unzip
echo ----------------------

   #... unzipping will be done in parallel chunks
   COUNTPP=0
   FILELIST=$(ls -1 ${INPDIR}/${YYYY_MM}/*)
   for FILE in ${FILELIST}
   do
    FILEBASE=$(basename ${FILE} .ncz)
    ${NC_BINDIR}/nccopy -k 2 ${INPDIR}/${YYYY_MM}/${FILEBASE}.ncz ${OUTDIR}/${YYYY_MM}/${FILEBASE}.nc &
    (( COUNTPP=COUNTPP+1 ))
    if [[ ${COUNTPP} -ge ${MAXPP} ]]
    then
      COUNTPP=0
      wait
    fi
   done
   wait

 rm -rf ${INPDIR}/${YYYY_MM}

DATE2=$(date +%s)
SEC_UNZIP=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}

#... convert CCLM caf/cas to ICON caf/cas (just a workaround, should be included in the ICON program)
echo ----------------------
echo ... ccaf2icaf
echo ----------------------

    #... converting willl be done in parallel chunks
    cd ${OUTDIR}/${YYYY_MM}
    (( MAXPP=TASKS_PREP+TASKS_PREP ))
    COUNTPP=0
    FILELIST=$(ls -1)
    for FILE in ${FILELIST}
    do
(
       ${UTILS_BINDIR}/ccaf2icaf ${FILE} 2 ${GCM_SOILTYPE}
       ${NCO_BINDIR}/ncks -h -O -x -v W_SO_REL,T_SO,soil1,soil1_bnds ${FILE} ${FILE}
)&
    (( COUNTPP=COUNTPP+1 ))
    if [ ${COUNTPP} -ge ${MAXPP} ]
    then
      COUNTPP=0
      wait
    fi
    done
    wait

    cd ${PFDIR}/${EXPID}
#... end of conversion

DATE2=$(date +%s)
SEC_CCAF2ICAF=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}

echo ----------------------
echo ... check files
echo ----------------------
  #... check if all necessary input files exist
    CHECK_FILES=$(${CFU} check_files ${CURRENT_DATE} ${NEXT_DATE} \
  $(printf %02d ${HINCBOUND}):00:00 ${GCM_PREFIX} ${GCM_PREFIX} .nc \
  ${OUTDIR}/${YYYY_MM} T ${ITYPE_CALENDAR})

  if [ ${CHECK_FILES} -eq 1 ]
    then
    cat <<EOF_MESS > ${PFDIR}/${EXPID}/error_message
Error in prep
Date ${YYYY} / ${MM}
Error during preprocessing
Not all input files found
EOF_MESS
    # --- Leap year fix for missing 29 Feb files ---
    if [ -f check_files.log ]; then
      while IFS= read -r line; do
        # Only process lines with missing files
        if [[ "$line" == *"-- does not exist" ]]; then
          missing_file=$(echo "$line" | awk '{print $1}')
          # Check if file is for Feb 29
          if [[ "$missing_file" =~ ([0-9]{4})_02/caf([0-9]{4})0229([0-9]{2}).nc ]]; then
            year=${BASH_REMATCH[1]}
            date=${BASH_REMATCH[2]}0229${BASH_REMATCH[3]}
            hour=${BASH_REMATCH[3]}
            # Build source file for Feb 28
            src_file="${OUTDIR}/${YYYY_MM}/caf${year}0228${hour}.nc"
            if [ -f "$src_file" ]; then
              cp "$src_file" "$missing_file"
              # Update time variable in NetCDF file
              # Use nco to set time to 29 Feb
              # Example: ncap2 -O -s 'time=time+86400' infile.nc outfile.nc
              ${NCO_BINDIR}/ncatted -O -a calendar,time,o,c,"proleptic_gregorian" "$missing_file"
              ${NCO_BINDIR}/ncap2 -O -s 'time=time+86400' "$missing_file" "$missing_file"
              echo "Leap year fix: copied $src_file to $missing_file and updated time variable." >> ${WORKDIR}/${EXPID}/joblogs/prep/prep_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log
            else
              echo "Leap year fix: source file $src_file not found for $missing_file" >> ${WORKDIR}/${EXPID}/joblogs/prep/prep_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log
              cp check_files.log ${WORKDIR}/${EXPID}/joblogs/prep/prep_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log
              echo check ${WORKDIR}/${EXPID}/joblogs/prep/prep_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log >> ${PFDIR}/${EXPID}/error_message
              if [ -n "${NOTIFICATION_ADDRESS}" ]
              then
                ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
              fi
              DATE2=$(date +%s)
              SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")
              echo "prep      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s"  >>${PFDIR}/${EXPID}/chain_status.log
              exit 1
            fi
          fi
        fi
      done < check_files.log
    fi # --- End leap year fix ---
  fi # ${CHECK_FILES} -eq 1
  rm -f check_files.log

DATE2=$(date +%s)
SEC_CHECK=$(${PYTHON} -c "print(${DATE2}-${DATE1})")
DATE1=${DATE2}

SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")

printf '%-32s %8s s\n'  'time used for untaring data:'  ${SEC_UNTAR}
printf '%-32s %8s s\n'  'time used for unzipping data:'  ${SEC_UNZIP}
printf '%-32s %8s s\n' 'time used for ccaf2icaf:' ${SEC_CCAF2ICAF}
printf '%-32s %8s s\n'  'time used for checking data:'  ${SEC_CHECK}
printf '%-32s %8s s\n' 'total time for pre-processing:' ${SEC_TOTAL}

echo "prep      ${YYYY_MM} FINISHED $(date) --- ${SEC_TOTAL}s"  >>${PFDIR}/${EXPID}/chain_status.log

#... submit CONV2ICON job
  cd ${PFDIR}/${EXPID} ; ./subchain conv2icon ${CURRENT_DATE}

#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
# if icon data are already available: ITYPE_CONV2ICON=0
else

#... the following line is just an example. Adjust this line for copying your icon input data.
  tar --wildcards -C ${OUTDIR}/${YYYY_MM} -xf ${ARCHIVE_INPDIR}/year${YYYY}/${GCM_PREFIX}${YYYY}${MM}*.tar
  if [ ${CURRENT_DATE} -eq ${YDATE_START} ]; then
    tar --wildcards -C ${INIDIR} -xf ${ARCHIVE_INPDIR}/${GCM_PREFIX}${YYYY}${MM}*_inidata.tar
  fi
#... check if all necessary input files exist
    CHECK_FILES=$(${CFU} check_files ${CURRENT_DATE} ${NEXT_DATE} \
  $(printf %02d ${HINCBOUND}):00:00  ${GCM_PREFIX} ${GCM_PREFIX} _lbc.nc \
  ${OUTDIR}/${YYYY_MM} T ${ITYPE_CALENDAR})

    if [ ${CHECK-FILES} -eq 1 ] || [ ! -f ${OUTDIR}/${YYYY_MM}/LOWBC_${YYYY}_${MM}.nc ]
    then
  cat <<EOF_MESS > ${PFDIR}/${EXPID}/error_message
Error in prep
Date ${YYYY} / ${MM}
Error during preprocessing
Not all input files found
EOF_MESS
    if [ ${CHECK-FILES} -eq 1 ]
    then
      mv check_files.log ${WORKDIR}/${EXPID}/joblogs/prep/prep_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log
      echo check ${WORKDIR}/${EXPID}/joblogs/prep/prep_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log >> ${PFDIR}/${EXPID}/error_message
    fi
  if [ ! -f ${OUTDIR}/${YYYY_MM}/LOWBC_${YYYY}_${MM}.nc ]
  then
      echo "missing ${OUTDIR}/${YYYY_MM}/LOWBC_${YYYY}_${MM}.nc" | tee -a ${WORKDIR}/${EXPID}/joblogs/prep/prep_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log
    fi
    if [ -n "${NOTIFICATION_ADDRESS}" ]
      then
        ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
    fi
      DATE2=$(date +%s)
      SEC_TOTAL=$(${PYTHON} -c "print(${DATE2}-${DATE_START})")
      echo "prep      ${YYYY_MM} FAILED   $(date) --- ${SEC_TOTAL}s"  >>${PFDIR}/${EXPID}/chain_status.log
  exit 1
  fi

  ### submit an ICON job if
  ### it is the first PREP job in the chain OR
  ### the in parallel running ICON job was faster than the PREP job
  DATELOG=$(cat ${PFDIR}/${EXPID}/date.log | cut -c1-10)
  if [ ${CURRENT_DATE} -eq ${YDATE_START} ] || [ ${CURRENT_DATE} -eq ${DATELOG} ]
  then
    #################################################
    # submit ICON job
    #################################################
    cd ${PFDIR}/${EXPID} ; ./subchain icon noprep
  fi

  echo "prep      ${YYYY_MM} FINISHED $(date) --- 0s"  >> ${PFDIR}/${EXPID}/chain_status.log

#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
# closing if clause for ITYPE_CONV2ICON
fi
#------------

echo "END  " ${YYYY} ${MM} >> ${WORKDIR}/${EXPID}/joblogs/prep/finish_joblist
