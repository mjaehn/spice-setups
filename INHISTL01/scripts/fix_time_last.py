import xarray as xr
import numpy as np
import sys

filename = sys.argv[1]

with xr.open_dataset(filename) as ds:
    time = ds['time'].values
    if np.issubdtype(time.dtype, np.datetime64):
        if len(time) > 1:
            dt = time[1] - time[0]
            expected_last = time[0] + dt * (len(time) - 1)
            if time[-1] != expected_last:
                print(f"Correcting last time value: {time[-1]} -> {expected_last}")
                time[-1] = expected_last
                ds['time'].values[:] = time
                ds.to_netcdf(filename, mode='w')
            else:
                print("No correction needed.")
        else:
            print("Not enough time steps to check.")
    else:
        print("Time variable is not in datetime64 format.")
