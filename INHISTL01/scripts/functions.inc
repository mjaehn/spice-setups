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

#########################################################
#########################################################
# functions used in the chain scripts
#########################################################
#########################################################

#########################################################
#... function for correcting CDO created netCDF
#########################################################
function cdocor {
  # CALL: inparameter infile outparameter outfile

  inparameter=$1
  infile=$2
  outparameter=$3
  outfile=$4

  #... set the _FillValue to -1.E20
  set +e
  fillvalue=$(${NC_BINDIR}/ncdump -h ${outfile} | grep ${outparameter}:_FillValue)
  if [ "${fillvalue}" ]
  then
    ${CDO} -s setmissval,-1.E20 ${outfile} ${outfile}_tmp${EXPID}${YYYY}${MM}
    mv ${outfile}_tmp${EXPID}${YYYY}${MM} ${outfile}
  fi
  set -e
  # get the coordinates from the original file
  COORDINATES=$(${NC_BINDIR}/ncdump -h ${infile} | grep ${inparameter}:coordinates | cut -d'"' -f2)
  # only if coordinates exists a correction is necessary
  if [ "${COORDINATES}" ]
  then
    ${NCO_BINDIR}/ncatted -h -a coordinates,${outparameter},o,c,"${COORDINATES}" ${outfile}
    # if the rotated_pole variable exists exclude it from the copy list
    ${NC_BINDIR}/ncdump -h ${outfile} | grep "rotated_pole ;" > /dev/null
    if [ $? -ne 0 ]
    then
      COORDINATES=$(echo ${COORDINATES} | tr ' ' ','),rotated_pole
    else
      COORDINATES=$(echo ${COORDINATES} | tr ' ' ',')
    fi
    # copy coordinates from old to new file
    ${NCO_BINDIR}/ncks -h -A -C -v ${COORDINATES} ${infile} ${outfile}
  fi
}

#########################################################
#... function for correcting ICON output regarding CF conventions
#########################################################
function iconcor {
  COUNT=$1
  INC=$2
  FILE=$3
  OPER=$4

  if [ $(echo ${FILE} | rev | cut -c -4 | rev) == 'p.nc' ]
  then
     ${NCO_BINDIR}/ncrename -h -d plev,pressure -v plev,pressure ${FILE} > /dev/null
  fi

  if [ $(echo ${FILE} | rev | cut -c -4 | rev) == 'z.nc' ]
  then
    if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'altitude')" != "" ]
    then
      ${NCO_BINDIR}/ncrename -h -d alt,altitude -v alt,altitude ${FILE} > /dev/null
      ${NCO_BINDIR}/ncap2 -h -O -s 'altitude=float(altitude)' ${FILE} tmp${EXPID}${YYYY}${MM}${COUNT}.nc
      cp tmp${EXPID}${YYYY}${MM}${COUNT}.nc ${FILE}
      rm tmp${EXPID}${YYYY}${MM}${COUNT}.nc
    fi
  fi

#... in case of runoff_s or runoff_g remove the dimension depth
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'runoff_s_t_8')" != "" ]
  then
    DEPTH=$(${NC_BINDIR}/ncdump -h ${FILE} | grep time\,\ depth | grep runoff_s_t_8 | cut -d, -f 2) ; DEPTH=$(echo ${DEPTH##*( )})
    ${NCO_BINDIR}/ncwa -h -O --no_cell_methods -a ${DEPTH} ${FILE} tmp${EXPID}${YYYY}${MM}${COUNT}.nc
    ${NCO_BINDIR}/ncks -h -O -x -v ${DEPTH},${DEPTH}_bnds tmp${EXPID}${YYYY}${MM}${COUNT}.nc ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${COUNT}.nc
  elif [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'runoff_s')" != "" ] ; then
    DEPTH=$(${NC_BINDIR}/ncdump -h ${FILE} | grep time\,\ depth | grep runoff_s | cut -d, -f 2) ; DEPTH=$(echo ${DEPTH##*( )})
    ${NCO_BINDIR}/ncwa -h -O --no_cell_methods -a ${DEPTH} ${FILE} tmp${EXPID}${YYYY}${MM}${COUNT}.nc
    ${NCO_BINDIR}/ncks -h -O -x -v ${DEPTH},${DEPTH}_bnds tmp${EXPID}${YYYY}${MM}${COUNT}.nc ${FILE}
    ${NCO_BINDIR}/ncatted -h -a cell_methods,runoff_s,o,c,'time: sum' ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${COUNT}.nc
  fi
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'runoff_g')" != "" ]
  then
    DEPTH=$(${NC_BINDIR}/ncdump -h ${FILE} | grep time\,\ depth | grep runoff_g | cut -d, -f 2) ; DEPTH=$(echo ${DEPTH##*( )})
    ${NCO_BINDIR}/ncwa -h -O --no_cell_methods -a ${DEPTH} ${FILE} tmp${EXPID}${YYYY}${MM}${COUNT}.nc
    ${NCO_BINDIR}/ncks -h -O -x -v ${DEPTH},${DEPTH}_bnds tmp${EXPID}${YYYY}${MM}${COUNT}.nc ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${COUNT}.nc
  fi

#----------------------------------------------------------------------------------------
#... call program for the main corrections regarding CF-netCDF
  set -e
  ${CORRECT_CF} ${INC} ${OUTPUT_MAPPING_FILE} ${FILE} ${OPER}
  set +e
#----------------------------------------------------------------------------------------

  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'height_2m = 1')" != "" ]
  then
    ${NCO_BINDIR}/ncwa -h -O --no_cell_methods -a height_2m ${FILE} tmp${EXPID}${YYYY}${MM}${COUNT}.nc
    ${NCO_BINDIR}/ncap2 -h -O -s 'height_2m=float(height_2m)' tmp${EXPID}${YYYY}${MM}${COUNT}.nc ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${COUNT}.nc
  fi
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'height_10m = 1')" != "" ]
  then
    ${NCO_BINDIR}/ncwa -h -O --no_cell_methods -a height_10m ${FILE} tmp${EXPID}${YYYY}${MM}${COUNT}.nc
    ${NCO_BINDIR}/ncap2 -h -O -s 'height_10m=float(height_10m)' tmp${EXPID}${YYYY}${MM}${COUNT}.nc ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${COUNT}.nc
  fi

#... Set global attributes. Attribute param ist only a number which may be deleted
  ${NCO_BINDIR}/ncatted -h -a institution,,d,, -a param,,d,, ${FILE}
  ${NCO_BINDIR}/ncatted -h -a title,GLOBAL,o,c,"${GA_TITLE}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a institution,GLOBAL,o,c,"${GA_INSTITUTION}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a project_id,GLOBAL,o,c,"${GA_PROJECT_ID}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a experiment_id,GLOBAL,o,c,"${EXPID}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a realization,GLOBAL,o,c,"${GA_REALIZATION}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a Conventions,GLOBAL,o,c,"${GA_CONVENTIONS}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a ConventionsURL,GLOBAL,o,c,"${GA_CONVENTIONSURL}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a contact,GLOBAL,o,c,"${GA_CONTACT}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a icon-clm_version,GLOBAL,o,c,"${GA_ICON_CLM_VERSION}" ${FILE}
  ${NCO_BINDIR}/ncatted -h -a creation_date,GLOBAL,o,c,"$(date '+%Y-%m-%d %H:%M:%S %Z')" ${FILE}

}

#########################################################
#... function for correcting time_bnds
#########################################################
function cell_methods_time {
  # in case cell_methods exists the value of the time variable is replaced by the value of middle of the time interval

  CELL_FILE=$1
  CELL_PARAM=$2
  CELL_SUFFIX=$3

  if [ "$(${CFU} get_attval ${CELL_FILE} ${CELL_PARAM}${CELL_SUFFIX} cell_methods | grep 'time: point')" == "" ] && \
        [ "$(${CFU} get_attval ${CELL_FILE} ${CELL_PARAM}${CELL_SUFFIX} cell_methods)" != "--" ]
  then
 #echo "Process "${CELL_PARAM}" with time_bnds"
    ${NCO_BINDIR}/ncwa -h -O -C -v time_bnds -a bnds ${CELL_FILE} tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc
#    ${NCO_BINDIR}/ncrename -h -v time_bnds,time tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc # this might give strange results therefore better apply ncap2
    ${NCO_BINDIR}/ncap2 -O -s "time=time_bnds" tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}2.nc
    ${NCO_BINDIR}/ncks -O -v time tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}2.nc tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc
    ${NCO_BINDIR}/ncatted -h -a ,time,d,,, tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc
    ${NCO_BINDIR}/ncks -h -A tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc ${CELL_FILE}
    rm -f tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}2.nc
    if [ ${CURRENT_DATE} -eq ${YDATE_START} ]
    then
      ${NCO_BINDIR}/ncks -h -O -d time,1,  ${CELL_FILE} tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc
      mv tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc ${CELL_FILE}
    fi
    rm -f tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc
  else
  # otherwise, i.e. for intantaneous values, time_bnds are deleted
    ${NCO_BINDIR}/ncatted -h -a bounds,time,d,, ${CELL_FILE}
    ${NCO_BINDIR}/ncks -h -x -v time_bnds ${CELL_FILE} tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc
    mv tmp${EXPID}${YYYY}${MM}${CELL_PARAM}${CELL_SUFFIX}.nc ${CELL_FILE}
  fi
  CELL_FILE=
  CELL_PARAM=
  CELL_SUFFIX=

}

