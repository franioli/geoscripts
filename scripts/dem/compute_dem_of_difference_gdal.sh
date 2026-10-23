#!/bin/bash
# differenciate_dems.sh
#
# Compute the elevation difference between two DEMs:  result = A − B
#
# By default the DEM A is warped onto the DEM B grid.
# Use -W to reverse the direction, -c/-t to target a custom CRS/resolution
# (both DEMs are then reprojected to that common grid), and -d to mask out
# large outlier differences.
#
# Dependencies: GDAL ≥ 2.0  (gdalwarp, gdal_calc.py, gdalinfo, gdalsrsinfo)
#
# Examples:
#   ./differenciate_dems.sh dem_2017.tif dem_2009.tif
#   ./differenciate_dems.sh dem_2017.tif dem_2009.tif -W a -o diff.tif
#   ./differenciate_dems.sh dem_2017.tif dem_2009.tif -c EPSG:32632 -t 1.0 -d 50

# ─── Default Values ───────────────────────────────────────────────────────────

DEM_A=""                 # First DEM  (minuend,    result = A − B)   (positional arg 1)
DEM_B=""                 # Second DEM (subtrahend, result = A − B)   (positional arg 2)
WARPED_DEM=""            # Warped DEM output path     (-w); auto-generated if empty
DIFF_DEM="dem_difference.tif"  # Difference DEM output (-o)
RESAMPLING="bilinear"    # Resampling method           (-e)
KEEP_WARPED=false        # Keep intermediate warped files (-k)
WARP_DEM="a"             # Which DEM is warped         (-W): "a" (default) or "b"
TARGET_RES=""            # Override target resolution  (-t); default from grid-DEM
TARGET_CRS=""            # Override target CRS         (-c); default from grid-DEM
MAX_DIFF=""              # Mask |diff| > VALUE         (-d); default: no masking
NODATA="-9999"           # NoData value for the output (-n)

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Compute the elevation difference between two DEMs:  result = A − B

By default DEM A is warped onto DEM B's grid.
Use -W b to reverse (warp B onto A's grid).
Use -c / -t to target a custom CRS or resolution; in that case both DEMs
are reprojected to the same common grid before differencing.

Usage:  $(basename "$0")[options] <dem_A> <dem_B> 

  Arguments:
    dem_A           First DEM  (minuend:    result = A − B)
    dem_B           Second DEM (subtrahend: result = A − B)

  Output:
    -o PATH         Output difference DEM         (default: dem_difference.tif)
    -w PATH         Output path for warped DEM    (default: auto-generated)
    -k              Keep intermediate warped DEMs (default: deleted)
    -n VALUE        NoData value for the output   (default: -9999)

  Warp control:
    -W a|b          Which DEM is warped onto the other's grid (default: a)
                      a → warp A onto B's grid  [default]
                      b → warp B onto A's grid
    -t FLOAT        Target pixel size in map units (e.g. 1.0 for 1 m).
                    Overrides the resolution of the grid DEM.
                    When set, both DEMs are reprojected to this resolution.
    -c CRS          Target CRS, e.g. EPSG:32632.
                    Overrides the CRS of the grid DEM.
                    When set, both DEMs are reprojected to this CRS.
    -e METHOD       Resampling method for gdalwarp (default: bilinear)
                    Options: nearest, bilinear, cubic, cubicspline, lanczos, …

  Masking:
    -d VALUE        Mask pixels where |diff| > VALUE (e.g. 50 for 50 m).
                    Masked pixels are set to NoData. Default: no masking.

  Examples:
    $(basename "$0") dem_2017.tif dem_2009.tif
    $(basename "$0") -W b -o result.tif dem_2017.tif dem_2009.tif
    $(basename "$0") -c EPSG:32632 -t 1.0 -d 50 -k dem_2017.tif dem_2009.tif

EOF
    exit 1
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -W) WARP_DEM="${2,,}"; shift 2 ;;   # ${2,,} = lowercase
        -t) TARGET_RES="$2"; shift 2 ;;
        -c) TARGET_CRS="$2"; shift 2 ;;
        -e) RESAMPLING="$2"; shift 2 ;;
        -d) MAX_DIFF="$2"; shift 2 ;;
        -n) NODATA="$2"; shift 2 ;;
        -o) DIFF_DEM="$2"; shift 2 ;;
        -w) WARPED_DEM="$2"; shift 2 ;;
        -k) KEEP_WARPED=true; shift ;;
        -h) usage ;;
        -*) echo "ERROR: Unknown option: $1" >&2; usage ;;
        *)  # positional args
            if   [ -z "$DEM_A" ]; then DEM_A="$1"
            elif [ -z "$DEM_B" ]; then DEM_B="$1"
            else echo "ERROR: Unexpected argument: $1" >&2; usage
            fi
            shift ;;
    esac
