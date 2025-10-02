import xarray as xr
import numpy as np
import sys
from pathlib import Path


def main(filename: str) -> None:
    filename = Path(filename)

    # Open the file, load it into memory and close the underlying file handle
    # This avoids problems when writing back to the same path.
    with xr.open_dataset(filename) as src:
        ds = src.load()

    time = ds['time'].values
    if np.issubdtype(time.dtype, np.datetime64):
        if len(time) > 1:
            dt = time[1] - time[0]
            expected_last = time[0] + dt * (len(time) - 1)
            if time[-1] != expected_last:
                old_last = time[-1]
                print(f"Correcting last time value: {old_last} -> {expected_last}")
                time[-1] = expected_last
                # operate on an in-memory copy
                ds = ds.copy()
                # assign_coords is the supported way to update a dimension coordinate
                ds = ds.assign_coords(time=time)

                # If there are time bounds, try to update any entries that reference the old last value.
                if 'time_bnds' in ds:
                    try:
                        tb = ds['time_bnds'].values
                        # replace any occurrence of the old last time
                        mask = tb == old_last
                        if mask.any():
                            tb[mask] = expected_last
                            ds['time_bnds'].values = tb
                        else:
                            # As a fallback, if time_bnds has the same first dim length as time,
                            # set the last row to [expected_last - dt, expected_last]
                            if tb.shape[0] == len(time) and tb.shape[-1] >= 2:
                                try:
                                    tb[-1, 0] = expected_last - dt
                                    tb[-1, 1] = expected_last
                                    ds['time_bnds'].values = tb
                                except Exception:
                                    # ignore if shapes/dtypes don't match exactly
                                    pass
                    except Exception:
                        # If anything goes wrong adjusting time_bnds, continue — we at least fixed the time coord.
                        pass
            else:
                print("No correction needed.")
        else:
            print("Not enough time steps to check.")
    else:
        print("Time variable is not in datetime64 format.")

    print(f"Overwriting file {filename}")
    # Write the in-memory dataset back to disk (this will create/overwrite the file)
    ds.to_netcdf(filename, mode='w')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix_time_last.py <file.nc>")
        sys.exit(2)
    main(sys.argv[1])
