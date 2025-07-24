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

###
###... building yearly time series from monthly ones
###... format is such that it can be used in the CCLM2CMOR tool
###

cd ${OUTDIR}/${YYYY_MM}
FILELIST=$(ls -1)

YYYY_START=${YDATE_START:0:4}
let "YYYY_PREV = YYYY-1"
let "YYYY_PREV_PREV = YYYY-2"

if [ ${YYYY_PREV} -lt ${YDATE_START:0:4} ]
##this should prevent from the case that only one year was simulated
##  and then the yearly time series is only computed for this year
then
  echo reset YYYY_PREV to ${YYYY_PREV} because of only 1-year integration
  YYYY_PREV=${YDATE_START:0:4}
fi
YEAR_FINISHED=0
if [ ${MM} -eq 1 ] && [ ${CURRENT_DATE} -ne ${YDATE_START} ]
then

  echo ... combining monthly data into yearly for ${YYYY_PREV}

  FIRST_MONTH=1
  LAST_MONTH=12
  if [ ${YYYY_PREV} -eq ${YDATE_START:0:4} ]
  then
    FIRST_MONTH=${YDATE_START:4:2}
  fi

  #... check if all month of the year contain the same number of files
  NFILES=$(ls -1 ${OUTDIR}/${YYYY_PREV}_$(printf %02d ${FIRST_MONTH}) | wc -l)
  for (( MONTH=${FIRST_MONTH}; MONTH<=${LAST_MONTH}; MONTH++ ))
  do
    if [ ${NFILES} -ne $(ls -1 ${OUTDIR}/${YYYY_PREV}_$(printf %02d ${MONTH}) | wc -l) ]
    then
      echo ERROR: Not all monthly directories of ${YYYY_PREV} contain the same number of files
      if [ -n "${NOTIFICATION_ADDRESS}" ]
      then
        echo Error in post > ${PFDIR}/${EXPID}/error_message
        echo Not all monthly directories of ${YYYY_PREV} contain the same number of files
        ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
        rm ${PFDIR}/${EXPID}/error_message
      fi
      exit
    fi
  done

  cd ${OUTDIR}/yearly
  COUNTPP=0
  for FILE in ${FILELIST}
  do
