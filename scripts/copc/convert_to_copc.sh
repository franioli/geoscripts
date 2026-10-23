#!/bin/bash
# convert_to_copc.sh
#
# Convert a single point cloud (LAS / LAZ / E57 / PLY / …) to
# Cloud Optimized Point Cloud (COPC) format using PDAL.
#
# Output is always a .copc.laz file (COPC requires the LAZ container).
#
# Dependencies: PDAL >= 2.6  (pdal with writers.copc support)
#
# Examples:
#   ./convert_to_copc.sh cloud.las
#   ./convert_to_copc.sh -o copc/cloud.copc.laz cloud.laz
#   ./convert_to_copc.sh -o cloud.copc.laz cloud.e57

# ─── Default Values ───────────────────────────────────────────────────────────

INPUT=""                    # Input point cloud         (positional arg 1)
OUTPUT=""                   # Output COPC path          (-o); auto if empty

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF

Convert a point cloud to Cloud Optimized Point Cloud (COPC).

Usage:  $(basename "$0") [options] <input>

  Arguments:
    input           Source point cloud (LAS, LAZ, E57, PLY, …)

  Output:
    -o PATH         Output .copc.laz path
                    (default: <input>.copc.laz beside input)

  Examples:
    $(basename "$0") cloud.las
    $(basename "$0") -o copc/cloud.copc.laz cloud.laz
    $(basename "$0") -o cloud.copc.laz cloud.e57

EOF
    exit 1
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT="$2"; shift 2 ;;
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
    echo "ERROR: An input point cloud path is required."
    usage
fi

[ ! -f "$INPUT" ] && { echo "ERROR: Input file not found: $INPUT"; exit 1; }

# ─── Resolve Output Path ──────────────────────────────────────────────────────

if [ -z "$OUTPUT" ]; then
    BASE=$(basename "$INPUT")
    DIR=$(dirname "$INPUT")
    # Strip known extensions, then append .copc.laz
    BASE="${BASE%.las}"
    BASE="${BASE%.laz}"
    BASE="${BASE%.e57}"
    BASE="${BASE%.ply}"
    OUTPUT="${DIR}/${BASE}.copc.laz"
fi

# ─── Print Summary ────────────────────────────────────────────────────────────

echo ""
echo "COPC conversion"
echo "  Input:   $INPUT"
echo "  Output:  $OUTPUT"
echo ""

# ─── Convert to COPC ─────────────────────────────────────────────────────────

mkdir -p "$(dirname "$OUTPUT")"

PIPELINE=$(mktemp /tmp/pdal_pipeline_XXXXXX.json)
trap 'rm -f "$PIPELINE"' EXIT

cat > "$PIPELINE" << EOF
{
  "pipeline": [
    "$INPUT",
    {
      "type": "writers.copc",
      "filename": "$OUTPUT"
    }
  ]
}
EOF

pdal pipeline "$PIPELINE"

[ $? -ne 0 ] && { echo "ERROR: pdal pipeline failed for $(basename "$INPUT")"; exit 1; }

echo ""
echo "Done. COPC saved to: $OUTPUT"
