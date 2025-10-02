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

import os
import sys
import numpy as np
import xarray as xr


def file_exists(file_path):
    """Check if a file exists."""
    return os.path.exists(file_path)


class WeatherData:
    """Class to store and fetch empirical constants."""

    def __init__(self):
        # Short reference
        self.cn_short_hourly_day = 37
        self.cd_short_hourly_day = 0.24
        self.cn_short_hourly_night = 37
        self.cd_short_hourly_night = 0.96
        self.G_short_daytime = 0.1
        self.G_short_nighttime = 0.5

    def hourly_constants(self, reference, time_of_day):
        """Fetch hourly constants based on reference type and time of day."""
        if reference == "short" and time_of_day == "day":
            return self.cn_short_hourly_day, self.cd_short_hourly_day, self.G_short_daytime
        elif reference == "short" and time_of_day == "night":
            return self.cn_short_hourly_night, self.cd_short_hourly_night, self.G_short_nighttime
        else:
            raise ValueError("Reference not defined. Select from 'short'.")


def saturation_vapor_pressure(temperature):
    """Calculate saturation vapor pressure."""
    return 0.6108 * np.exp(17.27 * temperature / (temperature + 237.3))


def actual_vap_pressure_from_ps_qv_2m(ps, qv_2m):
    """Calculate actual vapor pressure from surface pressure and specific humidity."""
    return qv_2m * ps / (0.622 + 0.378 * qv_2m)


def actual_vap_pressure_from_t_rh_2m(t_2m, rh_2m):
    """Calculate actual vapor pressure from temperature and relative humidity."""
    return xr.where(
        t_2m >= 273.15,
        6.112 * rh_2m * np.exp(17.62 * (t_2m - 273.15) / (t_2m - 30.03)),
        6.112 * rh_2m * np.exp(22.46 * (t_2m - 273.15) / (t_2m - 0.53))
    )


