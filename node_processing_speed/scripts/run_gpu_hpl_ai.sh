#!/usr/bin/env bash
set -euo pipefail

HPLAI_BIN="${HPLAI_BIN:-./hpl-ai}"
HPLAI_CFG="${HPLAI_CFG:-hpl-ai.dat}"
OUTDIR="${1:-results/hpl_ai_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"

if [[ ! -x "$HPLAI_BIN" ]]; then
  echo "ERROR: HPLAI_BIN not executable. Set HPLAI_BIN=/path/to/hpl-ai"
  exit 1
fi

cp "$HPLAI_CFG" "$OUTDIR/"
pushd "$OUTDIR" >/dev/null
echo "Running HPL-AI..."
"$HPLAI_BIN" | tee hpl_ai.out
echo "Parse performance from hpl_ai.out."
popd >/dev/null

