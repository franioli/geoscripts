# geoscripts

Small collection of command-line scripts for raster (DEM/DSM/orthophoto) and
point-cloud processing, built on GDAL, PDAL and rasterio.

## Layout

| Folder | Script | Purpose |
|---|---|---|
| `scripts/cog/` | `convert_to_cog.sh` | One GeoTIFF → Cloud Optimized GeoTIFF (auto predictor) |
| | `convert_to_cog_batch.sh` | Batch wrapper around `convert_to_cog.sh` |
| | `convert_raster_to_cog.sh` | Quick converter for `*dsm*.tif` / `*orthophoto*.tif` in a folder |
| `scripts/copc/` | `convert_to_copc.sh` | One point cloud (LAS/LAZ/E57/PLY…) → COPC |
| | `convert_to_copc_batch.sh` | Batch wrapper around `convert_to_copc.sh` |
| `scripts/dem/` | `apply_geoid_correction.sh` / `.py` | Apply a geoid-undulation raster to a DEM (GDAL / rasterio versions) |
| | `compute_dem_of_difference_gdal.sh` | DEM of difference A − B with GDAL |
| | `compute_dod_batch.py` | Consecutive-year DoD for a set of surveys |
| `scripts/preview/` | `generate_dsm_previews.py` | PNG previews of `data/*dsm*.tif` |

Each batch script calls its single-file sibling from the same folder, so keep
them together. Every script documents its options in its header, or via `-h`.

## Environment (pixi)

Dependencies are declared in [pixi.toml](pixi.toml): Python, GDAL, PDAL (with
COPC support), rasterio, numpy and matplotlib, all from conda-forge.

1. Install pixi (once): `curl -fsSL https://pixi.sh/install.sh | bash`
2. From the repo root, create the environment: `pixi install`
   (creates `.pixi/`, and a `pixi.lock` to commit for reproducibility)
3. Run a script inside it:

   ```bash
   pixi run scripts/cog/convert_to_cog.sh dsm.tif
   pixi run scripts/copc/convert_to_copc_batch.sh -s data -d copc
   pixi run python scripts/dem/apply_geoid_correction.py dem.tif geoid.tif
   ```

   Or open a shell with everything on `PATH`: `pixi shell`, then call the
   scripts directly.

Add a package with `pixi add <name>`.

### Using your existing micromamba env instead

The `geospatial` env already has GDAL and PDAL. The Python scripts also need
rasterio, numpy and matplotlib:

```bash
micromamba activate geospatial
micromamba install -c conda-forge rasterio numpy matplotlib-base
```

## Notes

- Scripts using relative defaults (`data/`, `cog/`, `open-data/`…) expect to be
  run from your data working directory, not from the script's folder.
- The docstring of `compute_dod_batch.py` refers to `scripts/compute_dod_batch.py`;
  its real path is now `scripts/dem/compute_dod_batch.py`.
- Harmless PDAL warnings about `libpdal_plugin_reader_hdf` / `icebridge` can
  appear; they don't affect LAS/LAZ/COPC.