def main():
    ref_type = "short"
    ipath = sys.argv[1]

    # Input variables
    print("Loading input datasets...")
    ds_t2m = xr.open_dataset(ipath + "AT_2M_ts.nc")
    ds_sp_10m = xr.open_dataset(ipath + "ASP_10M_ts.nc")
    ds_sw = xr.open_dataset(ipath + "ASOB_S_ts.nc")
    ds_lw = xr.open_dataset(ipath + "ATHB_S_ts.nc")

    # Input files for actual vapor pressure calculation
    infile1 = "APS_ts.nc"
    infile2 = "AQV_2M_ts.nc"
    infile3 = "AT_2M_ts.nc"
    infile4 = "ARELHUM_2M_ts.nc"

    var_altitude = 2  # Assuming a default altitude of 2 meters
    var_wind_height = 10  # Assuming wind height is 10 meters

    # Natural constants
    c_p = 1.013e-3  # specific heat at constant pressure [MJ kg-1 °C-1]
    epsilon = 0.622  # ratio molecular weight of water vapor/dry air
    lambda_val = 2.45  # latent heat of vaporization [MJ kg-1]
    unit_hourly = 0.0036

    var_tmean = ds_t2m['AT_2M'] - 273.15  # from K to degree C

    # Check input files for actual vapor pressure
    print("Checking input files for actual vapor pressure...")
    if file_exists(ipath + infile1) and file_exists(ipath + infile2):
        ds1 = xr.open_dataset(ipath + infile1)
        ds2 = xr.open_dataset(ipath + infile2)
        ps = ds1["APS"]
        qv_2m = ds2["AQV_2M"]
        e_a = actual_vap_pressure_from_ps_qv_2m(ps, qv_2m)
        ds1.close()
        ds2.close()
    elif file_exists(ipath + infile3) and file_exists(ipath + infile4):
        ds1 = xr.open_dataset(ipath + infile3)
        ds2 = xr.open_dataset(ipath + infile4)
        t_2m = ds1["AT_2M"]
        rh_2m = ds2["ARELHUM_2M"]
        e_a = actual_vap_pressure_from_t_rh_2m(t_2m, rh_2m)
        ds1.close()
        ds2.close()
    else:
        print("Input files for calculation of actual vapor pressure are missing!")
        sys.exit(1)

    e_a = e_a / 1000  # from Pa to kPa

    var_wind = ds_sp_10m['ASP_10M']
    R_ns = ds_sw['ASOB_S'] * unit_hourly  # from W/m2 to MJm-2
    R_nl = ds_lw['ATHB_S'] * unit_hourly  # from W/m2 to MJm-2

    FAO56_PMconstants = WeatherData()

    # Constants from Singer (2021)
    C_n = 37
    C_d = 0.34

    # Calculations
    print("Performing calculations...")
    pressure = 101.3 * (((293 - 0.0065 * var_altitude) / 293) ** 5.26)
    gamma = (c_p * pressure) / (epsilon * lambda_val)  # psychrometric constant [kPa °C-1]

    e_sat = saturation_vapor_pressure(var_tmean)
    e_deficit = e_sat - e_a

    delta = (4098 * (0.6108 * np.exp(17.27 * var_tmean / (var_tmean + 237.3)))) / ((var_tmean + 237.3) ** 2)
    u2 = var_wind * 4.87 / np.log(67.8 * var_wind_height - 5.42)  # wind speed 10m -> 2m above ground

    R_n = R_ns - R_nl
    G = xr.where(
        R_ns <= 0,
        R_n * FAO56_PMconstants.hourly_constants(reference=ref_type, time_of_day="night")[2],
        R_n * FAO56_PMconstants.hourly_constants(reference=ref_type, time_of_day="day")[2]
    )

    # Remove extra dimensions if present
    delta = delta.squeeze()
    u2 = u2.squeeze()
    e_deficit = e_deficit.squeeze()

    APOTEVAP_S = (0.408 * delta * (R_n - G) + gamma * (C_n / (var_tmean + 273)) * u2 * e_deficit) / (
            delta + gamma * (1 + C_d * u2)
    )

    # Remove extra dimensions from APOTEVAP_S
    APOTEVAP_S = APOTEVAP_S.squeeze()

    APOTEVAP_S = xr.DataArray(
        APOTEVAP_S,
        attrs={
            "long_name": "Potential evapotranspiration",
            "standard_name": "water_potential_evapotranspiration_amount",
            "units": "kg m-2",
            "grid_mapping": "rotated_pole",
            "cell_methods": "time: sum",
        },
        coords={'time': ds_t2m.time, 'rlat': ds_t2m.rlat, 'rlon': ds_t2m.rlon},
        dims=['time', 'rlat', 'rlon']
    )

    ds_APOTEVAP_S = xr.Dataset({
        "APOTEVAP_S": APOTEVAP_S,
        "lon": ds_t2m.lon,
        "lon_bnds": ds_t2m.lon_bnds,
        "lat": ds_t2m.lat,
        "lat_bnds": ds_t2m.lat_bnds,
        # "time_bnds": ds_t2m.time_bnds,
        "rotated_pole": ds_t2m.rotated_pole
    })

    ds_APOTEVAP_S.attrs = ds_t2m.attrs
    ds_APOTEVAP_S.attrs['history'] = "FAO56 Penman-Monteith equation, Allen (2005), Singer (2021) Nature, based hourly PET"

    encoding = {
        'lat': {'_FillValue': None},
        'lon': {'_FillValue': None},
        'lat_bnds': {'_FillValue': None},
        'lon_bnds': {'_FillValue': None},
        'rlat': {'_FillValue': None},
        'rlon': {'_FillValue': None},
        #'height_2m': {'_FillValue': None},
        'time': {'_FillValue': None, 'dtype': 'float64'},
        #'time_bnds': {'_FillValue': None, 'dtype': 'float64'},
        'APOTEVAP_S': {'_FillValue': -1.e+20}
    }

    print("Saving output to NetCDF...")
    ds_APOTEVAP_S.to_netcdf(ipath + 'APOTEVAP_S_ts.nc', encoding=encoding)
    print("Process completed successfully!")


if __name__ == "__main__":
    main()