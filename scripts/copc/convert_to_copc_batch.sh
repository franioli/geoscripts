#!/bin/bash
# convert_to_copc_batch.sh
#
# Convert multiple point clouds to COPC by calling convert_to_copc.sh
# for each file found under a source directory.
#
# Output files are written to the destination directory as <base>.copc.laz.
# Processes all .las and .laz files by default; use -g for other patterns.
#
# Dependencies: convert_to_copc.sh (same directory by default), PDAL >= 2.6
#
# Examples:
#   ./convert_to_copc_batch.sh -s data -d copc
#   ./convert_to_copc_batch.sh -s data -d copc -g "*.laz"
#   ./convert_to_copc_batch.sh -s data/2022 -d copc/2022

# ─── Default Values ───────────────────────────────────────────────────────────

SRC="."                     # Source directory          (-s)
DST="copc"                  # Destination directory     (-d)
GLOB="*.la[sz]"             # File glob pattern         (-g)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPC_SCRIPT="${SCRIPT_DIR}/convert_to_copc.sh"

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Convert multiple point clouds to COPC via convert_to_copc.sh.

Usage:  $(basename "$0") [options]

  Source / destination:
    -s DIR          Source directory       (default: $SRC)
    -d DIR          Destination directory  (default: $DST)
    -g PATTERN      Glob for input files   (default: "$GLOB")

  Examples:
    $(basename "$0") -s data -d copc
    $(basename "$0") -s data -d copc -g "*.laz"
    $(basename "$0") -s data/2022 -d copc/2022

EOF
    exit 1
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) SRC="$2";  shift 2 ;;
        -d) DST="$2";  shift 2 ;;
        -g) GLOB="$2"; shift 2 ;;
        -h) usage ;;
        -*) echo "ERROR: Unknown option: $1" >&2; usage ;;
        *)  echo "ERROR: Unexpected argument: $1" >&2; usage ;;
    esac
done

# ─── Validate ─────────────────────────────────────────────────────────────────

[ ! -d "$SRC" ]        && { echo "ERROR: Source directory not found: $SRC"; exit 1; }
[ ! -f "$COPC_SCRIPT" ] && { echo "ERROR: convert_to_copc.sh not found: $COPC_SCRIPT"; exit 1; }
[ ! -x "$COPC_SCRIPT" ] && { echo "ERROR: convert_to_copc.sh is not executable: $COPC_SCRIPT"; exit 1; }

# ─── Discover Files ───────────────────────────────────────────────────────────

mkdir -p "$DST"

shopt -s nullglob
FILES=("$SRC"/$GLOB)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No files matching '$GLOB' found in: $SRC"
    exit 0
fi

echo ""
echo "Batch COPC conversion"
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
    BASE=$(basename "$f")
    BASE="${BASE%.las}"
    BASE="${BASE%.laz}"
    OUT="${DST}/${BASE}.copc.laz"
    IDX=$(( PASS + FAIL + 1 ))

    echo "══════════════════════════════════════════════════════"
    echo "[${IDX}/${TOTAL}]  $(basename "$f")"

    if "$COPC_SCRIPT" -o "$OUT" "$f"; then
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
