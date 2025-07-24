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

ulimit -s unlimited

export OMP_NUM_THREADS=1
export ICON_THREADS=1
export OMP_SCHEDULE=static,1
export OMP_DYNAMIC="false"
export OMP_STACKSIZE=200M

JOBID=${SLURM_JOBID}

#################################################
#  Pre-Settings
#################################################

#... get the job_settings environment variables
source ${PFDIR}/${EXPID}/job_settings

if [ -a ${ICONDIR}/nvhpc_gpu/setting ]
then
  echo "Load Setting"
  . ${ICONDIR}/nvhpc_gpu/setting
fi

export NVCOMPILER_ACC_SYNCHRONOUS=1
export FI_CXI_SAFE_DEVMEM_COPY_THRESHOLD=0
export FI_CXI_RX_MATCH_MODE=software
export FI_MR_CACHE_MONITOR=disabled
export MPICH_GPU_SUPPORT_ENABLED=1
export NVCOMPILER_ACC_DEFER_UPLOADS=1
export NVCOMPILER_TERM=trace
export CUDA_BUFFER_PAGE_IN_THRESHOLD_MS=0.001

if [ -z ${BINARY_ICON} ]
then
  echo ERROR: Environment variable BINARY_ICON not set in job_settings
  exit
fi

INPDIR=${SCRATCHDIR}/${EXPID}/input/icon
OUTDIR=${SCRATCHDIR}/${EXPID}/output/icon

NEXT_MONTH_DATE=$(${CFU} get_next_dates $(echo ${CURRENT_DATE} | cut -c1-6)0100 01:00:00 ${ITYPE_CALENDAR} | cut -c1-10)

NEXT_DATE=$(${CFU} get_next_dates ${CURRENT_DATE} ${INC_DATE} ${ITYPE_CALENDAR} | cut -c1-10)

if [ ${NEXT_DATE} -ge ${NEXT_MONTH_DATE} ]
then
  NEXT_DATE=${NEXT_MONTH_DATE}
fi

YYYY=${CURRENT_DATE:0:4}
MM=${CURRENT_DATE:4:2}
YYYY_MM=${YYYY}_${MM}
HINC_RESTART=$(${CFU} get_hours ${CURRENT_DATE} ${NEXT_DATE} ${ITYPE_CALENDAR})
echo CURRENT_DATE $CURRENT_DATE
echo NEXT_DATE $NEXT_DATE
echo HINC_RESTART $HINC_RESTART

echo "icon      ${YYYY}_${MM} START    $(date)" >> ${PFDIR}/${EXPID}/chain_status.log
DATE_START=$(date +%s)

# check if all boundary data are provided by conv2icon
if [ $(${CFU} check_files ${CURRENT_DATE} ${NEXT_DATE} $(printf %02d ${HINCBOUND}):00:00 ${GCM_PREFIX} ${GCM_PREFIX} _lbc.nc ${INPDIR}/${YYYY_MM} T ${ITYPE_CALENDAR}) -eq 1 ]
then
    cat <<EOF_MESS > ${PFDIR}/${EXPID}/error_message
Error in ICON
Date ${YYYY} / ${MM}
Not all ICON input files found
Maybe the ICON job was faster than the in parallel running CONV2ICON job
If the latter is the case the CONV2ICON will rerun the ICON automatically
EOF_MESS

  mv check_files.log ${WORKDIR}/${EXPID}/joblogs/icon/icon_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log
  echo check ${WORKDIR}/${EXPID}/joblogs/icon/arch_${EXPID}_${YYYY_MM}_check_files_${JOBID}.log >> ${PFDIR}/${EXPID}/error_message

  if [ -n "${NOTIFICATION_ADDRESS}" ]
  then
    ${NOTIFICATION_SCRIPT} ${NOTIFICATION_ADDRESS}  "SUBCHAIN ${EXPID} abort due to errors" ${PFDIR}/${EXPID}/error_message
  fi
  DATE_END=$(date +%s)
  SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
  echo "icon      ${YYYY}_${MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
    exit 1
fi

#... Create run directory:
if [ ! -d ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM} ]
then
  mkdir -p ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}