#########################################################
#... function for height interpolation over terrain height
#########################################################

function height_interpolation {
  COUNT=$1
  declare -p HLEVS=("${!2}") > /dev/null
#  declare -p PARAMS=("${!3}") > /dev/null
  OUTPATH=$3
  FILE=$4

  FILEOUT=${OUTPATH}/$(basename ${FILE} .nc)z.nc
  cp ${FILE} tmp${EXPID}${YYYY}${MM}1_${COUNT}.nc
  ${NCO_BINDIR}/ncks -h -A ${WORKDIR}/${EXPID}/post/z_mc-topography_c.nc tmp${EXPID}${YYYY}${MM}1_${COUNT}.nc
  #... the attributes for missing values must be deleted, because CDO does not interpolate fields
  #...    that contain missing values. lmask_boundary=.true. gives -9.99e-08 as missing value in
  #...    the lateral boundary zone
  ${NCO_BINDIR}/ncatted -h -a _FillValue,,d,,, -a missing_value,,d,,, tmp${EXPID}${YYYY}${MM}1_${COUNT}.nc
  ${CDO} -s gh2hlx,$(echo ${HLEVS[@]} | sed 's/ /,/g') tmp${EXPID}${YYYY}${MM}1_${COUNT}.nc tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  #... cdo produces nan in the lateral boundary zone where the values are all -9.99e-08
  #... the following ncatted for re-installing the missing value has to be called twice,
  #...    because a direct definition of the missing value does not work, when the missing values are nan.
  ${NCO_BINDIR}/ncatted -h -a _FillValue,,o,f,nan -a missing_value,,o,f,nan tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncatted -h -a _FillValue,,m,f,-9.99e-08 -a missing_value,,m,f,-9.99e-08 tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncatted -h -a _FillValue,time,d,,, -a missing_value,time,d,,, tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncatted -h -a _FillValue,clat_bnds,d,,, -a missing_value,clat_bnds,d,,, -a _FillValue,clon_bnds,d,,, -a missing_value,clon_bnds,d,,, tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncatted -h -a _FillValue,clat,d,,, -a missing_value,clat,d,,, -a _FillValue,clon,d,,, -a missing_value,clon,d,,, tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncks -O -x -v height tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncrename -h -d height_2,height -v height_2,height  tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncatted -h -a _FillValue,height,d,,, -a missing_value,height,d,,, tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
  ${NCO_BINDIR}/ncap2 -h -O -s 'height=float(height)' tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc ${FILEOUT}  ##BG added -O
  rm tmp${EXPID}${YYYY}${MM}1_${COUNT}.nc tmp${EXPID}${YYYY}${MM}2_${COUNT}.nc
}

#########################################################
#... function for remapping time series from ICON to rotated grid
#########################################################

function remap2rot {

  REMAP=$1    # remapnn, remapdis, remapcon, remapycon remaplaf
  PARAM=$2  # name of variable to be remapped
  SUFFIX=$3

    #... currently the weights for remap produce an error when applied. Therefore they
    #...    are not yet used in the function remap2rot until the reason is found

  echo ${REMAP} ${PARAM}${SUFFIX}
  FILE=${OUTDIR}/${YYYY_MM}/${PARAM}${SUFFIX}_ts.nc

  #... preparation for coordinate corrections at the end of this function
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'height_2m')" != "" ]
  then
    COORDINATES=$(${NC_BINDIR}/ncdump -h ${FILE} | grep ${PARAM}:coordinates | cut -d'"' -f2 | sed 's!clon\ clat!lon\ lat!')
    ${NCO_BINDIR}/ncks -h -O -v height_2m ${FILE} tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}00.nc
    ${NCO_BINDIR}/ncatted -h -a ,global,d,, tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}00.nc
  fi
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'height_10m')" != "" ]
  then
    COORDINATES=$(${NC_BINDIR}/ncdump -h ${FILE} | grep ${PARAM}:coordinates | cut -d'"' -f2 | sed 's!clon\ clat!lon\ lat!')
    ${NCO_BINDIR}/ncks -h -O -v height_10m ${FILE} tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}00.nc
    ${NCO_BINDIR}/ncatted -h -a ,global,d,, tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}00.nc
  fi

  #... add clon/clat and clon_bnds/clat_bnds and coordinates attribute (needed for remapping with CDO)
  if [ "$(${CFU} get_attval ${FILE} ${PARAM}${SUFFIX} coordinates)" == "--" ]
  then
    ${NCO_BINDIR}/ncks -h -A ${OUTDIR}/icon_grid.nc ${FILE}
    ${NCO_BINDIR}/ncatted -h -a coordinates,${PARAM},c,c,"clon clat" ${FILE}
  fi

  #... change missing_value to standard -1.E20
  fillvalue=$(${NC_BINDIR}/ncdump -h ${FILE} | grep ${PARAM}:_FillValue)
  if [ "${fillvalue}" ]
  then
    ${CDO} -s setmissval,-1.E20 ${FILE} ${FILE}_tmp${EXPID}${YYYY}${MM}
    mv ${FILE}_tmp${EXPID}${YYYY}${MM} ${FILE}
  fi

  if [ y${SUFFIX: -1} == 'yz' ]
  then
    # data interpolated to heights over terrain have other weights
    ${CDO} -s -P ${OMP_THREADS_POST} ${REMAP},${TARGET_GRID} ${FILE} tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}.nc
  else
    #weights with source mask
    ${CDO} -s -P ${OMP_THREADS_POST} remap,${TARGET_GRID},${OUTDIR}/${REMAP}_weights.nc ${FILE} tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}.nc
  fi
  mv tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}.nc ${FILE}

  ${NCO_BINDIR}/ncks -h -O -v ${PARAM} ${FILE} tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}1.nc
  mv tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}1.nc ${FILE}

  #... correct the coordinates attribute
  if [ -f tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}00.nc ]
  then
    ${NCO_BINDIR}/ncks -h -A  tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}00.nc ${FILE}
    ${NCO_BINDIR}/ncatted -h -a coordinates,${PARAM},o,c,"${COORDINATES}" ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}00.nc
  fi

  #... in case cell_methods exists the value of the time variable is replaced by the value of middle of the time interval
  cell_methods_time ${OUTDIR}/${YYYY_MM}/${PARAM}${SUFFIX}_ts.nc ${PARAM} ${SUFFIX}

  #... modify dimension and cell_methods attribute for soil water
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'lwe_thickness_of_moisture_content_of_soil_layer')" != "" ] || \
     [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'lwe_thickness_of_frozen_water_content_of_soil_layer')" != "" ]
  then
    DEPTH=$(${NC_BINDIR}/ncdump -h ${FILE} | grep time\,\ depth | cut -d, -f 2) ; DEPTH=$(echo ${DEPTH##*( )})
    ${NCO_BINDIR}/ncks -3 ${FILE} tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc
    if [ ${DEPTH} != "depth" ]
    then
      ${NCO_BINDIR}/ncrename -d ${DEPTH},depth  \
                             -v ${DEPTH},depth -v ${DEPTH}_bnds,depth_bnds tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc
    fi
    ${NCO_BINDIR}/ncks -O -4 tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc ${FILE}
    ${NCO_BINDIR}/ncatted -h -a cell_methods,${PARAM},o,c,"time: point depth: sum" ${FILE}
    ${NCO_BINDIR}/ncatted -h -a bounds,depth,o,c,"depth_bnds" ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc
  fi

  #... modify dimension and cell_methods attribute for soil temperature. Remove 1 dimension, this is the same as T_S
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'solid_earth_subsurface_temperature')" != "" ]
  then
    DEPTH=$(${NC_BINDIR}/ncdump -h ${FILE} | grep time\,\ depth | cut -d, -f 2) ; DEPTH=$(echo ${DEPTH##*( )})
    ${NCO_BINDIR}/ncks -3 ${FILE} tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc
    if [ ${DEPTH} != "depth" ]
    then
      ${NCO_BINDIR}/ncrename -d ${DEPTH},depth  \
                             -v ${DEPTH},depth tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc
    fi
    #... remove first dimension
    ${NCO_BINDIR}/ncks -O -4 -d depth,1, tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc ${FILE}
    ${NCO_BINDIR}/ncatted -h -a cell_methods,${PARAM},o,c,"time: point" ${FILE}
    rm tmp${EXPID}${YYYY}${MM}${PARAM}${SUFFIX}soil.nc
  fi

  #... modify short_name and long_name of parameter depth
  if [ "$(${NC_BINDIR}/ncdump -h ${FILE} | grep 'double depth')" != "" ]
  then
    ${NCO_BINDIR}/ncatted -h -a short_name,depth,o,c,"depth" ${FILE}
    ${NCO_BINDIR}/ncatted -h -a long_name,depth,o,c,"depth below land" ${FILE}
  fi

  #... CDO writes institution=MPIMET into the output of each variable, this will be deleted here
  ${NCO_BINDIR}/ncatted -h -a institution,,d,, ${FILE}

}

##################################################################################################################
##################################################################################################################
#... functions for building time series
#      these are the essential functions to create the *_ts.nc files on post/YYYY_MM
#      the input quantities of for these functions are the icon_YYYYMMDDTHHmmssZ output files from ICON
##################################################################################################################
##################################################################################################################

#... building a time series for a given quantity
function timeseries {
  PARAM=$1
  OUTNN=$2
  REMAP=$3 # remapnn, remapdis, remapcon, remapycon remaplaf
#  WEIGHTS_FILE=$3
#  LSO=$4

  # if the 2nd argument is not given it is assumed to be an additional quantity and the function timeseriesa is called
  if [ -z $2 ]
  then
    timeseriesa $1
    return
  fi

  cd ${INPDIR}/${YYYY_MM}/${OUTNN}
  rm -f tmp${EXPID}${YYYY}${MM}${PARAM}.nc
  ${NCO_BINDIR}/ncrcat --no_cell_methods -h -O -v ${PARAM} icon_*[!cpz].nc ${OUTDIR}/${YYYY_MM}/${PARAM}_ts.nc

  remap2rot ${REMAP} ${PARAM}

}

##################################################################################################################
# building a time series on pressure levels for a given quantity

function timeseriesp {
  PARAM=$1
  OUTNN=$2
  declare -p PLEVS=("${!3}") > /dev/null
  REMAP=$4 # remapnn, remapdis, remapcon, remapycon remaplaf

  # if the 4th argument is not given it is assumed to be an additional quantity and the function timeseriesap is called
  if [ -z $4 ]
  then
    timeseriesap $1 $2
    return
  fi

  NPLEV=0
  while [[ ${NPLEV} -lt ${#PLEVS[@]} ]]
  do
    PASCAL=$(${PYTHON} -c "print(${PLEVS[${NPLEV}]} * 100.)")
#    PASCAL=$(${PYTHON} -c "print(${PLEVS[${NPLEV}]})")
    PLEV=$(${PYTHON} -c "print(int(${PLEVS[${NPLEV}]}))")
    cd ${INPDIR}/${YYYY_MM}/${OUTNN}
    rm -f tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}p.nc
    ${NCO_BINDIR}/ncrcat --no_cell_methods -h -O -d pressure,${PASCAL},${PASCAL} -v ${PARAM} icon_*p.nc* ${OUTDIR}/${YYYY_MM}/${PARAM}${PLEV}p_ts.nc

    ${NCO_BINDIR}/ncwa -h -O --no_cell_methods -a pressure -v ${PARAM} ${OUTDIR}/${YYYY_MM}/${PARAM}${PLEV}p_ts.nc tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}p.nc
    cp tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}p.nc ${OUTDIR}/${YYYY_MM}/${PARAM}${PLEV}p_ts.nc
    rm -f tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}p.nc
    ${NCO_BINDIR}/ncks -h -O -v pressure  ${OUTDIR}/${YYYY_MM}/${PARAM}${PLEV}p_ts.nc tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}pressure.nc
    ${NCO_BINDIR}/ncatted  -h -a ,global,d,, tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}pressure.nc
    remap2rot ${REMAP} ${PARAM} ${PLEV}p
    ${NCO_BINDIR}/ncks -h -A tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}pressure.nc ${OUTDIR}/${YYYY_MM}/${PARAM}${PLEV}p_ts.nc
    rm tmp${EXPID}${YYYY}${MM}${PARAM}${PLEV}pressure.nc
    ${NCO_BINDIR}/ncatted -h -O -a coordinates,$1,o,c,'lon lat pressure' ${OUTDIR}/${YYYY_MM}/${PARAM}${PLEV}p_ts.nc
    let "NPLEV = NPLEV + 1"
  done
}

