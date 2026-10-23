#!/bin/bash
# apply_geoid_correction.sh
#
# Apply a geoid correction to a DEM/DSM using a geoid-undulation raster (N):
#   orthometric  H = h - N      (default,    -s sub)
#   ellipsoidal  h = H + N      (             -s add)
#
# The undulation raster (typically low-res, EPSG:4326) is warped onto the
# DEM grid (reproject + bilinear resample to the DEM CRS, extent and
# resolution), then summed cell by cell. This is the rigorous workflow:
# one N value is bilinearly interpolated at every DEM cell.
#
# Dependencies: GDAL >= 2.0  (gdalwarp, gdal_calc.py, gdalinfo, gdalsrsinfo)
#
# Examples:
#   ./apply_geoid_correction.sh dsm_ellip.tif geoid_undulation.tif
#   ./apply_geoid_correction.sh dem.tif geoid.tif -s add -o dem_ellip.tif
#   ./apply_geoid_correction.sh dem.tif geoid.tif -e cubic -k

# ─── Default Values ───────────────────────────────────────────────────────────

DEM=""                          # DEM/DSM to correct       (positional arg 1)
GEOID=""                        # Geoid-undulation raster N (positional arg 2)
WARPED_GEOID=""                 # Warped N output path     (-w); auto if empty
OUT_DEM="dem_corrected.tif"     # Corrected DEM output      (-o)
RESAMPLING="bilinear"           # Resampling for N          (-e)
OPERATION="sub"                 # sub: H=h-N  |  add: h=H+N (-s)
KEEP_WARPED=false               # Keep intermediate N file  (-k)
NODATA="-9999"                  # NoData value for output   (-n)

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Apply a geoid correction to a DEM/DSM using a geoid-undulation raster (N).

The undulation raster is warped onto the DEM grid (CRS + extent + resolution,
bilinear by default), then combined cell by cell:
    -s sub :  H = h - N   (ellipsoidal -> orthometric)  [default]
    -s add :  h = H + N   (orthometric -> ellipsoidal)

Usage:  $(basename "$0") [options] <dem> <geoid>

  Arguments:
    dem             DEM/DSM to correct
    geoid           Geoid-undulation raster N (any CRS/resolution)

  Output:
    -o PATH         Output corrected DEM        (default: dem_corrected.tif)
    -w PATH         Output path for warped N    (default: auto-generated)
    -k              Keep intermediate warped N  (default: deleted)
    -n VALUE        NoData value for the output (default: -9999)

  Correction:
    -s add|sub      Direction of correction (default: sub)
                      sub -> H = h - N  [default]
                      add -> h = H + N
    -e METHOD       Resampling method for N (default: bilinear)
                    Options: nearest, bilinear, cubic, cubicspline, lanczos, …

  Examples:
    $(basename "$0") dsm_ellip.tif geoid_undulation.tif
    $(basename "$0") -s add -o dem_ellip.tif dem.tif geoid.tif
    $(basename "$0") -e cubic -k dem.tif geoid.tif

EOF
    exit 1
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) OPERATION="${2,,}"; shift 2 ;;   # ${2,,} = lowercase
        -e) RESAMPLING="$2"; shift 2 ;;
        -n) NODATA="$2"; shift 2 ;;
        -o) OUT_DEM="$2"; shift 2 ;;
        -w) WARPED_GEOID="$2"; shift 2 ;;
        -k) KEEP_WARPED=true; shift ;;
        -h) usage ;;
        -*) echo "ERROR: Unknown option: $1" >&2; usage ;;
        *)  # positional args
            if   [ -z "$DEM" ];   then DEM="$1"
            elif [ -z "$GEOID" ]; then GEOID="$1"
            else echo "ERROR: Unexpected argument: $1" >&2; usage
            fi
            shift ;;
    esac
done

# ─── Validate Inputs ──────────────────────────────────────────────────────────

if [ -z "$DEM" ] || [ -z "$GEOID" ]; then
    echo "ERROR: Two raster paths are required: <dem> <geoid>"
    usage
fi

[ ! -f "$DEM" ]   && { echo "ERROR: DEM not found: $DEM"; exit 1; }
[ ! -f "$GEOID" ] && { echo "ERROR: Geoid raster not found: $GEOID"; exit 1; }

if [ "$OPERATION" != "add" ] && [ "$OPERATION" != "sub" ]; then
    echo "ERROR: -s must be 'add' or 'sub' (got: '$OPERATION')"; exit 1