else
  if [ ${CURRENT_DATE:6:4} -eq 0100 ]
  then
    rm -rf ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/*
  else
    # in case of sub-monthly chunks delete only files
    find ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}  -maxdepth 1 -type f -exec rm -f {} \;
  fi
fi

#... Create output directory:
if [ ! -d ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_MM} ]
then
  mkdir -p ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_MM}
  NOUTDIR=1
  while [ ${NOUTDIR} -le ${#HOUT_INC[@]} ]
  do
    mkdir -p ${SCRATCHDIR}/${EXPID}/output/icon/${YYYY_MM}/out$(printf %02d ${NOUTDIR})
    ((NOUTDIR++))
  done
fi

#################################################
#  Main Part
#################################################
if [ $(echo ${NEXT_DATE} | cut -c7-10) -eq 0100 ]
then
  echo START ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/icon/finish_joblist
else
  echo START ${YYYY} ${MM} $(cat ${PFDIR}/${EXPID}/date.log | cut -c7-8) >> ${WORKDIR}/${EXPID}/joblogs/icon/finish_joblist
fi
#... Convert output intervals in the form hh:mm:ss into seconds:
for i in $(seq 0 $((${#HOUT_INC[@]}-1)));
do
  echo  SOUT_INC[$(($i+1))]=$(${PYTHON} -c "print(int('${HOUT_INC[$i]:0:2}')*3600 + int('${HOUT_INC[$i]:3:2}')*60 + int('${HOUT_INC[$i]:6:2}'))")
  SOUT_INC[$(($i+1))]=$(${PYTHON} -c "print(int('${HOUT_INC[$i]:0:2}')*3600 + int('${HOUT_INC[$i]:3:2}')*60 + int('${HOUT_INC[$i]:6:2}'))")
done

HSTART=$(${CFU} get_hours ${YDATE_START} ${CURRENT_DATE} ${ITYPE_CALENDAR})
HNEXT=$(${CFU} get_hours ${YDATE_START} ${NEXT_DATE} ${ITYPE_CALENDAR})
SSTART=$(${PYTHON} -c "print(int(int('${HSTART}')*3600))")
SNEXT=$(${PYTHON} -c "print(int(int('${HNEXT}')*3600))")

# ----------------------------------------------------------------------
# global namelist settings
# ----------------------------------------------------------------------
# the grid parameters
atmo_dyn_grids="${LAM_GRID##*/}"  # get filename without path
atmo_rad_grids="${PARENT_GRID##*/}"
EXTPAR_FILENAME="${EXTPAR##*/}"

# ----------------------------------------------------------------------
# link files needed for icon to the directory from which icon will be started
# ----------------------------------------------------------------------
cd ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}

if [[ ${ECRADDIR} == "" ]];then
  ecrad_data_path=
else
  ecrad_data_path=$(basename ${ECRADDIR})
fi

INI_FILES="$PARENT_GRID"
INI_FILES="$INI_FILES $LAM_GRID"
INI_FILES="$INI_FILES $EXTPAR"
INI_FILES="$INI_FILES ${INI_BASEDIR}/dict.latbc"
INI_FILES="$INI_FILES ${ECRADDIR}"

# initial data file
if [ ${CURRENT_DATE} -eq ${YDATE_START} ]
then
  # at cold start taken from coarse model data interpolation
  LRESTART=.FALSE.
  CHECK_UUID_GRACEFULLY=.FALSE.
  inidatafile=${INIDIR}/${GCM_PREFIX}${YDATE_START}_ini.nc
  fg_file=${INI_BASEDIR}/europe011/FG_IAEVAL00_1950010100.nc
  INI_FILES="$INI_FILES ${inidatafile} ${fg_file}"
  if [ ${NUM_RESTART_PROCS} -eq 0 ];then
    RESTART_WRITE_MODE="sync"
  else
    RESTART_WRITE_MODE="dedicated procs multifile"
  fi
else
  # at warm start taken from restart file
  LRESTART=.TRUE.
  CHECK_UUID_GRACEFULLY=.TRUE.
  RES_DATE=${CURRENT_DATE:0:8}T${CURRENT_DATE:8:2}
  if [ ${NUM_RESTART_PROCS} -eq 0 ];then