##################################################################################################################
#... building a time series on height levels for a given quantity

function timeseriesz {
  PARAM=$1
  OUTNN=$2
  declare -p ZLEVS=("${!3}") > /dev/null
  REMAP=$4 # remapnn, remapdis, remapcon, remapycon remaplaf

  # if the 4th argument is not given it is assumed to be an additional quantity and the function timeseriesaz is called
  if [ -z $4 ]
  then
    timeseriesaz $1 $2
    return
  fi

  set +e
  ${NC_BINDIR}/ncdump -h ${INPDIR}/${YYYY_MM}/${OUTNN}/icon_${ISO_NEXT_DATE}z.nc | grep float\ ${PARAM} | grep height > /dev/null 2>&1
  ERROR_STATUS=$?
  set -e
  if [ ${ERROR_STATUS}  -eq 0 ]
  then
    HEIGHT=height
    NN=
  else
    HEIGHT=altitude
    NN=NN
  fi
  NZLEV=0
  while [[ ${NZLEV} -lt ${#ZLEVS[@]} ]]
  do
    ZLEV=$(${PYTHON} -c "print(int(${ZLEVS[${NZLEV}]}))")
    cd ${INPDIR}/${YYYY_MM}/$2
    ${NCO_BINDIR}/ncrcat --no_cell_methods -h -O -d ${HEIGHT},${ZLEV}.,${ZLEV}. -v ${PARAM} icon_*z.nc* ${OUTDIR}/${YYYY_MM}/${PARAM}${ZLEV}z${NN}_ts.nc

    ${NCO_BINDIR}/ncwa -h -O --no_cell_methods -a ${HEIGHT} -v ${PARAM} ${OUTDIR}/${YYYY_MM}/${PARAM}${ZLEV}z${NN}_ts.nc tmp${EXPID}${YYYY}${MM}${PARAM}${ZLEV}z${NN}.nc
    cp tmp${EXPID}${YYYY}${MM}${PARAM}${ZLEV}z${NN}.nc ${OUTDIR}/${YYYY_MM}/${PARAM}${ZLEV}z${NN}_ts.nc
    rm tmp${EXPID}${YYYY}${MM}${PARAM}${ZLEV}z${NN}.nc
    ${NCO_BINDIR}/ncks -h -O -v ${HEIGHT}  ${OUTDIR}/${YYYY_MM}/${PARAM}${ZLEV}z${NN}_ts.nc tmp${EXPID}${YYYY}${MM}${PARAM}${ZLEV}${HEIGHT}.nc
    ${NCO_BINDIR}/ncatted  -h -a ,global,d,, tmp${EXPID}${YYYY}${MM}${PARAM}${ZLEV}${HEIGHT}.nc
    remap2rot ${REMAP} ${PARAM} ${ZLEV}z${NN}
    ${NCO_BINDIR}/ncks -h -A tmp${EXPID}${YYYY}${MM}${PARAM}${ZLEV}${HEIGHT}.nc ${OUTDIR}/${YYYY_MM}/${PARAM}${ZLEV}z${NN}_ts.nc
    rm tmp${EXPID}${YYYY}${MM}${PARAM}${ZLEV}${HEIGHT}.nc
    ${NCO_BINDIR}/ncatted -h -O -a coordinates,$1,o,c,"lon lat ${HEIGHT}" ${OUTDIR}/${YYYY_MM}/${PARAM}${ZLEV}z${NN}_ts.nc
    let "NZLEV = NZLEV + 1"
  done
}

##################################################################################################################
##################################################################################################################
#... functions for calculating additional quantities
#      the calculations use *_ts.nc files from post/YYYY_MM
##################################################################################################################
##################################################################################################################

function timeseriesa {

 case ${1} in

   'ASOD_S')
      # averaged total downward sw radiation at the surface
      echo calculate ASOD_S ...
      infile1=${OUTDIR}/${YYYY_MM}/ASOB_S_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/ASODIFU_S_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/ASOD_S_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}ASOD_S.nc
          ${NCO_BINDIR}/ncks -h -A -v ASODIFU_S ${infile2} tmp${EXPID}${YYYY}${MM}ASOD_S.nc
          ${NCO_BINDIR}/ncap2 -O -s "ASOD_S=ASOB_S+ASODIFU_S" tmp${EXPID}${YYYY}${MM}ASOD_S.nc tmp${EXPID}${YYYY}${MM}ASOD_S.nc
          ${NCO_BINDIR}/ncks -h -O -v ASOD_S,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}ASOD_S.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,ASOD_S,m,c,"averaged total downward sw radiation at the surface" -a standard_name,ASOD_S,o,c,"surface_downwelling_shortwave_flux_in_air" ${outfile}
          rm tmp${EXPID}${YYYY}${MM}ASOD_S.nc
        else
          echo "Input fields " ASOB_S " and/or " ASODIFU_S " for calculating " ASOD_S " are missing"
        fi
      fi
     ;;

  'ASODIRD_S')
     # averaged solar direct downward flux at the surface
     echo calculate ASODIRD_S ...
     infile1=${OUTDIR}/${YYYY_MM}/ASOB_S_ts.nc
     infile2=${OUTDIR}/${YYYY_MM}/ASODIFU_S_ts.nc
     infile3=${OUTDIR}/${YYYY_MM}/ASODIFD_S_ts.nc
     outfile=${OUTDIR}/${YYYY_MM}/ASODIRD_S_ts.nc
     if [[ -f ${infile1} ]] && [[ -f ${infile2} ]] && [[ -f ${infile3} ]]
     then
       ${CDO} -s add ${infile1} -sub ${infile2} ${infile3} ${outfile}
       ${NCO_BINDIR}/ncrename -h -v ASOB_S,ASODIRD_S ${outfile}
       ${NCO_BINDIR}/ncatted -h -a standard_name,ASODIRD_S,m,c,"surface_direct_downwelling_shortwave_flux_in_air" ${outfile}
       ${NCO_BINDIR}/ncatted -h -a long_name,ASODIRD_S,m,c,"averaged surface downward direct solar radiation" ${outfile}
       ${NCO_BINDIR}/ncatted -h -a cell_methods,ASODIRD_S,m,c,"time: mean" ${outfile}
       # cdo removes the time_bnds units, create it again with the following command
       # MJ: time_bnds is missing, so it cannot modify the units attribute
       # ${NCO_BINDIR}/ncatted -h -a units,time_bnds,o,c,"$(${CFU} get_attval ${OUTDIR}/${YYYY_MM}/ASOB_S_ts.nc time units)" ${outfile}
     else
       echo "Input fields ASOB_S and/or ASODIFU_S and/or ASODIFD_S for calculating solar direct downward flux at the surface ASODIRD_S are missing"
     fi
    ;;

   'ASOU_T')
      # averaged solar upward radiation at top
      echo calculate ASOU_T ...
      infile1=${OUTDIR}/${YYYY_MM}/ASOD_T_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/ASOB_T_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/ASOU_T_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}ASOU_T.nc
          ${NCO_BINDIR}/ncks -h -A -v ASOB_T ${infile2} tmp${EXPID}${YYYY}${MM}ASOU_T.nc
          ${NCO_BINDIR}/ncap2 -O -s "ASOU_T=ASOD_T-ASOB_T" tmp${EXPID}${YYYY}${MM}ASOU_T.nc tmp${EXPID}${YYYY}${MM}ASOU_T.nc
          ${NCO_BINDIR}/ncks -h -O -v ASOU_T,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}ASOU_T.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,ASOU_T,m,c,"averaged solar upward radiation at top" -a standard_name,ASOU_T,m,c,"toa_outgoing_shortwave_flux" ${outfile}
          rm tmp${EXPID}${YYYY}${MM}ASOU_T.nc
        else
          echo "Input fields " ASOD_T " and/or " ASOB_T " for calculating " ASOU_T " are missing"
        fi
      fi
     ;;

   'ATHD_S')
      # averaged total downward lw radiation at the surface
      echo calculate ATHD_S ...
      infile1=${OUTDIR}/${YYYY_MM}/ATHB_S_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/ATHU_S_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/ATHD_S_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}ATHD_S.nc
          ${NCO_BINDIR}/ncks -h -A -v ATHU_S ${infile2} tmp${EXPID}${YYYY}${MM}ATHD_S.nc
          ${NCO_BINDIR}/ncap2 -O -s "ATHD_S=ATHB_S+ATHU_S" tmp${EXPID}${YYYY}${MM}ATHD_S.nc tmp${EXPID}${YYYY}${MM}ATHD_S.nc
          ${NCO_BINDIR}/ncks -h -O -v ATHD_S,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}ATHD_S.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,ATHD_S,m,c,"averaged total downward lw radiation at the surface" -a standard_name,ATHD_S,o,c,"surface_downwelling_longwave_flux_in_air" ${outfile}
          rm tmp${EXPID}${YYYY}${MM}ATHD_S.nc
        else
          echo "Input fields " ATHB_S " and/or " ATHU_S " for calculating " ATHD_S " are missing"
        fi
      fi
     ;;

   'DD_10M')
      #  wind direction in 10m height
      echo calculate DD_10M ...
      varname=DD_10M
      varnameULON=U_10M
      varnameVLAT=V_10M
      uvlonlatfile=UVlonlat_10M_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/${varname}_ts.nc
      infile1=${OUTDIR}/${YYYY_MM}/${varnameULON}_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/${varnameVLAT}_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp ${infile1} ${uvlonlatfile}
          ${NCO_BINDIR}/ncks -h -A -v ${varnameVLAT} ${infile2} ${uvlonlatfile}
        else
          echo "Input fields for calculating wind direction at 10m height are missing"
        fi
        ${NCO_BINDIR}/ncap2 -O -s "${varname}=float(45.0/atan(1.0)*atan2(${varnameULON},${varnameVLAT})+180.0)" ${uvlonlatfile} ${uvlonlatfile}
        ${NCO_BINDIR}/ncks -h -O -v ${varname},lat,lon,rotated_pole,height_10m ${uvlonlatfile} ${outfile}
        ${NCO_BINDIR}/ncatted -h -O -a standard_name,${varname},o,c,'wind_from_direction' -a long_name,${varname},o,c,'wind direction at 10m height' -a units,${varname},o,c,'deg' -a coordinates,${varname},c,c,'lon lat height_10m' -a cell_methods,${varname},o,c,'time: point' ${outfile}
        rm ${uvlonlatfile}
        # "The wind direction at 10m height was determined w.r.t. the geographical WGS84 system."
      fi
     ;;

   'DTR_2M')
      #  echo diurnal temperature range
      echo calculate DTR_2M ...
      outfile=${OUTDIR}/${YYYY_MM}/DTR_2M_ts.nc
      infile1=${OUTDIR}/${YYYY_MM}/TMAX_2M_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/TMIN_2M_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ]
        then
          ${CDO} -s sub ${infile1} ${infile2} ${outfile}
          ${NCO_BINDIR}/ncrename -h -v TMAX_2M,DTR_2M ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,DTR_2M,m,c,"diurnal temperature range" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a cell_methods,DTR_2M,m,c,"time: range" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a units,time_bnds,o,c,"$(${CFU} get_attval ${infile2} time units)" ${outfile}
        else
          echo "Input fields TMAX_2M and/or TMIN_2M for the diurnal temperature range DTR are missing"
        fi
      fi
     ;;

   'FIELDCAP')
      # field capacity, pore volume and wilting point
      echo calculate FIELDCAP, PORVOL, WILPOINT ...
      capfield=('1.E-10' '1.E-10' '0.196' '0.260' '0.340' '0.370' '0.463' '0.763' '-1.E20' '-1.E20')
      porfield=('1.E-10' '1.E-10' '0.364' '0.445' '0.455' '0.475' '0.507' '0.863' '-1.E20' '-1.E20')
      wilfield=('0.0' '0.0' '0.042' '0.100' '0.110' '0.185' '0.257' '0.265' '-1.E20' '-1.E20')

      iofile=${OUTDIR}/icon_c.nc
      if [ -f ${iofile} ] ; then

        ${NCO_BINDIR}/ncks -O -v SOILTYP ${OUTDIR}/icon_c.nc ${OUTDIR}/SOILTYP_c.nc
        cp ${OUTDIR}/SOILTYP_c.nc ${OUTDIR}/SOILTYP_p.nc
        cp ${OUTDIR}/SOILTYP_c.nc ${OUTDIR}/SOILTYP_w.nc

        for i in {1..10..1}
        do
          im1=$((i-1))
          #          echo $i ${capfield[$im1]} $im1
          ${NCO_BINDIR}/ncap2 -O -s 'where(SOILTYP=='$i') SOILTYP='${capfield[$im1]} ${OUTDIR}/SOILTYP_c.nc ${OUTDIR}/SOILTYP_c.nc
          ${NCO_BINDIR}/ncap2 -O -s 'where(SOILTYP=='$i') SOILTYP='${porfield[$im1]} ${OUTDIR}/SOILTYP_p.nc ${OUTDIR}/SOILTYP_p.nc
          ${NCO_BINDIR}/ncap2 -O -s 'where(SOILTYP=='$i') SOILTYP='${wilfield[$im1]} ${OUTDIR}/SOILTYP_w.nc ${OUTDIR}/SOILTYP_w.nc
        done

        mv ${OUTDIR}/SOILTYP_c.nc ${OUTDIR}/FIELDCAP.nc
        mv ${OUTDIR}/SOILTYP_p.nc ${OUTDIR}/PORVOL.nc
        mv ${OUTDIR}/SOILTYP_w.nc ${OUTDIR}/WILPOINT.nc

        ${NCO_BINDIR}/ncrename -v SOILTYP,FIELDCAP ${OUTDIR}/FIELDCAP.nc
        ${NCO_BINDIR}/ncrename -v SOILTYP,PORVOL ${OUTDIR}/PORVOL.nc
        ${NCO_BINDIR}/ncrename -v SOILTYP,WILPOINT ${OUTDIR}/WILPOINT.nc

        # -- Add standard_name to files:
        ${NCO_BINDIR}/ncatted -h -a standard_name,FIELDCAP,m,c,"volume_fraction_of_condensed_water_in_soil_at_field_capacity" ${OUTDIR}/FIELDCAP.nc
        ${NCO_BINDIR}/ncatted -h -a standard_name,PORVOL,m,c,"volume_fraction_of_pore_volume_in_soil" ${OUTDIR}/PORVOL.nc
        ${NCO_BINDIR}/ncatted -h -a standard_name,WILPOINT,m,c,"volume_fraction_of_condensed_water_at_wilting_point" ${OUTDIR}/WILPOINT.nc

        # -- Add long_name to files:
        ${NCO_BINDIR}/ncatted -h -a long_name,FIELDCAP,m,c,"volume fraction of soil moisture content at field capacity" ${OUTDIR}/FIELDCAP.nc
        ${NCO_BINDIR}/ncatted -h -a long_name,PORVOL,m,c,"volume fraction of soil pore volume" ${OUTDIR}/PORVOL.nc
        ${NCO_BINDIR}/ncatted -h -a long_name,WILPOINT,m,c,"volume fraction of soil moisture at wilting point" ${OUTDIR}/WILPOINT.nc

        # -- Merge files into icon_c.nc
        ${NCO_BINDIR}/ncks -A ${OUTDIR}/FIELDCAP.nc ${OUTDIR}/icon_c.nc
        ${NCO_BINDIR}/ncks -A ${OUTDIR}/PORVOL.nc ${OUTDIR}/icon_c.nc
        ${NCO_BINDIR}/ncks -A ${OUTDIR}/WILPOINT.nc ${OUTDIR}/icon_c.nc

        # -- Add extra attributes:
        rawdata=$(${NC_BINDIR}/ncdump -h ${EXTPAR}|grep -i rawdata|cut -d \" -f2)
        ${NCO_BINDIR}/ncatted -h -a rawdata,global,c,c,"${rawdata}"  ${OUTDIR}/icon_c.nc
        ${NCO_BINDIR}/ncatted -h -a flag_values,SOILTYP,c,c,"1, 2, 3, 4, 5, 6, 7, 8, 9, 0" -a flag_meanings,SOILTYP,c,c,"ice rock sand sandy_loam loam clay_loam clay peat water sea_ice" ${OUTDIR}/icon_c.nc
        ${NCO_BINDIR}/ncatted -h -a missing_value,SOILTYP,d,, -a missing_value,FIELDCAP,d,,  -a missing_value,PORVOL,d,, -a missing_value,WILPOINT,d,, ${OUTDIR}/icon_c.nc
        ${NCO_BINDIR}/ncatted -h -a _FillValue,SOILTYP,d,, -a _FillValue,FIELDCAP,m,f,-1.E20 -a _FillValue,PORVOL,m,f,-1.E20 -a _FillValue,WILPOINT,m,f,-1.E20 ${OUTDIR}/icon_c.nc

        # -- Remove temporal files:
        rm ${OUTDIR}/FIELDCAP.nc ${OUTDIR}/PORVOL.nc ${OUTDIR}/WILPOINT.nc
     else
       echo "Input file ${iofile} is missing"
     fi
    ;;

   'FR_SNOW')
      #  snow fraction
      echo calculate FR_SNOW ...
      varnamew=W_SNOW
      varnamef=FR_SNOW
      outfile=${OUTDIR}/${YYYY_MM}/${varnamef}_ts.nc
      infile1=${OUTDIR}/${YYYY_MM}/${varnamew}_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}snowfraction.nc
          ${NCO_BINDIR}/ncap2 -O -s "SNOW_flg = float(${varnamew} > 0.0000005); SNOW = float(${varnamew}/0.015); where(SNOW>1.0) SNOW=1.0f; where(SNOW<0.01) SNOW=0.01f; ${varnamef}=float(SNOW*SNOW_flg)" tmp${EXPID}${YYYY}${MM}snowfraction.nc tmp${EXPID}${YYYY}${MM}snowfraction.nc
          ${NCO_BINDIR}/ncks -h -O -v ${varnamef},lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}snowfraction.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -O -a standard_name,${varnamef},o,c,'surface_snow_area_fraction' -a long_name,${varnamef},o,c,'Snow Area Fraction' -a units,${varnamef},o,c,'1' -a cell_methods,${varnamef},o,c,'time: point'  ${outfile}
          rm   tmp${EXPID}${YYYY}${MM}snowfraction.nc
          # "The snow area fraction was calculated with the internally used method."
        else
          echo "Input field " ${varnamew} " for calculating snow area fraction is missing"
        fi
      fi
     ;;
   'T_SNOW')
      #  snow temperature
      echo "set T_SNOW to _FillValue where FR_SNOW = 0"
      varnamef=FR_SNOW
      varnamet=T_SNOW
      outfile=${OUTDIR}/${YYYY_MM}/${varnamet}_ts.nc
      infile1=${OUTDIR}/${YYYY_MM}/${varnamef}_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/${varnamet}_ts.nc
     if [[ -f ${infile1} && -f ${infile2} ]] ; then
        ${CDO} -P 8 -O --no_history merge ${infile1} ${infile2} tmp${EXPID}${YYYY}${MM}FR_T_SNOW.nc
        ${NCO_BINDIR}/ncap2 -O -s 'where(FR_SNOW==0)FR_SNOW=-1.E20;where(FR_SNOW>0)FR_SNOW=1;T_SNOW=FR_SNOW*T_SNOW' tmp${EXPID}${YYYY}${MM}FR_T_SNOW.nc tmp2${EXPID}${YYYY}${MM}FR_T_SNOW.nc
        ${CDO} -P 8 -O --no_history -selvar,T_SNOW tmp2${EXPID}${YYYY}${MM}FR_T_SNOW.nc ${outfile}
        rm tmp${EXPID}${YYYY}${MM}FR_T_SNOW.nc tmp2${EXPID}${YYYY}${MM}FR_T_SNOW.nc
        #echo "Snow temperature (T_SNOW) is now adjusted for regions with FR_SNOW>0"
      else
        echo "Snow temperature (T_SNOW) or snow fraction (FR_SNOW) is not available."
      fi
     ;;

   'PREC_CON')
      # convective precipitation
      echo calculate PREC_CON ...
      infile1=${OUTDIR}/${YYYY_MM}/RAIN_CON_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/SNOW_CON_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/PREC_CON_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}PREC_CON.nc
          ${NCO_BINDIR}/ncks -h -A -v SNOW_CON ${infile2} tmp${EXPID}${YYYY}${MM}PREC_CON.nc
          ${NCO_BINDIR}/ncap2 -O -s "PREC_CON=RAIN_CON+SNOW_CON" tmp${EXPID}${YYYY}${MM}PREC_CON.nc tmp${EXPID}${YYYY}${MM}PREC_CON.nc
          ${NCO_BINDIR}/ncks -h -O -v PREC_CON,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}PREC_CON.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,PREC_CON,m,c,"convective precipitation" -a standard_name,PREC_CON,o,c,"convective_precipitation_amount" ${outfile}
          rm tmp${EXPID}${YYYY}${MM}PREC_CON.nc
        else
          echo "Input fields " RAIN_CON " and/or " SNOW_CON " for calculating " PREC_CON " are missing"
        fi
      fi
     ;;

   'PVAP_2M')
      # water vapour partial pressure in 2m
      echo calculate PVAP_2M ...
      outfile=${OUTDIR}/${YYYY_MM}/PVAP_2M_ts.nc
      infile1=${OUTDIR}/${YYYY_MM}/APS_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/AQV_2M_ts.nc
      infile3=${OUTDIR}/${YYYY_MM}/AT_2M_ts.nc
      infile4=${OUTDIR}/${YYYY_MM}/ARELHUM_2M_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp ${infile1} ${OUTDIR}/${YYYY_MM}/PS_QV_ts.nc
          ${NCO_BINDIR}/ncks -A ${infile2} ${OUTDIR}/${YYYY_MM}/PS_QV_ts.nc
          ${NCO_BINDIR}/ncap2 -O -s "PVAP_2M=float(1/(0.622+0.378*AQV_2M)*AQV_2M*APS)" ${OUTDIR}/${YYYY_MM}/PS_QV_ts.nc ${OUTDIR}/${YYYY_MM}/PVAP_2M_ts_tmp.nc
          ${NCO_BINDIR}/ncks -h -O -v PVAP_2M,lon,lat,rotated_pole ${OUTDIR}/${YYYY_MM}/PVAP_2M_ts_tmp.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a standard_name,PVAP_2M,m,c,"water_vapour_partial_pressure_in_air" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a units,PVAP_2M,m,c,"Pa" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,PVAP_2M,m,c,"water vapour partial pressure in 2m" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a _FillValue,,m,f,-1.e20 ${outfile}
	  rm ${OUTDIR}/${YYYY_MM}/PVAP_2M_ts_tmp.nc ${OUTDIR}/${YYYY_MM}/PS_QV_ts.nc
        elif [ -f ${infile3} -a -f ${infile4} ] ; then
          cp ${infile3} ${OUTDIR}/${YYYY_MM}/T_RELHUM_ts.nc
          ${NCO_BINDIR}/ncks -A ${infile4} ${OUTDIR}/${YYYY_MM}/T_RELHUM_ts.nc
          # Verify if RELHUM_2M is present
          ${NCO_BINDIR}/ncks -m -v ARELHUM_2M ${OUTDIR}/${YYYY_MM}/T_RELHUM_ts.nc
          ${NCO_BINDIR}/ncap2 -O -s "PVAP_2M=AT_2M-999999" ${OUTDIR}/${YYYY_MM}/T_RELHUM_ts.nc ${OUTDIR}/${YYYY_MM}/T_RELHUM_ts.nc
          ${NCO_BINDIR}/ncap2 -O -s 'where ( AT_2M >=273.15 ) PVAP_2M=float(6.112*ARELHUM_2M*exp(17.62*(AT_2M-273.15)/(AT_2M-30.03))); elsewhere PVAP_2M=float(6.112*ARELHUM_2M*exp(22.46*(AT_2M-273.15)/(AT_2M-0.53))); ' ${OUTDIR}/${YYYY_MM}/T_RELHUM_ts.nc ${OUTDIR}/${YYYY_MM}/PVAP_2M_ts_tmp.nc
          ${NCO_BINDIR}/ncks -h -O -v PVAP_2M,lon,lat,rotated_pole ${OUTDIR}/${YYYY_MM}/PVAP_2M_ts_tmp.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a standard_name,PVAP_2M,m,c,"water_vapour_partial_pressure_in_air" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a units,PVAP_2M,m,c,"Pa" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,PVAP_2M,m,c,"water vapour partial pressure in 2m" ${outfile}
          ${NCO_BINDIR}/ncatted -h -a _FillValue,,m,f,-1.e20 ${outfile}
	  rm ${OUTDIR}/${YYYY_MM}/PVAP_2M_ts_tmp.nc ${outfile}_grid ${OUTDIR}/${YYYY_MM}/T_RELHUM_ts.nc
        else
          echo "Input fields PS+QV_2M or T_2M+RELHUM_2M for the water vapour partial pressure PVAP_2M are missing"
        fi
      fi
     ;;

   'APOTEVAP_S')
      # calculation of potential evapotranspiration
      echo calculate APOTEVAP_S ...
	  cd ${OUTDIR}/${YYYY_MM}
          ${PYTHON} ${PFDIR}/${EXPID}/scripts/calc_potevap_s.py ${OUTDIR}/${YYYY_MM}/
          ${NCO_BINDIR}/ncatted -h -a coordinates,,d,, ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.nc
          ${NCO_BINDIR}/ncatted -h -a coordinates,APOTEVAP_S,c,c,"lon lat height_2m" ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.nc
          ${NCO_BINDIR}/ncwa -O -a string1 ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.nc ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc
          # correct record variable
          ${NCO_BINDIR}/ncecat -h -O ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc
          ${NCO_BINDIR}/ncpdq -O -a time,record ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc
          ${NCO_BINDIR}/ncwa -O -a record ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc
          ${NCO_BINDIR}/ncatted -h -a cellmethods,APOTEVAP_S,m,c,'time: sum' -a cellmethods,rotated_pole,d,, ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc
          mv ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.tmp.nc ${OUTDIR}/${YYYY_MM}/APOTEVAP_S_ts.nc

     ;;

    'RUNOFF_S_corr')
      # correction of runoff
      echo calculate RUNOFF_S_corr ...

      infile1=${OUTDIR}/${YYYY_MM}/RUNOFF_S_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/RUNOFF_S_T_8_ts.nc
      infile4=${OUTDIR}/${EXPID}_c.nc
      outfile=${OUTDIR}/${YYYY_MM}/RUNOFF_S_uncorr_ts.nc
      frlake_thrld=0.05
      [ -e ${outfile} ] && cp ${outfile} ${infile1} # copy of original runoff data is case of repairement runs of post
      #if [ ! -e ${outfile} ] ; then
        #if [ -e tmp${EXPID}${YYYY}${MM}RUNOFF_S.nc ] && rm tmp${EXPID}${YYYY}${MM}RUNOFF_S.nc
        ${CDO} merge ${infile1}  ${infile2} tmp${EXPID}${YYYY}${MM}RUNOFF_S.nc
        ${NCO_BINDIR}/ncks -A -v FR_LAND,FR_LAKE $infile4 tmp${EXPID}${YYYY}${MM}RUNOFF_S.nc
        ## for complete lake grid points and mixed land/lake points the RUNOFF_S is corrected by the lake portion
        ${CDO} -expr,"RUNOFF_S=(FR_LAKE >= 1)? 0 : ((FR_LAKE > ${frlake_thrld})? (RUNOFF_S*(FR_LAND+FR_LAKE)-RUNOFF_S_T_8*FR_LAKE)/FR_LAND : RUNOFF_S ) " tmp${EXPID}${YYYY}${MM}RUNOFF_S.nc tmp${EXPID}${YYYY}${MM}RUNOFF_S_corr.nc

        mv $infile1 $outfile

        ${NCO_BINDIR}/ncks -h -O -v RUNOFF_S,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}RUNOFF_S_corr.nc ${infile1}
        ${NCO_BINDIR}/ncatted -h -a long_name,RUNOFF_S,m,c,"weighted surface water runoff (corrected for lake fraction > 5%: water which is leaving the land portion)" -a standard_name,RUNOFF_S,o,c,"surface_runoff_amount" -a cell_methods,RUNOFF_S,o,c,'time: sum' ${infile1}

        #echo tmp${EXPID}${YYYY}${MM}RUNOFF_S.nc tmp${EXPID}${YYYY}${MM}RUNOFF_S_corr.nc
        rm tmp${EXPID}${YYYY}${MM}RUNOFF_S.nc tmp${EXPID}${YYYY}${MM}RUNOFF_S_corr.nc
      ##fi
     ;;

    'RUNOFF_T')
      # total runoff
      echo calculate RUNOFF_T ...
      infile1=${OUTDIR}/${YYYY_MM}/RUNOFF_S_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/RUNOFF_G_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/RUNOFF_T_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}RUNOFF_T.nc
          ${NCO_BINDIR}/ncks -h -A -v RUNOFF_G ${infile2} tmp${EXPID}${YYYY}${MM}RUNOFF_T.nc
          ${NCO_BINDIR}/ncap2 -O -s "RUNOFF_T=RUNOFF_S+RUNOFF_G" tmp${EXPID}${YYYY}${MM}RUNOFF_T.nc tmp${EXPID}${YYYY}${MM}RUNOFF_T.nc
          ${NCO_BINDIR}/ncks -h -O -v RUNOFF_T,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}RUNOFF_T.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,RUNOFF_T,m,c,"total runoff" -a standard_name,RUNOFF_T,o,c,"total_runoff_amount"  -a cell_methods,RUNOFF_T,o,c,'time: sum' ${outfile}
          rm tmp${EXPID}${YYYY}${MM}RUNOFF_T.nc
        else
          echo "Input fields " RUNOFF_S " and/or " RUNOFF_G " for calculating " RUNOFF_T " are missing"
        fi
      fi
      ;;

   'SOD_S')
      # total downward sw radiation at the surface
      echo calculate SOD_S ...
      infile1=${OUTDIR}/${YYYY_MM}/SOBS_RAD_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/SODIFU_S_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/SOD_S_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}SOD_S.nc
          ${NCO_BINDIR}/ncks -h -A -v SODIFU_S ${infile2} tmp${EXPID}${YYYY}${MM}SOD_S.nc
          ${NCO_BINDIR}/ncap2 -O -s "SOD_S=SOBS_RAD+SODIFU_S" tmp${EXPID}${YYYY}${MM}SOD_S.nc tmp${EXPID}${YYYY}${MM}SOD_S.nc
          ${NCO_BINDIR}/ncks -h -O -v SOD_S,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}SOD_S.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,SOD_S,m,c,"total downward sw radiation at the surface" -a standard_name,SOD_S,o,c,"surface_downwelling_shortwave_flux_in_air" ${outfile}
          rm tmp${EXPID}${YYYY}${MM}SOD_S.nc
        else
          echo "Input fields " SOBS_RAD " and/or " SODIFU_S " for calculating " SOD_S " are missing"
        fi
      fi
     ;;

   'SODIRD_S')
     # solar direct downward flux at the surface
     echo calculate SODIRD_S ...
     infile1=${OUTDIR}/${YYYY_MM}/SOBS_RAD_ts.nc
     infile2=${OUTDIR}/${YYYY_MM}/SODIFU_S_ts.nc
     infile3=${OUTDIR}/${YYYY_MM}/SODIFD_S_ts.nc
     outfile=${OUTDIR}/${YYYY_MM}/SODIRD_S_ts.nc
     if [[ -f ${infile1} ]] && [[ -f ${infile2} ]] && [[ -f ${infile3} ]]
     then
       ${CDO} -s add ${infile1} -sub ${infile2} ${infile3} ${outfile}
       ${NCO_BINDIR}/ncrename -h -v SOBS_RAD,SODIRD_S ${outfile}
       ${NCO_BINDIR}/ncatted -h -a standard_name,SODIRD_S,m,c,"surface_direct_downwelling_shortwave_flux_in_air" ${outfile}
       ${NCO_BINDIR}/ncatted -h -a long_name,SODIRD_S,m,c,"surface downward direct solar radiation" ${outfile}
       ${NCO_BINDIR}/ncatted -h -a cell_methods,SODIRD_S,m,c,"time: point" ${outfile}
       # cdo removes the time_bnds units, create it again with the following command
