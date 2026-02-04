#!/usr/bin/env bash

## Packages
## Prefer environment modules on HPC (module load ...)
## Or build with OpenBLAS/MKL.



set -euo pipefail

HPL_BIN="${HPL_BIN:-./xhpl}"
HPL_DAT="${HPL_DAT:-HPL.dat}"
OUTDIR="${1:-results/hpl_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"

if [[ ! -x "$HPL_BIN" ]]; then
  echo "ERROR: HPL_BIN not executable. Set HPL_BIN=/path/to/xhpl"
  exit 1
fi
if [[ ! -f "$HPL_DAT" ]]; then
  echo "ERROR: HPL_DAT not found. Provide HPL.dat tuned for the node."
  exit 1
fi

cp "$HPL_DAT" "$OUTDIR/HPL.dat"
pushd "$OUTDIR" >/dev/null

echo "Running HPL..."
"$HPL_BIN" | tee hpl.out

echo "Parse GFLOP/s from hpl.out (look for 'Gflops' column)."
popd >/dev/null