# num_restart_procs=0
   RESTART_WRITE_MODE="sync"
   resdatafile=($(ls ${RESDIR}/*restart*${RES_DATE}*.nc))
   if [ -e ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/restart_ATMO_DOM01.nc ];then
    unlink ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/restart_ATMO_DOM01.nc
   fi
   ln -sf ${resdatafile} ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/restart_ATMO_DOM01.nc
  else
# num_restart_procs>0
   RESTART_WRITE_MODE="dedicated procs multifile"
   resdatafile=${RESDIR}/*restart_ATMO_*${RES_DATE}*.mfr
   if [ -e ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/multifile_restart_ATMO.mfr ];then
    unlink ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/multifile_restart_ATMO.mfr
   fi
   ln -sf ${resdatafile} ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/multifile_restart_ATMO.mfr
  fi

  #... Link first lbc data (necessary for all icon jobs in the entire experiment):
  FIRST_YYYY=${YDATE_START:0:4}
  FIRST_MM=${YDATE_START:4:2}
  if [ ${CURRENT_DATE:6:2} -eq 01 ]
  then
    ln -sf ${INIDIR}/${GCM_PREFIX}${YDATE_START}_lbc.nc ${INPDIR}/${YYYY_MM}
  fi
fi

for IFILE in ${INI_FILES}
do
  ln -sf ${IFILE} $(basename ${IFILE}) && echo "$IFILE was linked ..."
done

# Link aerosol data:
let PREV_YYYY=${YYYY}-1
let NEXT_YYYY=${YYYY}+1
# Kinne aersols
ln -sf ${KINNE_DIR}/EURO_R13B05_aeropt_kinne_sw_b14_coa.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_kinne_sw_b14_coa.nc
ln -sf ${KINNE_DIR}/EURO_R13B05_aeropt_kinne_lw_b16_coa.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_kinne_lw_b16_coa.nc
# Kinne natural aerosols only
ln -sf ${KINNE_DIR}/EURO_R13B05_aeropt_kinne_sw_b14_fin_1850.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_kinne_sw_b14_fin.nc
ln -sf ${KINNE_DIR}/EURO_R13B05_aeropt_kinne_sw_b14_fin_1850.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_kinne_sw_b14_fin_${PREV_YYYY}.nc
ln -sf ${KINNE_DIR}/EURO_R13B05_aeropt_kinne_sw_b14_fin_1850.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_kinne_sw_b14_fin_${NEXT_YYYY}.nc
# volcanic aerosols
ln -sf ${VOLC_DIR}/bc_aeropt_cmip6_volc_lw_b16_sw_b14_${YYYY}.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_cmip6_volc_lw_b16_sw_b14_${YYYY}.nc
ln -sf ${VOLC_DIR}/bc_aeropt_cmip6_volc_lw_b16_sw_b14_${PREV_YYYY}.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_cmip6_volc_lw_b16_sw_b14_${PREV_YYYY}.nc
ln -sf ${VOLC_DIR}/bc_aeropt_cmip6_volc_lw_b16_sw_b14_${NEXT_YYYY}.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_aeropt_cmip6_volc_lw_b16_sw_b14_${NEXT_YYYY}.nc
# MACv2 simple plumes
ln -sf ${SP_DIR}/MACv2.0-SP-merged-historical-and-SSP2-45_v1.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/MACv2.0-SP_v1.nc

#Link ozone data:
ln -sf $OZONE_DIR/bc_ozone_historical_${PREV_YYYY}.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_ozone_${PREV_YYYY}.nc
ln -sf $OZONE_DIR/bc_ozone_historical_${NEXT_YYYY}.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_ozone_${NEXT_YYYY}.nc
ln -sf $OZONE_DIR/bc_ozone_historical_${YYYY}.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_ozone_${YYYY}.nc

#Link solar irradiance data
ln -sf ${SOLAR_DIR}/swflux_14band_cmip6_1850-2299-v3.2.nc ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/bc_solar_irradiance_sw_b14.nc

# set some namelist switches for climate projections (counting from 2021 onwards)
if [ ${YYYY} -ge 2021 ] ; then
  lscale_cdnc=.true.
  irad_aero=19
else
  lscale_cdnc=.false.
  irad_aero=18
fi

# ------------------------------------------------------------------------------
# End of link part.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Checkings:
# ------------------------------------------------------------------------------

if [ ${NUM_RESTART_PROCS} -gt 0 ]
then
  echo WARNING: NUM_RESTART_PROCS must be 0 or 1. Your setting is ${NUM_RESTART_PROCS}. Value reset to 1.
  NUM_RESTART_PROCS=1
fi

# ------------------------------------------------------------------------------
# Automatic time settings:
# ------------------------------------------------------------------------------

#... if DTIME is not set in job_settings, calculate it from the equations in the ICON tutorial
#... the following settings should only be changed for good reasons!
BASE_OUTPUT_INTERVAL=3600  # smallest value of the increment in output_bounds of the output_nml namelists
NDYN_SUBSTEPS=5    # number of short time steps per basic timestep dtime. Default: 5. Should not exceed the default
NT_CONV=3   # time step factor for convective and cloud cover. Integer number, setting the multiple of dtime
NT_RAD=3   # time step factor for radiation. Integer number, setting the multiple of dt_conv
NT_SSO=6   # time step factor for orographic gravity wave drag (SSO). Integer number, setting the multiple of dtime
NT_GWD=6   # time step factor for non-orographic gravity wave drag. Integer number, setting the multiple of dtime
if [ -z ${DTIME} ]
then
  Rn=$($CFU get_attval ${LAM_GRID} global grid_root)
  Bk=$($CFU get_attval ${LAM_GRID} global grid_level)
#  DTIME=$(${PYTHON} -c "dt=int(45450.0/(${Rn}.*2.**${Bk}.))
# dtime_max = 1.8 * ndyn_substeps * 5050.0 / (n * 2**k)
DTIME=$(${PYTHON} -c "print(int(int('${NDYN_SUBSTEPS}')*9090.0/(${Rn}.*2.**${Bk}.)))")
fi

#... DTIME modified such that it fits into ${BASE_OUTPUT_INTERVAL}. Therefore the following calculations are only valid
#...     if the increment in output_bounds is a multiple of ${BASE_OUTPUT_INTERVAL}.
  DTIME=$(${PYTHON} -c "dt=${DTIME}
while (${BASE_OUTPUT_INTERVAL}%dt > 0) :
  dt=dt-1

print(dt)")

# convective and cloud cover time step
DT_CONV=$(${PYTHON} -c "print(${DTIME}*${NT_CONV})")
DT_RAD=$(${PYTHON} -c "print(${DT_CONV}*${NT_RAD})")
DT_SSO=$(${PYTHON} -c "print(${DTIME}*${NT_SSO})")
DT_GWD=$(${PYTHON} -c "print(${DTIME}*${NT_GWD})")

echo
echo "Calculated a default DTIME: ${DTIME} sec"
echo "DT_CONV = ${DT_CONV}"
echo "DT_RAD  = ${DT_RAD}"
echo "DT_SSO  = ${DT_SSO}"
echo "DT_GWD  = ${DT_GWD}"
echo

echo "NDYN_SUBSTEPS=${NDYN_SUBSTEPS}" > ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/dt_settings
echo "DTIME=${DTIME}" >> ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/dt_settings
echo "DT_CONV=${DT_CONV}" >> ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/dt_settings
echo "DT_RAD=${DT_RAD}" >> ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/dt_settings
echo "DT_SSO=${DT_SSO}" >> ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/dt_settings
echo "DT_GWD=${DT_GWD}" >> ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/dt_settings

# ------------------------------------------------------------------------------
# end of automatic time settings part
# ------------------------------------------------------------------------------

NOUTDIR=0  # counter for output directories

# ------------------------------------------------------------------------------
# create ICON master namelist
# ------------------------------------------------------------------------------

# For a complete list see Namelist_overview and Namelist_overview.pdf
cat > icon_master.namelist << EOF
&master_nml
  lrestart             = ${LRESTART}
  lrestart_write_last  = .TRUE.
/
&time_nml
  ini_datetime_string  = "${YDATE_START_ISO}"
  dt_restart           = $(${PYTHON} -c "print(${HINC_RESTART}*3600.)")
  is_relative_time     = .TRUE.
/
&master_model_nml
  model_type              = 1
  model_name              = "ATMO"
  model_namelist_filename = "NAMELIST_${EXPID}"
  model_min_rank          = 1
  model_max_rank          = 65536
  model_inc_rank          = 1
/
&master_time_control_nml
  calendar             = "${CALENDAR}"
  experimentStartDate  = "${YDATE_START_ISO}"
  experimentStopDate   = "${YDATE_STOP_ISO}"
/
EOF
# ----------------------------------------------------------------------
# model namelists
# ----------------------------------------------------------------------
# reconstruct the grid parameters in namelist form
dynamics_grid_filename=""
for gridfile in ${atmo_dyn_grids}; do
  dynamics_grid_filename="${dynamics_grid_filename} '${gridfile}',"
done

radiation_grid_filename=""
for gridfile in ${atmo_rad_grids}; do
  radiation_grid_filename="${radiation_grid_filename} '${gridfile}',"
done

cat > NAMELIST_${EXPID} << EOF
&parallel_nml
  nproma            = 0
  nproma_sub        = 20000
  nblocks_c         = 0
  nblocks_e         = 1
  p_test_run        = .false.
  l_test_openmp     = .false.
  l_log_checks      = .true.
  num_io_procs      = ${NUM_IO_PROCS}
  num_restart_procs = ${NUM_RESTART_PROCS}
  num_prefetch_proc = ${NUM_PREFETCH_PROC}
  iorder_sendrecv   = 3
  proc0_shift       = 0
  use_omp_input   = .true.
/
&grid_nml
  dynamics_grid_filename  = ${dynamics_grid_filename}
  radiation_grid_filename = ${radiation_grid_filename}
  dynamics_parent_grid_id = 0
  lredgrid_phys           = .true.
  lfeedback               = .true.
  l_limited_area          = .true.
  ifeedback_type          = 2
  start_time  = 0., 1800.,3600.,
/
&initicon_nml
  init_mode                    = 3
  lread_ana                    = .false. ! (T) Read dwdana
  ifs2icon_filename            = "${inidatafile##*/}"
  dwdfg_filename               = "${fg_file}"
  zpbl1       = 500.
  zpbl2       = 1000.
  ltile_init=.TRUE.
  ltile_coldstart=.true.
/
&limarea_nml
  itype_latbc     = 1
  dtime_latbc     = $(${PYTHON} -c "print(${HINCBOUND}*3600.)")
  latbc_varnames_map_file = 'dict.latbc'
  latbc_path      = '${INPDIR}/${YYYY_MM}'
  latbc_filename  = '${GCM_PREFIX}<y><m><d><h>_lbc.nc'
! latbc_contains_qcqi = .false.     ! = .true.  if  qc, qi are in latbc
  latbc_contains_qcqi = .true.      ! = .true.  if  qc, qi are in latbc
                                    ! = .false. if qc, qi are not in latbc
/
&io_nml
  itype_pres_msl               = 5
  itype_rh                     = 1
  precip_interval              = "${PRECIP_INTERVAL}"
  runoff_interval              = "${RUNOFF_INTERVAL}"
  sunshine_interval            = "${SUNSHINE_INTERVAL}"
  maxt_interval                = "${MAXT_INTERVAL}"
  gust_interval                = $(${CFU} p2sec ${GUST_INTERVAL})
  melt_interval                = "${MELT_INTERVAL}"
  lmask_boundary               = .true.
  restart_write_mode="${RESTART_WRITE_MODE}"
/
&output_nml
!-----------------------------------------------------------Output Namelist 1: 3hrs
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
 ! ml_varlist                  = 'group:mode_iniana' ! this causes problems with operation="mean" in other output streams
  ml_varlist                   = 'alb_si','c_t_lk','fr_land','fr_seaice','freshsnow','gz0','h_ice','h_ml_lk','h_snow','pres','qc','qi','qr','qs','qv',
                                  'qv_s','rho_snow','smi','t_bot_lk','t_g','t_ice','t_mnw_lk','t_snow','t_so','t_wml_lk','temp','tke','u','v','w','w_i',
                                  'w_snow','w_so_ice','z_ifc','plantevap','hsnow_max','snow_age'                         !'group:mode_iniana'
  output_grid                  =  .TRUE.
!  stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 2: 1hr + mean
 filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
 dom                          =  1            ! write all domains
 output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
 steps_per_file               =  1
 mode                         =  1            ! 1: forecast mode (relative t-axis)
                                              ! 2: climate mode (absolute t-axis)
 include_last                 = .TRUE.
 steps_per_file_inclfirst     = .FALSE.
 output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
 filename_format              = '<output_filename>_<datetime2>'
 operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
 ml_varlist                   = 'sob_s','sou_s','thb_s','thu_s','sodifd_s' 'lhfl_s','shfl_s','qhfl_s','clct_mod','clct','thb_t','sob_t','sod_t','t_2m','rh_2m','umfl_s','vmfl_s','sp_10m' ! sp_10m is needed  1hrly for pot. evap
 output_grid                  =  .TRUE.
! stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 3: 6hrs + mean
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'gz0','clch','clcm','clcl','swflx_dn_clr','swflx_up_clr','lwflx_dn_clr','lwflx_up_clr','sp_10m'!,'tch','tkvh'
  m_levels                     = '1,60'
  output_grid                  =  .TRUE.
!  stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 4: 1hr - added ,'tqv','tqc','tqi' from output06 for CORDEX
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'cape_ml','cin_ml','hpbl','t_2m','t_g','tot_prec','rain_con','rain_gsp','snow_con','snow_gsp','qv_2m','rh_2m','pres_msl','pres_sfc','sli','sp_10m','tqv','tqc','tqi','u_10m',
                                     'v_10m','w_i','w_so','w_so_ice'
  output_grid                  =  .TRUE.
!  stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 5: 1hr+10min
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  600., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.      ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'sob_s','sou_s','sodifd_s'
  output_grid                  =  .TRUE.
!  stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 6: 6hrs
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
       ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'runoff_s','runoff_s_t_8','runoff_g','resid_wso','w_snow','h_snow','snowfrac','snow_melt'
  output_grid                  =  .TRUE.
! stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 7: daily values
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.   ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
      operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'tmin_2m','tmax_2m','dursun','gust10'
  output_grid                  =  .TRUE.
! stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 8: 24hrs + max
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'sli','sp_10m','lai','plcov','cape_ml','cin_ml','gz0'
  output_grid                  =  .TRUE.
/
&output_nml
!-----------------------------------------------------------Output Namelist 9: 1hr + mlevel
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'u','v','w','temp','qv' ! t and qv added for interpolation to zlevel above groud (CORDEX: 50m needed)
  m_levels                     = '${LEVELS}'
  output_grid                  =  .TRUE.
!  stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 10: 1hrs + plevel - UDAG
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>p'
      operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  pl_varlist                   = 'geopot','rh','temp','u','v','w','qv'
  p_levels                     =  92500              !30000,50000,70000,85000,92500
  output_grid                  =  .TRUE.
!  stream_partitions_ml         =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 11: 6hrs + plevel - CORDEX
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>p'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  pl_varlist                   = 'geopot','temp','u','v','w','qv'
  p_levels                     =  20000,25000,30000,40000,50000,60000,70000,75000,85000,100000 !20000,25000,40000,60000,75000,100000
  output_grid                  =  .TRUE.
!  stream_partitions_ml   =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 12: 6hrs
! Diesen Block ueberdenken: 3hr Ausgabe zu hoch, W_SO, W_SO_ICE in out04 (1hr)
! W_SNOW, H_SNOW, in out06 (6hr)cin
!KK: Ab 1960 ml_varlist umstellen und t_sk, t_so, t_snow, t_ice, fr_seaice zusaetzlich in Zeitreihen umgewandeln
!KK Andere größen können aus Ausgabe herausgenommen werden:
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'h_ice','t_ice','t_snow','t_so','t_sk',
                                 'qv_s','alb_si','plantevap','smi'
  output_grid                  =  .TRUE.
!  stream_partitions_ml   =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 13 daily mean
  filetype                     =  4            ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1            ! write all domains
  output_bounds                =  ${SSTART}., ${SNEXT}., ${SOUT_INC[$((NOUTDIR+=1))]}.    ! start, end, increment
  steps_per_file               =  1
  mode                         =  1            ! 1: forecast mode (relative t-axis)
                                               ! 2: climate mode (absolute t-axis)
  include_last                 = .TRUE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/${YYYY_MM}/out$(printf %02d $NOUTDIR)/icon'
  filename_format              = '<output_filename>_<datetime2>'
  operation                    = "${OPERATION[$((${NOUTDIR}-1))]}"
  ml_varlist                   = 'aod_550nm','gz0','fr_seaice'
  output_grid                  =  .TRUE.
!  stream_partitions_ml   =  2
/
&output_nml
!-----------------------------------------------------------Output Namelist 14: c-file
  filetype                     =  4              ! output format: 2=GRIB2, 4=NETCDFv2
  dom                          =  1              ! write all domains
  output_bounds                =  120., 120., 3600.  ! start, end, increment
  steps_per_file               =  1
  mode                         =  1              ! 1: forecast mode (relative t-axis)
       ! 2: climate mode (absolute t-axis)
  include_last                 = .FALSE.
  steps_per_file_inclfirst     = .FALSE.
  output_filename              = '${OUTDIR}/icon'
  filename_format              = '<output_filename>_c'   ! file name base
  ml_varlist                   = 'z_ifc','z_mc','topography_c','fr_land','depth_lk','fr_lake','soiltyp','rootdp','fr_glac' !'fr_urb','fr_glac',fr_glac might cause problem
  output_grid                  =  .TRUE.
!  stream_partitions_ml   =  2
/
!&meteogram_output_nml
!  lmeteogram_enabled = .TRUE.
!  ldistributed       = .FALSE.
!  loutput_tiles      = .TRUE.
!  n0_mtgrm           = 0
!  ninc_mtgrm         = 1
!  stationlist_tot = 50.050,  8.600, 'Frankfurt-Flughafen',
!                    52.220, 14.135, 'Lindenberg_Obs',
!                    52.167, 14.124, 'Falkenberg',
!                    47.800, 10.900, 'Hohenpeissenberg',
!                    53.630,  9.991, 'Hamburg-Flughafen',
!                    54.533,  9.550, 'Schleswig',
!  max_time_stamps    = 500
!  zprefix            = 'Meteogram_'
!  var_list           = '  '
!/
&run_nml
  num_lev        = 60
  lvert_nest     = .false.
  dtime          = ${DTIME}     ! timestep in seconds
  ldynamics      = .TRUE.
  ltransport     = .true.
  ntracer        = 5
  iforcing       = 3
  ltestcase      = .false.
! msg_level      = 13
  msg_level      = 0
  ltimer         = .true.
  timers_level   = 10
  check_uuid_gracefully = ${CHECK_UUID_GRACEFULLY}
  output         = "nml" ! "nml"
! debug_check_level = 10
  debug_check_level = 0
  lart           = .false.
/
&nwp_phy_nml
  inwp_gscp       = 1
  mu_rain         = 0.5
  rain_n0_factor  = 0.1
  inwp_convection = 1
  inwp_radiation  = 4
  inwp_cldcover   = 1
  inwp_turb       = 1
  inwp_satad      = 1
  inwp_sso        = 1
  inwp_gwd        = 1
  inwp_surface    = 1
  latm_above_top  = .true.
  ldetrain_conv_prec = .true.
  efdt_min_raylfric = 7200.
  itype_z0         = 2
  icapdcycl        = 3
  icpl_aero_conv   = 0
  icpl_aero_gscp   = 0
  lscale_cdnc      = .false.
  icpl_o3_tp       = 1
  iprog_aero       = 0
  dt_rad    = ${DT_RAD}
  dt_conv   = ${DT_CONV}
  dt_sso    = ${DT_SSO}
  dt_gwd    = ${DT_GWD}
/
&nwp_tuning_nml
  tune_albedo_wso = 0.047,-0.102
  tune_gkwake   = 0.65
  tune_gfrcrit  = 0.35
  tune_gkdrag   = 0.08
  tune_dust_abs = 1.
  tune_zvz0i    = 0.85
  allow_overcast=${allow_overcast_yc[$(echo $MM -1 | bc )]}
  tune_box_liq_asy = 3.17
  tune_box_liq = 0.066
  tune_minsnowfrac = 0.2
  tune_gfluxlaun  = 3.75e-3
  tune_rcucov = 0.075
  tune_rhebc_land = 0.825
  tune_gust_factor=7.0
  lcalib_clcov =.FALSE.
  itune_gust_diag = 2
  tune_grcrit = 0.5
  tune_minsso = 1.0
  tune_blockred = 1.5
/
&turbdiff_nml
  tkhmin  = 0.6
  tkhmin_strat = 1.0
  tkmmin        = 0.75
  pat_len       = 750.
  c_diff  =  0.2
  rlam_heat = 9.66
  rat_sea =  1.06
  rat_lam =  1.03
  ltkesso = .true.
  frcsmot       = 0.2
  imode_frcsmot = 2
  alpha1  = 0.125
  icldm_turb = 1
  itype_sher = 1
  ltkeshs       = .true.
  a_hshr        = 2.0
/
&lnd_nml
  sstice_mode    = 6   ! 4: SST and sea ice fraction are updated daily,
                       !    based on actual monthly means
  ci_td_filename = '${INPDIR}/${YYYY_MM}/LOWBC_${YYYY}_${MM}.nc'
  sst_td_filename= '${INPDIR}/${YYYY_MM}/LOWBC_${YYYY}_${MM}.nc'
  ntiles         = 3
  nlev_snow      = 1
  zml_soil       = ${ZML_SOIL}
  lmulti_snow    = .false.
  itype_heatcond = 3
  idiag_snowfrac = 20
  itype_snowevap = 3
  lsnowtile      = .true.
  lseaice        = .true.
  llake          = .true.
  itype_lndtbl   = 4
  itype_evsl     = 4
  itype_trvg     = 3
  itype_root     = 2
  itype_canopy   = 2
  cwimax_ml      = 5.e-4
  c_soil         = 1.25
  c_soil_urb     = 0.5
  czbot_w_so	 = 4.5
  lprog_albsi    = .true.
  lterra_urb     = .true.
  rsmin_fac      = 1.34
/
&radiation_nml
  ecrad_data_path= '${ecrad_data_path}'
  ecrad_isolver = 2
  ghg_filename =  '${GHG_FILENAME}'
  irad_co2    = 4           ! 4: from greenhouse gas scenario
  irad_ch4    = 4           ! 4: from greenhouse gas scenario
  irad_n2o    = 4           ! 4: from greenhouse gas scenario
  irad_cfc11  = 4           ! 4: from greenhouse gas scenario
  irad_cfc12  = 4           ! 4: from greenhouse gas scenario
  irad_o3     = 5
  isolrad     = 2
  irad_aero   = 18
  albedo_type = 2          ! Modis albedo
  direct_albedo = 4
  albedo_whitecap = 1
  direct_albedo_water = 3
/
&nonhydrostatic_nml
  itime_scheme    = 4
  vwind_offctr    = 0.2
  damp_height     = 10500.
  rayleigh_coeff  = 1.0
  divdamp_order   = 24
  divdamp_fac     = 0.004
  divdamp_type    = 32
  igradp_method   = 3
  l_zdiffu_t      = .true.
  thslp_zdiffu    = 0.02
  thhgtd_zdiffu   = 125.
  htop_moist_proc = 22500.
  hbot_qvsubstep  = 16000.
  ndyn_substeps=${NDYN_SUBSTEPS}
/
&sleve_nml
  min_lay_thckn   = 20.
  max_lay_thckn   = 400.
  htop_thcknlimit = 15000.
  top_height      = 23500.
  stretch_fac     = 0.9
  decay_scale_1   = 4000.
  decay_scale_2   = 2500.
  decay_exp       = 1.2
  flat_height     = 16000.
/
&dynamics_nml
  iequations     = 3
  divavg_cntrwgt = 0.50
  lcoriolis      = .true.
/
&transport_nml
  ivadv_tracer   = 3,3,3,3,3
  itype_hlimit   = 3,4,4,4,4,
  ihadv_tracer   = 52,2,2,2,2,
  llsq_svd       = .false.
  beta_fct       = 1.005
/
&diffusion_nml
  hdiff_order      = 5
  itype_vn_diffu   = 1
  itype_t_diffu    = 2
  hdiff_efdt_ratio = 32.
  hdiff_smag_fac   = 0.025
  lhdiff_vn        = .true.
  lhdiff_temp      = .true.
/
&interpol_nml
  nudge_zone_width  = 10
  nudge_max_coeff   = 0.075
  lsq_high_ord      = 3
  l_intp_c2l        = .true.
  l_mono_c2l        = .true.
  rbf_scale_mode_ll = 2
/
&gridref_nml
  grf_intmethod_e  = 6
  grf_scalfbk      = 2
  denom_diffu_v    = 150.
/
&extpar_nml
  itopo                = 1
  n_iter_smooth_topo   = 1,
  hgtdiff_max_smooth_topo = 750.
  heightdiff_threshold = 3000.
  itype_vegetation_cycle = 3
  itype_lwemiss = 2
  extpar_filename = "${EXTPAR_FILENAME}"
  pp_sso=2
/
&nudging_nml
  nudge_type = 1
  max_nudge_coeff_thermdyn = 0.075
  max_nudge_coeff_vn = 0.04
  nudge_start_height=10500
/
EOF

# ----------------------------------------------------------------------------
# run ICON
# ----------------------------------------------------------------------------
echo "----- start ICON"
echo

no_of_nodes=${NODES_ICON}
mpi_procs_pernode=4
((mpi_total_procs=no_of_nodes * mpi_procs_pernode))
srun \
    -n $mpi_total_procs \
    --ntasks-per-node $mpi_procs_pernode \
    --uenv=${UENV_ICON} \
    bash ${ICONDIR}/run/run_wrapper/santis_gpu.sh ${BINARY_ICON}

echo ----- ICON finished

#################################################
# cleanup
#################################################
if [ ${NUM_RESTART_PROCS} -eq 0 ];then
 if [ -f *_restart_ATMO_????????T*.nc ]
 then
  cp *_restart_ATMO_????????T*.nc ${RESDIR}
  rm *_restart_ATMO_*.nc
 else
  echo 'Restart file was not created'
  DATE_END=$(date +%s)
  SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
  echo "icon      ${YYYY}_${MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
  exit
 fi
else
 if [ -d multifile_restart_ATMO_????????T*.mfr ]
 then
  cp -r multifile_restart_ATMO_????????T*.mfr ${RESDIR}/.
  rm -rf multifile_restart_ATMO_????????T*.mfr
 else
  echo 'Restart directory was not created'
  DATE_END=$(date +%s)
  SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")
  echo "icon      ${YYYY}_${MM} FAILED   $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log
  exit
 fi
fi

# ----------------------------------------------------------------------
#... unlink files needed for icon to the directory from which icon was started
# ----------------------------------------------------------------------
cd ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}

