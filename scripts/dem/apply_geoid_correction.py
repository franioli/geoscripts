#!/usr/bin/env python3
"""Apply a geoid correction to a DEM/DSM using a geoid-undulation raster (N).

    orthometric  H = h - N   (default,  --op sub)
    ellipsoidal  h = H + N   (          --op add)

The undulation raster (typically low-res, EPSG:4326) is reprojected and
resampled onto the DEM grid in a single rasterio.warp.reproject call
(bilinear by default), then combined cell by cell. This is the rigorous
workflow: one N value is interpolated at every DEM cell.

Examples:
    ./apply_geoid_correction.py dsm_ellip.tif geoid_undulation.tif
    ./apply_geoid_correction.py dem.tif geoid.tif --op add -o dem_ellip.tif
    ./apply_geoid_correction.py dem.tif geoid.tif -e cubic
"""

from __future__ import annotations

import argparse
import sys

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.warp import reproject

RESAMPLING_METHODS: dict[str, Resampling] = {
    "nearest": Resampling.nearest,
    "bilinear": Resampling.bilinear,
    "cubic": Resampling.cubic,
    "cubicspline": Resampling.cubic_spline,
    "lanczos": Resampling.lanczos,
}

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply a geoid correction to a DEM/DSM using an undulation raster.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("dem", help="DEM/DSM to correct")
    parser.add_argument("geoid", help="Geoid-undulation raster N (any CRS/resolution)")
    parser.add_argument("-o", "--output", default="dem_corrected.tif", help="Output corrected DEM")
    parser.add_argument(
        "-s", "--op", choices=("add", "sub"), default="sub",
        help="sub: H=h-N [default] | add: h=H+N",
    )
    parser.add_argument(
        "-e", "--resampling", choices=tuple(RESAMPLING_METHODS), default="bilinear",
        help="Resampling method for N (default: bilinear)",
    )
    parser.add_argument("-n", "--nodata", type=float, default=-9999.0, help="NoData value (default: -9999)")
    return parser.parse_args()

def resample_to_grid(
    src_path: str,
    ref: rasterio.DatasetReader,
    resampling: Resampling,
) -> np.ndarray:
    """Reproject and resample a raster onto the grid of ``ref``.

    Returns the band-1 array aligned to ``ref`` (CRS, transform, shape).
    """
    dst = np.empty((ref.height, ref.width), dtype=np.float32)
    with rasterio.open(src_path) as src:
        reproject(
            source=rasterio.band(src, 1),
            destination=dst,
            src_transform=src.transform,
            src_crs=src.crs,
            dst_transform=ref.transform,
            dst_crs=ref.crs,
            resampling=resampling,
        )
    return dst


def apply_geoid_correction(
    dem_path: str,
    geoid_path: str,
    out_path: str,
    operation: str = "sub",
    resampling: Resampling = Resampling.bilinear,
    nodata: float = -9999.0,
) -> None:
    """Combine a DEM with a geoid-undulation raster cell by cell.

    Args:
        operation: ``"sub"`` for H = h - N, ``"add"`` for h = H + N.
    """
    with rasterio.open(dem_path) as dem:
        profile = dem.profile.copy()
        dem_data = dem.read(1, masked=True)
        n = resample_to_grid(geoid_path, dem, resampling)

    corrected = dem_data - n if operation == "sub" else dem_data + n
    result = np.where(corrected.mask, nodata, corrected.filled(nodata)).astype(np.float32)

    profile.update(dtype="float32", count=1, nodata=nodata)
    with rasterio.open(out_path, "w", **profile) as dst:
        dst.write(result, 1)


def main() -> None:
    args = parse_args()
    label = "H = h - N" if args.op == "sub" else "h = H + N"
    print(f"\nGeoid correction  →  {label}")
    print(f"  DEM:        {args.dem}")
    print(f"  Geoid (N):  {args.geoid}")
    print(f"  Resampling: {args.resampling}")
    print(f"  Output:     {args.output}\n")

    apply_geoid_correction(
        dem_path=args.dem,
        geoid_path=args.geoid,
        out_path=args.output,
        operation=args.op,
        resampling=RESAMPLING_METHODS[args.resampling],
        nodata=args.nodata,
    )
    print(f"Done. Corrected DEM saved to: {args.output}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # surface a clean CLI error
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
