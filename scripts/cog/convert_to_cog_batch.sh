#!/bin/bash
# batch_convert_to_cog.sh
#
# Convert multiple GeoTIFFs to Cloud Optimized GeoTIFF (COG) by calling
# convert_to_cog.sh for each file found under a source directory.
#
# Output files are written to the destination directory with _cog appended
# to the base name. All COG options are passed through to convert_to_cog.sh,
# including predictor auto-detection (runs independently per file).
#
# Dependencies: convert_to_cog.sh (same directory by default), GDAL >= 2.2
#
# Examples:
#   ./batch_convert_to_cog.sh -s data -d cog
#   ./batch_convert_to_cog.sh -s data -d cog -g "*dsm*"
#   ./batch_convert_to_cog.sh -s data -d cog -b 256 -j 4

# ─── Default Values ───────────────────────────────────────────────────────────

SRC="."                     # Source directory          (-s)
DST="cog"                   # Destination directory     (-d)
GLOB="*.tif"                # File glob pattern         (-g)
BLOCKSIZE=512               # COG tile block size       (-b)
COMPRESS="DEFLATE"          # Compression codec         (-c)
PREDICTOR=""                # DEFLATE predictor         (-p); auto per file
RESAMPLING="AVERAGE"        # Overview resampling       (-r)
THREADS="ALL_CPUS"          # Threads per conversion    (-j)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COG_SCRIPT="${SCRIPT_DIR}/convert_to_cog.sh"

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Convert multiple GeoTIFFs to COG via convert_to_cog.sh.

Usage:  $(basename "$0") [options]

  Source / destination:
    -s DIR          Source directory          (default: $SRC)
    -d DIR          Destination directory     (default: $DST)
    -g PATTERN      Glob for input files      (default: "$GLOB")

  COG options (passed through to convert_to_cog.sh):
    -b SIZE         Tile block size           (default: $BLOCKSIZE)
    -c CODEC        Compression codec         (default: $COMPRESS)
    -p PRED         DEFLATE predictor         (default: auto-detected per file)
    -r METHOD       Overview resampling       (default: $RESAMPLING)
    -j N            Threads per file          (default: $THREADS)

  Examples:
    $(basename "$0") -s data -d cog
    $(basename "$0") -s data -d cog -g "*dsm*"
    $(basename "$0") -s data -d cog -b 256 -j 4

EOF
    exit 1
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SRC="$2";        shift 2 ;;
        -d) DST="$2";        shift 2 ;;
        -g) GLOB="$2";       shift 2 ;;
        -b) BLOCKSIZE="$2";  shift 2 ;;
        -c) COMPRESS="$2";   shift 2 ;;
        -p) PREDICTOR="$2";  shift 2 ;;
        -r) RESAMPLING="$2"; shift 2 ;;
        -j) THREADS="$2";    shift 2 ;;
        -h) usage ;;
        -*) echo "ERROR: Unknown option: $1" >&2; usage ;;
        *)  echo "ERROR: Unexpected argument: $1" >&2; usage ;;
    esac
done

# ─── Validate ─────────────────────────────────────────────────────────────────

[ ! -d "$SRC" ]    && { echo "ERROR: Source directory not found: $SRC"; exit 1; }
[ ! -f "$COG_SCRIPT" ] && { echo "ERROR: convert_to_cog.sh not found: $COG_SCRIPT"; exit 1; }
[ ! -x "$COG_SCRIPT" ] && { echo "ERROR: convert_to_cog.sh is not executable: $COG_SCRIPT"; exit 1; }

# ─── Build Pass-Through Args ──────────────────────────────────────────────────

EXTRA_ARGS=(-b "$BLOCKSIZE" -c "$COMPRESS" -r "$RESAMPLING" -j "$THREADS")
[ -n "$PREDICTOR" ] && EXTRA_ARGS+=(-p "$PREDICTOR")

# ─── Discover Files ───────────────────────────────────────────────────────────

mkdir -p "$DST"

shopt -s nullglob
FILES=("$SRC"/$GLOB)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No files matching '$GLOB' found in: $SRC"
    exit 0
fi

echo ""
echo "Batch COG conversion"
echo "  Source:       $SRC"
echo "  Destination:  $DST"
echo "  Pattern:      $GLOB"
echo "  Files found:  ${#FILES[@]}"
echo ""

# ─── Process Files ────────────────────────────────────────────────────────────

PASS=0
FAIL=0
TOTAL=${#FILES[@]}

for f in "${FILES[@]}"; do
    BASE=$(basename "${f%.*}")
    OUT="${DST}/${BASE}_cog.tif"
    IDX=$(( PASS + FAIL + 1 ))

    echo "══════════════════════════════════════════════════════"
    echo "[${IDX}/${TOTAL}]  $(basename "$f")"

    if "$COG_SCRIPT" "${EXTRA_ARGS[@]}" -o "$OUT" "$f"; then
        PASS=$(( PASS + 1 ))
    else
        echo "WARNING: Failed to convert: $f" >&2
        FAIL=$(( FAIL + 1 ))
    fi
done

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════"
echo "Batch complete:  $PASS succeeded,  $FAIL failed"
echo "Output:          $DST"
echo ""

[ "$FAIL" -gt 0 ] && exit 1
exit 0