for IFILE in ${INI_FILES}
do
#    unlink $(basename ${IFILE}) && echo "$IFILE was unlinked ..."
   unlink $(basename ${IFILE}) && echo "$IFILE was unlinked ..."
done
if [ ${CURRENT_DATE} -ne ${YDATE_START} ]
then
 if [ ${NUM_RESTART_PROCS} -eq 0 ];then
# num_restart_procs=0
  unlink restart_ATMO_DOM01.nc
 else
# num_restart_procs>0
  unlink multifile_restart_ATMO.mfr
 fi
fi

# ----------------------------------------------------------------------
#... end of unlink part
# ----------------------------------------------------------------------

DATE_END=$(date +%s)
SEC_TOTAL=$(${PYTHON} -c "print(${DATE_END}-${DATE_START})")

if [ ${NEXT_DATE:6:4} -eq 0100 ]
then

  #... in case of partial month jobs reset the first date in date.log to the beginning of the
  #...   month. This is required for arch and post jobs
  if [ ${INC_DATE:3:2} -eq 0 ] && [ ${INC_DATE:6:2} -eq 0 ]
  then :
  else
      echo ${CURRENT_DATE:0:6}0100 > ${PFDIR}/${EXPID}/date.log
  fi

#################################################
# submit archive job
#################################################
  cd ${PFDIR}/${EXPID} ; ./subchain arch