#KK       ${NCO_BINDIR}/ncatted -h -a units,time_bnds,o,c,"$(${CFU} get_attval ${OUTDIR}/${YYYY_MM}/SOBS_RAD_ts.nc time units)" ${outfile}
     else
       echo "Input fields SOBS_RAD and/or SODIFU_S and/or SODIFD_S for calcu+lating solar direct downward flux at the surface SODIRD_S are missing"
     fi
    ;;

   'SP_10M')
      #  wind speed in 10m height
      echo calculate SP_10M ...
      uvresfile=UV_10M_ts.nc
      varname=SP_10M
      outfile=${OUTDIR}/${YYYY_MM}/${varname}_ts.nc
      infile1=${OUTDIR}/${YYYY_MM}/U_10M_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/V_10M_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} ${uvresfile}
          ${NCO_BINDIR}/ncks -h -A -v V_10M ${infile2} ${uvresfile}
          ${CDO} -s expr,${varname}'=(U_10M^2+V_10M^2)^0.5;' ${uvresfile} ${outfile}
          #... correct CDO created netCDF
          cdocor U_10M ${infile1} ${varname} ${outfile}
          ${NCO_BINDIR}/ncatted -h -O -a standard_name,${varname},o,c,'wind_speed' -a long_name,${varname},o,c,'wind speed at 10m height' -a cell_methods,${varname},o,c,'time: point' ${outfile}
          rm   ${uvresfile}
          echo "Calculated wind speed at 10m height."
        else
          echo "Input fields U_10 and/or V_10M for calculating wind speed at 10m height are missing"
        fi
      fi
      ;;

    'TOT_SNOW')
      # total snowfall
      echo calculate TOT_SNOW ...
      infile1=${OUTDIR}/${YYYY_MM}/SNOW_GSP_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/SNOW_CON_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/TOT_SNOW_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}TOT_SNOW.nc
          ${NCO_BINDIR}/ncks -h -A -v SNOW_CON ${infile2} tmp${EXPID}${YYYY}${MM}TOT_SNOW.nc
          ${NCO_BINDIR}/ncap2 -O -s "TOT_SNOW=SNOW_GSP+SNOW_CON" tmp${EXPID}${YYYY}${MM}TOT_SNOW.nc tmp${EXPID}${YYYY}${MM}TOT_SNOW.nc
          ${NCO_BINDIR}/ncks -h -O -v TOT_SNOW,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}TOT_SNOW.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,TOT_SNOW,m,c,"total snowfall" -a standard_name,TOT_SNOW,o,c,"total_snowfall_amount" ${outfile}
          rm tmp${EXPID}${YYYY}${MM}TOT_SNOW.nc
        else
          echo "Input fields " SNOW_GSP " and/or " SNOW_CON " for calculating " TOT_SNOW " are missing"
        fi
      fi
     ;;

   'TQW')
      # vertical integrated cloud condensed water
      echo calculate TQW ...
      infile1=${OUTDIR}/${YYYY_MM}/TQC_ts.nc
      infile2=${OUTDIR}/${YYYY_MM}/TQI_ts.nc
      outfile=${OUTDIR}/${YYYY_MM}/TQW_ts.nc
      if [ ! -e ${outfile} ] ; then
        if [ -f ${infile1} -a -f ${infile2} ] ; then
          cp  ${infile1} tmp${EXPID}${YYYY}${MM}TQW.nc
          ${NCO_BINDIR}/ncks -h -A -v TQI ${infile2} tmp${EXPID}${YYYY}${MM}TQW.nc
          ${NCO_BINDIR}/ncap2 -O -s "TQW=TQC+TQI" tmp${EXPID}${YYYY}${MM}TQW.nc tmp${EXPID}${YYYY}${MM}TQW.nc
          ${NCO_BINDIR}/ncks -h -O -v TQW,lat,lon,rotated_pole tmp${EXPID}${YYYY}${MM}TQW.nc ${outfile}
          ${NCO_BINDIR}/ncatted -h -a long_name,TQW,m,c,"vertical integrated cloud condensed water" -a standard_name,TQW,o,c,"atmosphere_cloud_condensed_water_content" ${outfile}
          rm tmp${EXPID}${YYYY}${MM}TQW.nc
        else
          echo "Input fields " TQC " and/or " TQI " for calculating " TQW " are missing"
        fi
      fi
     ;;

      *)
        echo ATTENTION: ${1} is not a valid choice, action skipped
      ;;

  esac

}