fi

# ─── Resolve Warped Output Path ───────────────────────────────────────────────

if [ -z "$WARPED_GEOID" ]; then
    BASENAME=$(basename "${GEOID%.*}")
    WARPED_GEOID="$(dirname "${GEOID}")/${BASENAME}_warped.tif"
fi

# ─── Extract Target Grid Parameters from the DEM ──────────────────────────────

# The DEM defines the target grid; N is warped to match it exactly.
DEM_SRS=$(gdalsrsinfo -o proj4 "$DEM")

ULX=$(gdalinfo "$DEM" | grep "Upper Left"  | sed -E 's/^Upper Left  \(\s*([0-9.-]+),.*$/\1/')
ULY=$(gdalinfo "$DEM" | grep "Upper Left"  | sed -E 's/^Upper Left  \(\s*[0-9.-]+,\s*([0-9.-]+).*$/\1/')
LRX=$(gdalinfo "$DEM" | grep "Lower Right" | sed -E 's/^Lower Right \(\s*([0-9.-]+),.*$/\1/')
LRY=$(gdalinfo "$DEM" | grep "Lower Right" | sed -E 's/^Lower Right \(\s*[0-9.-]+,\s*([0-9.-]+).*$/\1/')

if [ -z "$ULX" ] || [ -z "$ULY" ] || [ -z "$LRX" ] || [ -z "$LRY" ]; then
    echo "ERROR: Failed to extract bounds from: $DEM"; exit 1
fi

XRES=$(gdalinfo "$DEM" | grep "Pixel Size" | sed -E 's/^Pixel Size = \(([0-9.-]+),.*$/\1/')
YRES=$(gdalinfo "$DEM" | grep "Pixel Size" | sed -E 's/^Pixel Size = \([0-9.-]+,([0-9.-]+)\).*$/\1/')
XRES="${XRES#-}"  # strip leading minus (Y pixel size is stored negative)
YRES="${YRES#-}"

if [ -z "$XRES" ] || [ -z "$YRES" ]; then
    echo "ERROR: Failed to extract pixel size from: $DEM"; exit 1
fi

# ─── Print Summary ────────────────────────────────────────────────────────────

if [ "$OPERATION" = "sub" ]; then EXPR_LABEL="H = h - N"; else EXPR_LABEL="h = H + N"; fi

echo ""
echo "Geoid correction  →  $EXPR_LABEL"
echo "  DEM:             $DEM"
echo "  Geoid (N):       $GEOID  →  $WARPED_GEOID"
echo "  Target CRS:      $DEM_SRS"
echo "  Target res:      ${XRES} x ${YRES}"
echo "  Resampling:      $RESAMPLING"
echo "  Output:          $OUT_DEM"
echo ""

# ─── Warp N onto the DEM Grid ─────────────────────────────────────────────────

echo "Warping $(basename "$GEOID") onto the DEM grid ..."

# -te is in the DEM's own CRS, so -te_srs matches -t_srs.
gdalwarp \
    -t_srs  "$DEM_SRS" \
    -te_srs "$DEM_SRS" \
    -te "$ULX" "$LRY" "$LRX" "$ULY" \
    -tr "$XRES" "$YRES" \
    -r  "$RESAMPLING" \
    -overwrite \
    "$GEOID" "$WARPED_GEOID"

[ $? -ne 0 ] && { echo "ERROR: gdalwarp failed for $(basename "$GEOID")"; exit 1; }

# ─── Apply the Correction ─────────────────────────────────────────────────────

if [ "$OPERATION" = "sub" ]; then CALC_EXPR="A-B"; else CALC_EXPR="A+B"; fi

echo "Applying correction ($EXPR_LABEL) ..."

gdal_calc.py \
    --calc="$CALC_EXPR" \
    --format=GTiff \
    --type=Float32 \
    --NoDataValue="$NODATA" \
    -A "$DEM" \
    -B "$WARPED_GEOID" \
    --outfile="$OUT_DEM" \
    --overwrite

[ $? -ne 0 ] && { echo "ERROR: gdal_calc.py failed"; exit 1; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────

if [ "$KEEP_WARPED" = false ]; then
    echo "Removing intermediate warped N: $WARPED_GEOID"
    rm -f "$WARPED_GEOID"
else
    echo "Keeping intermediate warped N:  $WARPED_GEOID"
fi

echo ""
echo "Done. Corrected DEM saved to: $OUT_DEM"