done

# ─── Validate Inputs ──────────────────────────────────────────────────────────

if [ -z "$DEM_A" ] || [ -z "$DEM_B" ]; then
    echo "ERROR: Two DEM paths are required as positional arguments: dem_A dem_B"
    usage
fi

[ ! -f "$DEM_A" ] && { echo "ERROR: DEM A not found: $DEM_A"; exit 1; }
[ ! -f "$DEM_B" ] && { echo "ERROR: DEM B not found: $DEM_B"; exit 1; }

if [ "$WARP_DEM" != "a" ] && [ "$WARP_DEM" != "b" ]; then
    echo "ERROR: -W must be 'a' or 'b' (got: '$WARP_DEM')"; exit 1
fi

# ─── Determine Warp Direction ─────────────────────────────────────────────────

# DEM_GRID:  provides the target grid (not warped, unless -c/-t override)
# DEM_WARP:  is reprojected to match DEM_GRID

if [ "$WARP_DEM" = "a" ]; then
    DEM_WARP="$DEM_A"
    DEM_GRID="$DEM_B"
else
    DEM_WARP="$DEM_B"
    DEM_GRID="$DEM_A"
fi

# ─── Resolve Warped Output Path ───────────────────────────────────────────────

if [ -z "$WARPED_DEM" ]; then
    BASENAME=$(basename "${DEM_WARP%.*}")
    WARPED_DEM="$(dirname "${DEM_WARP}")/${BASENAME}_warped.tif"
fi

# ─── Extract Target Grid Parameters from DEM_GRID ─────────────────────────────

# CRS: user-provided value overrides DEM_GRID
if [ -n "$TARGET_CRS" ]; then
    WARP_SRS="$TARGET_CRS"
else
    WARP_SRS=$(gdalsrsinfo -o proj4 "$DEM_GRID")
fi

# DEM_GRID native CRS — needed for -te_srs so extent is passed in its own CRS
GRID_SRS=$(gdalsrsinfo -o proj4 "$DEM_GRID")

# Extent: always taken from DEM_GRID (expressed in its native CRS)
# gdalwarp -te_srs will reproject these bounds into the target CRS automatically.
ULX=$(gdalinfo "$DEM_GRID" | grep "Upper Left"  | sed -E 's/^Upper Left  \(\s*([0-9.-]+),.*$/\1/')
ULY=$(gdalinfo "$DEM_GRID" | grep "Upper Left"  | sed -E 's/^Upper Left  \(\s*[0-9.-]+,\s*([0-9.-]+).*$/\1/')
LRX=$(gdalinfo "$DEM_GRID" | grep "Lower Right" | sed -E 's/^Lower Right \(\s*([0-9.-]+),.*$/\1/')
LRY=$(gdalinfo "$DEM_GRID" | grep "Lower Right" | sed -E 's/^Lower Right \(\s*[0-9.-]+,\s*([0-9.-]+).*$/\1/')

if [ -z "$ULX" ] || [ -z "$ULY" ] || [ -z "$LRX" ] || [ -z "$LRY" ]; then
    echo "ERROR: Failed to extract bounds from: $DEM_GRID"; exit 1
fi

# Resolution: user-provided value overrides DEM_GRID
if [ -n "$TARGET_RES" ]; then
    XRES="$TARGET_RES"
    YRES="$TARGET_RES"
else
    XRES=$(gdalinfo "$DEM_GRID" | grep "Pixel Size" | sed -E 's/^Pixel Size = \(([0-9.-]+),.*$/\1/')
    YRES=$(gdalinfo "$DEM_GRID" | grep "Pixel Size" | sed -E 's/^Pixel Size = \([0-9.-]+,([0-9.-]+)\).*$/\1/')
    XRES="${XRES#-}"  # strip leading minus (Y pixel size is stored negative)
    YRES="${YRES#-}"
fi

if [ -z "$XRES" ] || [ -z "$YRES" ]; then
    echo "ERROR: Failed to extract pixel size from: $DEM_GRID"; exit 1
fi

# ─── Print Summary ────────────────────────────────────────────────────────────