echo END ${YYYY} ${MM}  >> ${WORKDIR}/${EXPID}/joblogs/icon/finish_joblist
echo "icon      ${YYYY}_${MM} FINISHED $(date) --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log

else

  #... save job output files in a subdirectory to prevent overwriting
  SUBDIR=$(cat ${PFDIR}/${EXPID}/date.log | cut -c7-8)
  if [ ! -d ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/${SUBDIR} ]
  then
    mkdir -p ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/${SUBDIR}
  fi

#  mv ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM} ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}parts/${SUBDIR}
  find ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM} -maxdepth 1 -type f -exec mv {} ${WORKDIR}/${EXPID}/joboutputs/icon/${YYYY_MM}/${SUBDIR} \;
  #... update date.log
  echo ${NEXT_DATE} > ${PFDIR}/${EXPID}/date.log
  echo "icon      ${YYYY}_${MM} FINISHED $(date) until ${NEXT_DATE} --- ${SEC_TOTAL}s" >> ${PFDIR}/${EXPID}/chain_status.log

  cd ${PFDIR}/${EXPID} ; ./subchain icon

  echo "END  " ${YYYY} ${MM} ${SUBDIR} >> ${WORKDIR}/${EXPID}/joblogs/icon/finish_joblist

fi
#endif daily-spice