(
      suffix=$(basename $FILE |cut -d. -f2) ##in case of repairments the file are already *.ncz formatted
      DIR=yearly/$(basename ${FILE} _ts.$suffix)
##      DIR=yearly/$(basename ${FILE} _ts.nc)
      [ -d ${OUTDIR}/${DIR} ] || mkdir -p  ${OUTDIR}/${DIR}
      PARAM=$(${NC_BINDIR}/ncdump -h ${OUTDIR}/${YYYY_MM}/${FILE} | grep ", rlat, rlon" | cut -d\  -f 2 | cut -d\( -f 1)
##      FPARAM=$(echo ${FILE%"_ts.nc"})
      FPARAM=$(echo ${FILE%"_ts.$suffix"})
      if [ "$(${CFU} get_attval ${OUTDIR}/${YYYY_MM}/${FILE} ${PARAM} cell_methods | grep 'time: point')" == "" ] && \
         [ "$(${CFU} get_attval ${OUTDIR}/${YYYY_MM}/${FILE} ${PARAM} cell_methods)" != "--" ] ## accumulated, avaraged, min/max variables
      then
        echo ${FILE} " is accumulated value in loop " ${COUNTPP}
        ${NCO_BINDIR}/ncrcat -h -O ${OUTDIR}/${YYYY_PREV}_??/${FILE}* tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc
#        NT=$(${CDO} -s ntime tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc)
#        (( NTM=NT-2 ))
        VT=($(${CFU} tbtimestamp tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc))
        TYF=$(echo ${VT[0]} | cut -c1-4)
        TMF=$(echo ${VT[0]} | cut -c6-7)
        TDF=$(echo ${VT[0]} | cut -c9-10)
        THF=$(echo ${VT[0]} | cut -c12-13)
        TYL=$(echo ${VT[*]: -1} | cut -c1-4)
        TML=$(echo ${VT[*]: -1} | cut -c6-7)
        TDL=$(echo ${VT[*]: -1} | cut -c9-10)
        THL=$(echo ${VT[*]: -1} | cut -c12-13)
        OUTFILE=${FPARAM}_${TYF}${TMF}${TDF}${THF}-${TYL}${TML}${TDL}${THL}.nc
#        ${NCO_BINDIR}/ncks -h -O -d time,0,${NTM} tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc ${OUTDIR}/${DIR}/${OUTFILE}
#        ${NCO_BINDIR}/ncks -h -O -F -d time,${NT},${NT} tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc ${OUTDIR}/${DIR}/prevprevtmp.nc

        mv tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc ${OUTDIR}/${DIR}/${OUTFILE}

      else                                                                                          ## instantaneous variables
        echo ${FILE} " is instantaneous value in loop " ${COUNTPP}
        NT=$(${CDO} -s ntime ${OUTDIR}/${YYYY_PREV}_12/${FILE}*)
        (( NTM=NT-2 ))
	${NCO_BINDIR}/ncks -h -O -d time,0,${NTM} ${OUTDIR}/${YYYY_PREV}_12/${FILE}* tmp${EXPID}${YYYY}${MM}Yb${COUNTPP}.nc ## reduced december file (without 00:00 of next year)
        if [[ $YYYY_PREV -ne $YYYY_START ]] ; then
          ${NCO_BINDIR}/ncks -h -d time,-1 ${OUTDIR}/${YYYY_PREV_PREV}_12/${FILE}* tmp${EXPID}${YYYY}${MM}Ya${COUNTPP}.nc
	  ${NCO_BINDIR}/ncrcat -h -O tmp${EXPID}${YYYY}${MM}Ya${COUNTPP}.nc ${OUTDIR}/${YYYY_PREV}_0?/${FILE}* ${OUTDIR}/${YYYY_PREV}_1[01]/${FILE}* tmp${EXPID}${YYYY}${MM}Yb${COUNTPP}.nc tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc
          rm -f tmp${EXPID}${YYYY}${MM}Ya${COUNTPP}.nc	
        else
	  ${NCO_BINDIR}/ncrcat -h -O ${OUTDIR}/${YYYY_PREV}_0?/${FILE}* ${OUTDIR}/${YYYY_PREV}_1[01]/${FILE}* tmp${EXPID}${YYYY}${MM}Yb${COUNTPP}.nc tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc
        fi
        VT=($(${CDO} -s showtimestamp tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc))
        TYF=$(echo ${VT[0]} | cut -c1-4)
        TMF=$(echo ${VT[0]} | cut -c6-7)
        TDF=$(echo ${VT[0]} | cut -c9-10)
        THF=$(echo ${VT[0]} | cut -c12-13)
        TYL=$(echo ${VT[*]: -1} | cut -c1-4)
        TML=$(echo ${VT[*]: -1} | cut -c6-7)
        TDL=$(echo ${VT[*]: -1} | cut -c9-10)
        THL=$(echo ${VT[*]: -1} | cut -c12-13)
        OUTFILE=${FPARAM}_${TYF}${TMF}${TDF}${THF}-${TYL}${TML}${TDL}${THL}.nc
        mv tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc ${OUTDIR}/${DIR}/${OUTFILE}
        rm -f tmp${EXPID}${YYYY}${MM}Yb${COUNTPP}.nc	

      fi
)&
    (( COUNTPP=COUNTPP+1 ))
    if [ ${COUNTPP} -ge ${MAXPP} ]
    then
      COUNTPP=0
      wait
      echo "Block finished"
    fi

  done
  wait

# !!!!!!! add a check, if all concatenations went well !!!!!!!!

  YEAR_FINISHED=1

elif [ ${NEXT_DATE} -eq ${YDATE_STOP} ]                                                 ## final year
then
  echo ... combining monthly data into year for ${YYYY}

  FIRST_MONTH=1
  LAST_MONTH=${YDATE_STOP:4:2}

  if [ ${YDATE_START:0:4} -eq ${YDATE_STOP:0:4} ]
  then
    FIRST_MONTH=${YDATE_START:4:2}
  fi

  if [ ${LAST_MONTH} -eq 1 ]
  then
    LAST_MONTH=12
  else
    let "LAST_MONTH = LAST_MONTH - 1"
  fi

  NFILES=$(ls -1 ${OUTDIR}/${YYYY}_$(printf %02d ${FIRST_MONTH}) | wc -l)
  for (( MONTH=${FIRST_MONTH}; MONTH<=${LAST_MONTH}; MONTH++ ))
  do
    if [ ${NFILES} -ne $(ls -1 ${OUTDIR}/${YYYY}_$(printf %02d ${MONTH}) | wc -l) ]
    then
      echo ERROR: Not all monthly directories of ${YYYY} contain the same number of files
      if [ -n "${NOTIFICATION_ADDRESS}" ]
      then
        echo Error in post > ${PFDIR}/${EXPID}/error_message
        echo Not all monthly directories of ${YYYY} contain the same number of files
        ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
        rm ${PFDIR}/${EXPID}/error_message
      fi
      exit
    fi
  done

  cd ${OUTDIR}/yearly
  COUNTPP=0
  for FILE in ${FILELIST}
  do
(
    suffix=$(basename $FILE |cut -d. -f2) ##in case of repairments the file are already *.ncz formatted
    DIR=yearly/$(basename ${FILE} _ts.$suffix)
    [ -d ${OUTDIR}/${DIR} ] || mkdir -p  ${OUTDIR}/${DIR}
    PARAM=$(${NC_BINDIR}/ncdump -h ${OUTDIR}/${YYYY_MM}/${FILE} | grep ", rlat, rlon" | cut -d\  -f 2 | cut -d\( -f 1)
    FPARAM=$(echo ${FILE%"_ts.$suffix"})
##    FPARAM=$(echo ${FILE%"_ts.nc"})
    if [ "$(${CFU} get_attval ${OUTDIR}/${YYYY_MM}/${FILE} ${PARAM} cell_methods | grep 'time: point')" == "" ] && \
       [ "$(${CFU} get_attval ${OUTDIR}/${YYYY_MM}/${FILE} ${PARAM} cell_methods)" != "--" ] ## accumulated, avaraged, min/max variables
    then
      echo ${FILE} " is accumulated value in loop " ${COUNTPP}
      ${NCO_BINDIR}/ncrcat -h -O ${OUTDIR}/${YYYY}_??/${FILE}* tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc

#      NT=$(${CDO} -s ntime tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc)
#      (( NTM=NT-2 ))
      VT=($(${CFU} tbtimestamp tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc))
      TYF=$(echo ${VT[0]} | cut -c1-4)
      TMF=$(echo ${VT[0]} | cut -c6-7)
      TDF=$(echo ${VT[0]} | cut -c9-10)
      THF=$(echo ${VT[0]} | cut -c12-13)
      TYL=$(echo ${VT[*]: -1} | cut -c1-4)
      TML=$(echo ${VT[*]: -1} | cut -c6-7)
      TDL=$(echo ${VT[*]: -1} | cut -c9-10)
      THL=$(echo ${VT[*]: -1} | cut -c12-13)
      OUTFILE=${FPARAM}_${TYF}${TMF}${TDF}${THF}-${TYL}${TML}${TDL}${THL}.nc
##       ${NCO_BINDIR}/ncks -h -O -d time,0,${NTM} tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc ${OUTDIR}/${YYYY}/${OUTFILE}
##       ${NCO_BINDIR}/ncks -h -O -d time,0,${NTM} tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc ${OUTDIR}/${DIR}/${OUTFILE}

      mv tmp${EXPID}${YYYY}${MM}${COUNTPP}.nc ${OUTDIR}/${DIR}/${OUTFILE}
    else                                                                                       ## instantaneous
      echo ${FILE} " is instantaneous value in loop " ${COUNTPP}
      NT=$(${CDO} -s ntime ${OUTDIR}/${YYYY}_${LAST_MONTH}/${FILE}*)
      (( NTM=NT-2 ))
      ${NCO_BINDIR}/ncks -h -O -d time,0,${NTM} ${OUTDIR}/${YYYY}_${LAST_MONTH}/${FILE} tmp${EXPID}${YYYY}${MM}Yb${COUNTPP}.nc  ## reduced last month file (without 00:00 of next year)
      ${NCO_BINDIR}/ncks -h -O -d time,0,-1 ${OUTDIR}/${YYYY}_${LAST_MONTH}/${FILE} ${OUTDIR}/${DIR}/${FPARAM}_${YDATE_STOP}.nc
##      mv tmp${EXPID}${YYYY}${MM}Yb${COUNTPP}.nc ${OUTDIR}/${YYYY}_${LAST_MONTH}/${FILE}_ts.nc
      mv tmp${EXPID}${YYYY}${MM}Yb${COUNTPP}.nc ${OUTDIR}/${YYYY}_${LAST_MONTH}/${FILE}

      if [[ $YYYY -ne $YYYY_START ]] ; then
        ${NCO_BINDIR}/ncks -h -d time,-1 ${OUTDIR}/${YYYY_PREV}_12/${FILE}* tmp${EXPID}${YYYY}${MM}Ya${COUNTPP}.nc
	${NCO_BINDIR}/ncrcat -h -O tmp${EXPID}${YYYY}${MM}Ya${COUNTPP}.nc ${OUTDIR}/${YYYY}_??/${FILE}* tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc
        rm -f tmp${EXPID}${YYYY}${MM}Ya${COUNTPP}.nc
      else
	${NCO_BINDIR}/ncrcat -h -O ${OUTDIR}/${YYYY}_??/${FILE}* tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc
      fi
	
      VT=($(${CDO} -s showtimestamp tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc))
      TYF=$(echo ${VT[0]} | cut -c1-4)
      TMF=$(echo ${VT[0]} | cut -c6-7)
      TDF=$(echo ${VT[0]} | cut -c9-10)
      THF=$(echo ${VT[0]} | cut -c12-13)
      TYL=$(echo ${VT[*]: -1} | cut -c1-4)
      TML=$(echo ${VT[*]: -1} | cut -c6-7)
      TDL=$(echo ${VT[*]: -1} | cut -c9-10)
      THL=$(echo ${VT[*]: -1} | cut -c12-13)
      OUTFILE=${FPARAM}_${TYF}${TMF}${TDF}${THF}-${TYL}${TML}${TDL}${THL}.nc
      mv tmp${EXPID}${YYYY}${MM}Y${COUNTPP}.nc ${OUTDIR}/${DIR}/${OUTFILE}
	
    fi

)&
    (( COUNTPP=COUNTPP+1 ))
    if [ ${COUNTPP} -ge ${MAXPP} ]
    then
      COUNTPP=0
      wait
      echo "Block finished"
    fi

  done
  wait

#!!!!!!! ToDo: add a check, whether all concatenations went well !!!!!!!!

#clean up of tmp files except those who are a result of an nco  error
  find ${OUTDIR}/yearly -maxdepth 1 -type f ! -name '*pid*' -delete

  YEAR_FINISHED=1

fi

if [ ${YEAR_FINISHED} -eq 1 ]
then
#################################################
# compress data
#################################################
case ${ITYPE_COMPRESS_POST} in

0)        #... no compression

  echo "**** no compression ****"
  ;;

1)        #... internal netCDF compression

  echo "**** internal netCDF compression"
  cd ${OUTDIR}/yearly

  FORMAT_SUFFIX=ncz  # do not use nc here !!!
  COUNTPP=0
  #.. This setting didn't compress five radiation files from out05
  #FILELIST=$(ls -1 ${OUTDIR}/yearly/*/*_${YYYY_PREV}*nc)
  #.. This settings compress all files:
  FILELIST=$(ls -1 ${OUTDIR}/yearly/*/*.nc)
  for FILE in ${FILELIST}
  do
(
    ${NC_BINDIR}/nccopy -d 1 -s ${FILE} ${FILE%.nc}.${FORMAT_SUFFIX}
    SUCCESS=$?
    if [ $? == 0 ] ; then
       rm ${FILE}
    else
       echo ${NC_BINDIR}/nccopy -d 1 -s ${FILE} ${FILE%.nc}.${FORMAT_SUFFIX} was not successfull
    fi
)&
    (( COUNTPP=COUNTPP+1 ))
    if [ ${COUNTPP} -ge ${MAXPP} ]
    then
      COUNTPP=0
      wait
    fi
  done
  wait

  if [ ${ITYPE_TS} -eq 3 ]
  then
    if [ ${NEXT_DATE} -eq ${YDATE_STOP} ]
    then
       YYYY_COMPRESS=${YYYY}
    else
       YYYY_COMPRESS=${YYYY_PREV}
    fi
    cd ${OUTDIR}
    FORMAT_SUFFIX=ncz  # do not use nc here !!!
    COUNTPP=0
    FILELIST=$(ls -1 ${YYYY_COMPRESS}_??/*.nc)
    for FILE in ${FILELIST}
    do
(
      ${NC_BINDIR}/nccopy -d 1 -s ${FILE} ${FILE%.nc}.${FORMAT_SUFFIX}
      SUCCESS=$?
      if [ $? == 0 ] ; then
         rm ${FILE}
      else
         echo ${NC_BINDIR}/nccopy -d 1 -s ${FILE} ${FILE%.nc}.${FORMAT_SUFFIX} was not successfull
      fi
)&
      (( COUNTPP=COUNTPP+1 ))
      if [ ${COUNTPP} -ge ${MAXPP} ]
      then
        COUNTPP=0
        wait
      fi
    done
    wait
  fi
  ;;

2)       #... gzip compression

  echo "**** gzip compression"
  cd ${OUTDIR}/yearly

  COUNTPP=0
  FILELIST=$(ls -1 */*.nc)
  for FILE in ${FILELIST}
  do
    gzip ${FILE} &
    (( COUNTPP=COUNTPP+1 ))
    if [ ${COUNTPP} -ge ${MAXPP} ]
    then
      COUNTPP=0
      wait
    fi
  done
  wait

  if [ ${ITYPE_TS} -eq 3 ]
  then
    if [ ${NEXT_DATE} -eq ${YDATE_STOP} ]
    then
       YYYY_COMPRESS=${YYYY}
    else
       YYYY_COMPRESS=${YYYY_PREV}
    fi
    cd ${OUTDIR}
    FORMAT_SUFFIX=ncz  # do not use nc here !!!
    COUNTPP=0
    FILELIST=$(ls -1 ${YYYY_COMPRESS}_??/*.nc)
    for FILE in ${FILELIST}
    do
      gzip ${FILE} &
      (( COUNTPP=COUNTPP+1 ))
      if [ ${COUNTPP} -ge ${MAXPP} ]
      then
        COUNTPP=0
        wait
      fi
    done
    wait
  fi
  ;;

3)       #... pigz compression

  echo "**** pigz compression"
  cd ${OUTDIR}/yearly

  FILELIST=$(ls -1 */*.nc)
  for FILE in ${FILELIST}
  do
    ${PIGZ} --fast -p ${MAXPP} ${FILE}
  done

  if [ ${ITYPE_TS} -eq 3 ]
  then
    if [ ${NEXT_DATE} -eq ${YDATE_STOP} ]
    then
       YYYY_COMPRESS=${YYYY}
    else
       YYYY_COMPRESS=${YYYY_PREV}
    fi
    cd ${OUTDIR}
    FORMAT_SUFFIX=ncz  # do not use nc here !!!
    COUNTPP=0
    FILELIST=$(ls -1 ${YYYY_COMPRESS}_??/*.nc)
    for FILE in ${FILELIST}
    do
      ${PIGZ} --fast -p ${MAXPP} ${FILE}
      (( COUNTPP=COUNTPP+1 ))
      if [ ${COUNTPP} -ge ${MAXPP} ]
      then
        COUNTPP=0
        wait
      fi
    done
    wait
  fi
  ;;

*)

  echo "**** invalid value for  ITYPE_COMPRESS_ARCH: "${ITYPE_COMPRESS_POST}
  echo "**** no compression applied"
  ;;

esac

fi # YEAR_FINISHED