##################################################################################################################
# additional quantities on p-level

function timeseriesap {

  case ${1} in

   'SP')
      # wind speed on p-levels
      echo calculate SP on p-levels ...
      declare -p PLEVS=("${!2}") > /dev/null
      VARNAME=SP
      NPLEV=0
      while [[ ${NPLEV} -lt ${#PLEVS[@]} ]]
      do
        PLEV=$(${PYTHON} -c "print(int(${PLEVS[${NPLEV}]}))")
        INFILE1=${OUTDIR}/${YYYY_MM}/U${PLEV}p_ts.nc
        INFILE2=${OUTDIR}/${YYYY_MM}/V${PLEV}p_ts.nc
        OUTFILE=${OUTDIR}/${YYYY_MM}/${VARNAME}${PLEV}p_ts.nc
        UVTMPFILE=${OUTDIR}/${YYYY_MM}/tmp_SPUV${PLEV}p_ts.nc
        if [ ! -e ${OUTFILE} ] ; then
          if [ -f ${INFILE1} -a -f ${INFILE2} ] ; then
            cp  ${INFILE1} ${UVTMPFILE}
            ${NCO_BINDIR}/ncks -h -A -v V ${INFILE2} ${UVTMPFILE}
            ${CDO} -s expr,${VARNAME}'=(U^2+V^2)^0.5;' ${UVTMPFILE} ${OUTFILE}
            #... correct CDO created netCDF
            cdocor U ${INFILE1} ${VARNAME} ${OUTFILE}
            ${NCO_BINDIR}/ncatted -h -O -a standard_name,${VARNAME},o,c,'wind_speed' -a long_name,${VARNAME},o,c,'wind speed' -a cell_methods,${VARNAME},o,c,'time: point'  ${OUTFILE}
           rm ${UVTMPFILE}
         else
           echo "ERROR: Input fields U"${PLEV}" and/or V"${PLEV}" for calculating wind speed at "${PLEV}"hPa are missing"
           echo ${INFILE1}
           echo ${INFILE2}
         fi
       else
         echo $(basename ${OUTFILE}) " already exists"
       fi
       let "NPLEV = NPLEV + 1"
     done
   ;;

   'DD')
      # wind direction on p-levels
      echo calculate DD on p-levels ...
      declare -p PLEVS=("${!2}") > /dev/null
      cd ${OUTDIR}/${YYYY_MM}
      VARNAME=DD
      NPLEV=0
      while [[ ${NPLEV} -lt ${#PLEVS[@]} ]]
      do
        PLEV=$(${PYTHON} -c "print(int(${PLEVS[$NPLEV]}))")
        INFILE1=U${PLEV}p_ts.nc
        INFILE2=V${PLEV}p_ts.nc
        OUTFILE=${VARNAME}${PLEV}p_ts.nc
        UVTMPFILE=tmp_DDUV_${PLEV}p_ts.nc
        if [ ! -e ${OUTFILE} ] ; then
          if [ -f ${INFILE1} -a -f ${INFILE2} ] ; then
            cp ${INFILE1} ${UVTMPFILE}
            ${NCO_BINDIR}/ncks -h -A -v V ${INFILE2} ${UVTMPFILE}
          else
            echo "Input fields U"${PLEV}" and/or V"${PLEV}" for calculating wind direction at "${PLEV}"hPa are missing"
            let "NPLEV = NPLEV + 1"
            continue
          fi
          ${NCO_BINDIR}/ncap2 -O -s "${VARNAME}=float(45.0/atan(1.0)*atan2(U,V)+180.0)" ${UVTMPFILE} ${UVTMPFILE}
          ${NCO_BINDIR}/ncks -h -O -v ${VARNAME},lat,lon,rotated_pole,pressure ${UVTMPFILE} ${OUTFILE}
          ${NCO_BINDIR}/ncatted -h -O -a standard_name,${VARNAME},o,c,'wind_from_direction' -a long_name,${VARNAME},o,c,'wind direction' -a units,${VARNAME},o,c,'deg' -a coordinates,${VARNAME},o,c,'lon lat pressure' -a cell_methods,${VARNAME},o,c,'time: point' ${OUTFILE}
          rm ${UVTMPFILE}
          # "The wind direction at "${PLEV}"hPa was determined w.r.t. the geographical WGS84 system."
        else
          echo $(basename ${OUTFILE}) " already exists"
        fi
        let "NPLEV = NPLEV + 1"
      done
     ;;

      *)
        echo ATTENTION: ${1} is not a valid choice, action skipped
      ;;
  esac
}

##################################################################################################################
# additional quantities on z-level

function timeseriesaz {

  case ${1} in

   'SP')
     # wind speed on height levels ...
      echo calculate SP on z-levels ...
     VARNAME=$1
     declare -p ZLEVS=("${!2}") > /dev/null
     SUFFIX=$3
     set -e
     if [ y${SUFFIX} == 'yNN' ]
     then
       HEIGHT=altitude
       NN=NN
     else
       HEIGHT=height
       NN=
     fi
     NZLEV=0
     while [[ ${NZLEV} -lt ${#ZLEVS[@]} ]]
     do
       ZLEV=$(${PYTHON} -c "print(int(${ZLEVS[${NZLEV}]}))")
       INFILE1=${OUTDIR}/${YYYY_MM}/U${ZLEV}z${NN}_ts.nc
       INFILE2=${OUTDIR}/${YYYY_MM}/V${ZLEV}z${NN}_ts.nc
       OUTFILE=${OUTDIR}/${YYYY_MM}/${VARNAME}${ZLEV}z${NN}_ts.nc
       UVTMPFILE=${OUTDIR}/${YYYY_MM}/tmp_SPUV${ZLEV}z${NN}.nc
       if [ ! -e ${OUTFILE} ] ; then
         if [ -f ${INFILE1} -a -f ${INFILE2} ] ; then
           cp  ${INFILE1} ${UVTMPFILE}
           ${NCO_BINDIR}/ncks -h -A -v V ${INFILE2} ${UVTMPFILE}
           ${CDO} -s expr,${VARNAME}'=(U^2+V^2)^0.5;' ${UVTMPFILE} ${OUTFILE}
           #... correct CDO created netCDF
           cdocor U ${INFILE1} ${VARNAME} ${OUTFILE}
           ${NCO_BINDIR}/ncatted -h -O -a standard_name,${VARNAME},o,c,'wind_speed' -a long_name,${VARNAME},o,c,'wind speed' -a cell_methods,${VARNAME},o,c,'time: point'  ${OUTFILE}
           rm ${UVTMPFILE}
         else
           echo "ERROR: Input fields U"${ZLEV}" and/or V"${ZLEV}" for calculating wind speed at "${ZLEV}"m "${HEIGHT}" are missing"
           echo ${INFILE1}
           echo ${INFILE2}
         fi
       fi
       let "NZLEV = NZLEV + 1"
     done
    ;;

   'DD')
      # wind direction on z-levels ...
      echo calculate DD on z-levels
      VARNAME=$1
      cd ${OUTDIR}/${YYYY_MM}
      declare -p ZLEVS=("${!2}") > /dev/null
      SUFFIX=$3
      if [ y${SUFFIX} == 'yNN' ]
      then
        HEIGHT=altitude
        NN=NN
      else
        HEIGHT=height
        NN=
      fi
      NZLEV=0
      while [[ ${NZLEV} -lt ${#ZLEVS[@]} ]]
      do
        ZLEV=$(${PYTHON} -c "print(int(${ZLEVS[$NZLEV]}))")
        INFILE1=${OUTDIR}/${YYYY_MM}/U${ZLEV}z${NN}_ts.nc
        INFILE2=${OUTDIR}/${YYYY_MM}/V${ZLEV}z${NN}_ts.nc
        OUTFILE=${OUTDIR}/${YYYY_MM}/${VARNAME}${ZLEV}z${NN}_ts.nc
        UVTMPFILE=${OUTDIR}/${YYYY_MM}/tmp_DDUV${ZLEV}z${NN}.nc
        if [ ! -e ${OUTFILE} ] ; then
          if [ -f ${INFILE1} -a -f ${INFILE2} ] ; then
            cp ${INFILE1} ${UVTMPFILE}
            ${NCO_BINDIR}/ncks -h -A -v V ${INFILE2} ${UVTMPFILE}
            ${NCO_BINDIR}/ncap2 -O -s "${VARNAME}=float(45.0/atan(1.0)*atan2(U,V)+180.0)" ${UVTMPFILE} ${UVTMPFILE}
            ${NCO_BINDIR}/ncks -h -O -v ${VARNAME},lat,lon,rotated_pole,${HEIGHT} ${UVTMPFILE} ${OUTFILE}
            ${NCO_BINDIR}/ncatted -h -O -a standard_name,${VARNAME},o,c,'wind_from_direction' -a long_name,${VARNAME},o,c,'wind direction' -a units,${VARNAME},o,c,'deg'  -a cell_methods,${VARNAME},o,c,'time: point' ${OUTFILE}
 #           ${NCO_BINDIR}/ncatted -h -O -a standard_name,${VARNAME},o,c,'wind_from_direction' -a long_name,${VARNAME},o,c,'wind direction' -a units,${VARNAME},o,c,'deg' -a coordinates,${VARNAME},o,c,'lon lat height' -a cell_methods,${VARNAME},o,c,'time: point' ${OUTFILE}
          rm ${UVTMPFILE}
          # "The wind direction at "${PLEV}"hPa was determined w.r.t. the geographical WGS84 system."
          else
            echo "ERROR: Input fields U"${ZLEV}" and/or V"${ZLEV}" for calculating wind direction at "${ZLEV}"m "${HEIGHT}" are missing"
            echo ${INFILE1}
            echo ${INFILE2}
          fi
        fi
        let "NZLEV = NZLEV + 1"
      done
     ;;

      *)
        echo ATTENTION: ${1} is not a valid choice, action skipped
      ;;
  esac
}

