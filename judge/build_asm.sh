#! /bin/bash
set -e

SRC="$1"
OUTDIR="${2:-/workspace/build}"

mkdir -p "$OUTDIR"
pic-as -mcpu=18f4520 "$SRC" -o "$OUTDIR/main.elf"