#!/bin/bash
# convert_to_cog.sh
#
# Convert a single GeoTIFF to Cloud Optimized GeoTIFF (COG).
#
# The DEFLATE predictor is auto-detected from the raster data type:
#   Float32 / Float64  →  PREDICTOR=3  (floating-point differencing)
#   Byte (uint8)       →  PREDICTOR=2  (horizontal differencing)
#   Other integer      →  PREDICTOR=1  (none)
#
# Override with -p if the auto-detected value is wrong for your data.
#
# Dependencies: GDAL >= 2.2  (gdal_translate with COG driver, gdalinfo)
#
# Examples:
#   ./convert_to_cog.sh dsm.tif
#   ./convert_to_cog.sh -o output/dsm_cog.tif dsm.tif
#   ./convert_to_cog.sh -b 256 -p 3 dsm.tif

# ─── Default Values ───────────────────────────────────────────────────────────

INPUT=""                    # Input raster              (positional arg 1)
OUTPUT=""                   # Output COG path           (-o); auto if empty
BLOCKSIZE=512               # COG tile block size       (-b)
COMPRESS="DEFLATE"          # Compression codec         (-c)
PREDICTOR=""                # DEFLATE predictor         (-p); auto-detected
RESAMPLING="AVERAGE"        # Overview resampling       (-r)
THREADS="ALL_CPUS"          # gdal_translate threads    (-j)

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Convert a single GeoTIFF to Cloud Optimized GeoTIFF (COG).

Usage:  $(basename "$0") [options] <input.tif>

  Arguments:
    input.tif       Input GeoTIFF raster

  Output:
    -o PATH         Output COG path  (default: <input>_cog.tif beside input)

  COG options:
    -b SIZE         Tile block size in pixels  (default: $BLOCKSIZE)
    -c CODEC        Compression codec          (default: $COMPRESS)
                    Options: DEFLATE, LZW, ZSTD, LERC, NONE, …
    -p PRED         DEFLATE predictor          (default: auto-detected)
                      1 → none  |  2 → horizontal (byte)  |  3 → float
    -r METHOD       Overview resampling        (default: $RESAMPLING)
                    Options: AVERAGE, NEAREST, BILINEAR, CUBIC, …
    -j N            Number of threads          (default: $THREADS)

  Examples:
    $(basename "$0") dsm.tif
    $(basename "$0") -o output/dsm_cog.tif dsm.tif
    $(basename "$0") -b 256 -p 3 dsm.tif

EOF
    exit 1
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT="$2";     shift 2 ;;
        -b) BLOCKSIZE="$2";  shift 2 ;;
        -c) COMPRESS="$2";   shift 2 ;;
        -p) PREDICTOR="$2";  shift 2 ;;
        -r) RESAMPLING="$2"; shift 2 ;;
        -j) THREADS="$2";    shift 2 ;;
        -h) usage ;;
        -*) echo "ERROR: Unknown option: $1" >&2; usage ;;
        *)  if [ -z "$INPUT" ]; then INPUT="$1"
            else echo "ERROR: Unexpected argument: $1" >&2; usage
            fi
            shift ;;
    esac
done

# ─── Validate Inputs ──────────────────────────────────────────────────────────

if [ -z "$INPUT" ]; then
    echo "ERROR: An input raster path is required."
    usage
fi

[ ! -f "$INPUT" ] && { echo "ERROR: Input file not found: $INPUT"; exit 1; }

# ─── Resolve Output Path ──────────────────────────────────────────────────────

if [ -z "$OUTPUT" ]; then
    BASE=$(basename "${INPUT%.*}")
    DIR=$(dirname "$INPUT")
    OUTPUT="${DIR}/${BASE}_cog.tif"
fi

# ─── Auto-detect DEFLATE Predictor ───────────────────────────────────────────

if [ -z "$PREDICTOR" ]; then
    DTYPE=$(gdalinfo "$INPUT" | grep "Type=" | head -1 | sed -E 's/.*Type=([A-Za-z0-9]+).*/\1/')
    case "$DTYPE" in
        Float32|Float64) PREDICTOR=3 ;;
        Byte)            PREDICTOR=2 ;;
        *)               PREDICTOR=1 ;;
    esac
    PRED_SOURCE="auto (${DTYPE})"
else
    PRED_SOURCE="manual"
fi

# ─── Print Summary ────────────────────────────────────────────────────────────

echo ""
echo "COG conversion"
echo "  Input:        $INPUT"
echo "  Output:       $OUTPUT"
echo "  Compression:  $COMPRESS  (predictor=$PREDICTOR, $PRED_SOURCE)"
echo "  Block size:   ${BLOCKSIZE} × ${BLOCKSIZE} px"
echo "  Overviews:    $RESAMPLING resampling"
echo "  Threads:      $THREADS"
echo ""

# ─── Convert to COG ──────────────────────────────────────────────────────────

mkdir -p "$(dirname "$OUTPUT")"

gdal_translate "$INPUT" "$OUTPUT" \
    -of COG \
    -co COMPRESS="$COMPRESS" \
    -co PREDICTOR="$PREDICTOR" \
    -co BLOCKSIZE="$BLOCKSIZE" \
    -co NUM_THREADS="$THREADS" \
    -co OVERVIEW_RESAMPLING="$RESAMPLING" \
    -co BIGTIFF=IF_SAFER

[ $? -ne 0 ] && { echo "ERROR: gdal_translate failed for $(basename "$INPUT")"; exit 1; }

echo ""
echo "Done. COG saved to: $OUTPUT"
