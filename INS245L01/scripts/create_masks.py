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

import argparse
import xarray as xr

def main(input_path, inidir, input_file, extpar_file):
    # Define file paths
    cdo_selname_lsm = f"{input_path}/{input_file}"
    input_fr_land = f"{inidir}/input_FR_LAND.nc"
    output_fr_land = f"{inidir}/output_FR_LAND.nc"

    # Load datasets
    ds_lsm = xr.open_dataset(cdo_selname_lsm)
    ds_extpar = xr.open_dataset(extpar_file)

    # Select LSM variable and rename to FR_LAND
    ds_lsm_sel = ds_lsm[['LSM']].rename({'LSM': 'FR_LAND'})
    ds_lsm_sel.to_netcdf(input_fr_land)
    print(f"File written: {input_fr_land}")

    # Select FR_LAND variable from external parameters
    ds_fr_land = ds_extpar[['FR_LAND']]
    ds_fr_land = ds_fr_land.expand_dims('time')
    ds_fr_land['time'] = ('time', [0])  # Add a dummy time value
    ds_fr_land.to_netcdf(output_fr_land)
    print(f"File written: {output_fr_land}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process ocean and land masks.')
    parser.add_argument('--input_path', required=True, help='Input directory path')
    parser.add_argument('--inidir', required=True, help='INI directory path')
    parser.add_argument('--input_file', required=True, help='Input file name')
    parser.add_argument('--extpar_file', required=True, help='External parameters file')

    args = parser.parse_args()
    main(args.input_path, args.inidir, args.input_file, args.extpar_file)

