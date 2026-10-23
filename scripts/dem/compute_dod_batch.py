"""Compute consecutive-year DSM-of-Difference (DoD) for all Belvedere surveys.

Usage
-----
    pixi run python scripts/compute_dod_batch.py
    pixi run python scripts/compute_dod_batch.py --data-dir open-data --out-dir proc/dod
    pixi run python scripts/compute_dod_batch.py --force   # overwrite existing files

Output naming convention (matches the manually-created reference file):
    proc/dod/belv_{Y_new}-{Y_old}_{platform_new}_dod_{res}cm_cog.tif

Resolution rule
---------------
When two DSMs have different resolutions the finer one is warped onto the
coarser grid (bilinear). This avoids upsampling artefacts and the DoD inherits
the coarser resolution label.
"""

import argparse
import glob
import json
import os
import sys
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.warp import reproject

NODATA = -9999.0


def discover_surveys(data_dir: str) -> list[dict]:
    """Return all surveys with a DSM, sorted by year."""
    surveys = []
    for meta_path in sorted(glob.glob(f"{data_dir}/*_meta.json")):
        with open(meta_path) as f:
            meta = json.load(f)

        dsm_raw = meta.get("data", {}).get("dsm")
        if dsm_raw is None:
            continue
        dsm_meta = dsm_raw[0] if isinstance(dsm_raw, list) else dsm_raw

        dsm_path = Path(data_dir) / dsm_meta["file_name"]
        if not dsm_path.exists():
            print(
                f"  Warning: DSM not found ({dsm_path}), skipping year {meta['year']}."
            )
            continue

        platform = Path(meta_path).stem.split("_")[2]  # e.g. "uav", "histo-aerial"
        surveys.append({
            "year": int(meta["year"]),
            "platform": platform,
            "dsm_path": str(dsm_path),
            "resolution_m": float(dsm_meta["resolution_m"]),
        })

    surveys.sort(key=lambda s: s["year"])
    return surveys


def res_label(res_m: float) -> str:
    """0.2 → '20cm', 0.4 → '40cm', 0.5 → '50cm'."""
    return f"{round(res_m * 100)}cm"


def compute_dod(newer: dict, older: dict, out_path: str) -> None:
    """Write DoD (newer − older) as a Cloud-Optimized GeoTIFF."""
    # Coarser resolution = reference grid; finer = warped
    if newer["resolution_m"] <= older["resolution_m"]:
        ref, warp = older, newer
        ref_is_older = True
    else:
        ref, warp = newer, older
        ref_is_older = False

    # Read reference grid properties and data
    with rasterio.open(ref["dsm_path"]) as ref_src:
        ref_height = ref_src.height
        ref_width = ref_src.width
        ref_transform = ref_src.transform
        ref_crs = ref_src.crs
        ref_nodata = ref_src.nodata
        ref_arr = ref_src.read(1).astype(np.float32)

    # Normalise nodata in reference array
    if ref_nodata is not None:
        ref_arr[ref_arr == ref_nodata] = NODATA

    # Read and reproject the other DSM onto the reference grid
    with rasterio.open(warp["dsm_path"]) as warp_src:
        warp_data = warp_src.read(1).astype(np.float32)
        warp_transform = warp_src.transform
        warp_crs = warp_src.crs
        warp_nodata = warp_src.nodata if warp_src.nodata is not None else NODATA

    warp_arr = np.full((ref_height, ref_width), NODATA, dtype=np.float32)
    reproject(
        source=warp_data,
        destination=warp_arr,
        src_transform=warp_transform,
        src_crs=warp_crs,
        src_nodata=warp_nodata,
        dst_transform=ref_transform,
        dst_crs=ref_crs,
        dst_nodata=NODATA,
        resampling=Resampling.bilinear,
    )

    # Assign to newer/older
    if ref_is_older:
        newer_arr, older_arr = warp_arr, ref_arr
    else:
        newer_arr, older_arr = ref_arr, warp_arr

    # DoD = newer − older; mask pixels where either input is nodata
    valid = (newer_arr != NODATA) & (older_arr != NODATA)
    dod = np.where(valid, newer_arr - older_arr, NODATA).astype(np.float32)

    # Write as COG (GDAL COG driver: handles tiling + overviews automatically)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with rasterio.open(
        out_path,
        "w",
        driver="COG",
        height=ref_height,
        width=ref_width,
        count=1,
        dtype="float32",
        crs=ref_crs,
        transform=ref_transform,
        nodata=NODATA,
        compress="DEFLATE",
        predictor=3,
        blocksize=512,
        overview_resampling="AVERAGE",
    ) as dst:
        dst.write(dod, 1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--data-dir",
        default="open-data",
        help="Folder with finalized DSMs and *_meta.json files (default: open-data)",
    )
    parser.add_argument(
        "--out-dir",
        default="proc/dod",
        help="Output folder for DoD COGs (default: proc/dod)",
    )
    parser.add_argument(
        "--force", action="store_true", help="Overwrite existing DoD files"
    )
    args = parser.parse_args()

    surveys = discover_surveys(args.data_dir)
    if len(surveys) < 2:
        print(
            f"ERROR: need at least 2 surveys in '{args.data_dir}', found {len(surveys)}."
        )
        sys.exit(1)

    print(f"Found {len(surveys)} surveys: {[s['year'] for s in surveys]}")
    print()

    # Build consecutive pairs, most-recent first
    pairs = [(surveys[i + 1], surveys[i]) for i in range(len(surveys) - 1)]
    pairs.reverse()

    col_w = 52
    results = []
    for newer, older in pairs:
        ref_res = max(newer["resolution_m"], older["resolution_m"])
        out_name = f"belv_{newer['year']}-{older['year']}_{newer['platform']}_dod_{res_label(ref_res)}_cog.tif"
        out_path = os.path.join(args.out_dir, out_name)

        if os.path.exists(out_path) and not args.force:
            print(f"  [skip]  {out_name}")
            results.append((newer["year"], older["year"], out_name, "skipped"))
            continue

        print(
            f"  {newer['year']} − {older['year']}  ({res_label(newer['resolution_m'])} vs {res_label(older['resolution_m'])} → {res_label(ref_res)})  …"
        )
        try:
            compute_dod(newer, older, out_path)
            results.append((newer["year"], older["year"], out_name, "done"))
        except Exception as exc:
            print(f"    ERROR: {exc}")
            results.append((newer["year"], older["year"], out_name, "ERROR"))

    print()
    print(f"{'Pair':<10}  {'Status':<8}  File")
    print("-" * 70)
    for y_new, y_old, name, status in results:
        print(f"  {y_new}-{y_old:<6}  {status:<8}  {name}")

    n_done = sum(1 for *_, s in results if s == "done")
    n_err = sum(1 for *_, s in results if s.startswith("ERROR"))
    print(
        f"\n{n_done} computed, {sum(1 for *_, s in results if s == 'skipped')} skipped, {n_err} errors."
    )


if __name__ == "__main__":
    main()
