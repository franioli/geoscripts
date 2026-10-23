import glob
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import rasterio

# Add rasterio to your pixi environment first:
# pixi add rasterio matplotlib


def generate_dsm_preview(tif_path, out_path):
    with rasterio.open(tif_path) as src:
        data = src.read(1).astype(float)
        nodata = src.nodata

    # Mask nodata values
    if nodata is not None:
        data = np.where(data == nodata, np.nan, data)

    # Simple hillshade-like visualization using terrain colormap
    fig, ax = plt.subplots(figsize=(8, 8), dpi=150)
    im = ax.imshow(
        data,
        cmap="terrain",
        vmin=np.nanpercentile(data, 2),  # clip outliers
        vmax=np.nanpercentile(data, 98),
    )
    plt.colorbar(im, ax=ax, label="Elevation (m)", fraction=0.03, pad=0.04)
    ax.set_title(Path(tif_path).stem, fontsize=10)
    ax.axis("off")
    plt.tight_layout()
    plt.savefig(out_path, bbox_inches="tight", pad_inches=0.1)
    plt.close()
    print(f"Saved preview: {out_path}")


# Batch process all DSMs
for tif in glob.glob("data/*dsm*.tif"):
    out_png = tif.replace(".tif", "_preview.png")
    generate_dsm_preview(tif, out_png)
