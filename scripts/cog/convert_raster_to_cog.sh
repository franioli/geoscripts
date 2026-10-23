#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [-s SRC_DIR] [-d DST_DIR] [-b BLOCKSIZE]"
  echo "  -s  Source directory (default: data)"
  echo "  -d  Destination directory (default: cog)"
  echo "  -b  COG block size (default: 512)"
  exit 1
}

SRC="data"
DST="cog"
BLOCKSIZE=512

while getopts "s:d:b:h" opt; do
  case $opt in
    s) SRC="$OPTARG" ;;
    d) DST="$OPTARG" ;;
    b) BLOCKSIZE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

mkdir -p "$DST"

shopt -s nullglob
for f in "$SRC"/*dsm*.tif "$SRC"/*orthophoto*.tif; do
  base=$(basename "${f%.tif}")
  out="$DST/${base}_cog.tif"

  if [[ "$base" == *dsm* ]]; then
    pred=3   # float32 elevation
  else
    pred=2   # 8-bit RGB ortho
  fi

  echo "→ $base"
  gdal_translate "$f" "$out" \
    -of COG \
    -co COMPRESS=DEFLATE \
    -co PREDICTOR=$pred \
    -co BLOCKSIZE=$BLOCKSIZE \
    -co NUM_THREADS=ALL_CPUS \
    -co OVERVIEW_RESAMPLING=AVERAGE \
    -co BIGTIFF=IF_SAFER
done