echo ""
echo "DEM differencing  →  result = A − B"
echo "  DEM A:           $DEM_A"
echo "  DEM B:           $DEM_B"
echo "  DEM being warped: $(basename "$DEM_WARP")  →  $WARPED_DEM"
echo "  Target CRS:      $WARP_SRS"
echo "  Target res:      ${XRES} x ${YRES}"
echo "  Resampling:      $RESAMPLING"
[ -n "$MAX_DIFF" ] && echo "  Max diff mask:   |diff| <= ${MAX_DIFF}"
echo "  Output diff:     $DIFF_DEM"
echo ""

# ─── Warp DEM_WARP onto the Target Grid ───────────────────────────────────────

echo "Warping $(basename "$DEM_WARP") ..."

# -te_srs tells gdalwarp that the -te bounds are in DEM_GRID's native CRS,
# so the extent is correctly reprojected even when -c changes the target CRS.
gdalwarp \
    -t_srs  "$WARP_SRS" \
    -te_srs "$GRID_SRS" \
    -te "$ULX" "$LRY" "$LRX" "$ULY" \
    -tr "$XRES" "$YRES" \
    -r  "$RESAMPLING" \
    -overwrite \
    "$DEM_WARP" "$WARPED_DEM"

[ $? -ne 0 ] && { echo "ERROR: gdalwarp failed for $(basename "$DEM_WARP")"; exit 1; }

# ─── Optionally Reproject DEM_GRID ────────────────────────────────────────────

# When a custom CRS (-c) or resolution (-t) is requested, DEM_GRID must also
# be reprojected so both rasters share the same pixel grid before differencing.
if [ -n "$TARGET_CRS" ] || [ -n "$TARGET_RES" ]; then
    GRID_WARPED="${DEM_GRID%.*}_warped_target.tif"
    echo "Reprojecting $(basename "$DEM_GRID") to target grid ..."
    gdalwarp \
        -t_srs  "$WARP_SRS" \
        -te_srs "$GRID_SRS" \
        -te "$ULX" "$LRY" "$LRX" "$ULY" \
        -tr "$XRES" "$YRES" \
        -r  "$RESAMPLING" \
        -overwrite \
        "$DEM_GRID" "$GRID_WARPED"
    [ $? -ne 0 ] && { echo "ERROR: gdalwarp failed for $(basename "$DEM_GRID")"; exit 1; }
else
    # No custom grid parameters: use DEM_GRID as-is
    GRID_WARPED="$DEM_GRID"
fi

# ─── Assign inputs for gdal_calc (result is always A − B) ────────────────────

if [ "$WARP_DEM" = "a" ]; then
    # A was warped onto B's grid → calc A = warped A, calc B = B (or reprojected B)
    GDAL_A="$WARPED_DEM"
    GDAL_B="$GRID_WARPED"
else
    # B was warped onto A's grid → calc A = A (or reprojected A), calc B = warped B
    GDAL_A="$GRID_WARPED"
    GDAL_B="$WARPED_DEM"
fi

# ─── Calculate Difference ─────────────────────────────────────────────────────

echo "Calculating difference DEM (A − B) ..." 
if [ -n "$MAX_DIFF" ]; then
    echo "Masking pixels where |diff| > ${MAX_DIFF} (set to NoData: ${NODATA})"
fi

if [ -n "$MAX_DIFF" ]; then
    # Mask pixels where the absolute difference exceeds MAX_DIFF
    CALC_EXPR="numpy.where(numpy.abs(A-B) <= ${MAX_DIFF}, A-B, ${NODATA})"
else
    CALC_EXPR="A-B"
fi

gdal_calc.py \
    --calc="$CALC_EXPR" \
    --format=GTiff \
    --type=Float32 \
    --NoDataValue="$NODATA" \
    -A "$GDAL_A" \
    -B "$GDAL_B" \
    --outfile="$DIFF_DEM" \
    --overwrite

[ $? -ne 0 ] && { echo "ERROR: gdal_calc.py failed"; exit 1; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────

if [ "$KEEP_WARPED" = false ]; then
    echo "Removing intermediate warped file: $WARPED_DEM"
    rm -f "$WARPED_DEM"
    # Also remove the temp-reprojected grid DEM if one was created
    if [ "$GRID_WARPED" != "$DEM_GRID" ]; then
        echo "Removing temporary reprojected file: $GRID_WARPED"
        rm -f "$GRID_WARPED"
    fi
else
    echo "Keeping intermediate warped file:  $WARPED_DEM"
    [ "$GRID_WARPED" != "$DEM_GRID" ] && echo "Keeping temporary reprojected file:  $GRID_WARPED"
fi

echo ""
echo "Done. Difference DEM saved to: $DIFF_DEM"