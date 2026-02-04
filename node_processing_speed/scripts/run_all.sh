#!/usr/bin/env bash
set -euo pipefail

NODETAG="${NODETAG:-$(hostname)}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTDIR="results/${NODETAG}_${STAMP}"
mkdir -p "$OUTDIR"

echo "Output: $OUTDIR"

# 1) HW detect
bash scripts/detect_hw.sh | tee "$OUTDIR/hw.txt"

# 2) CPU STREAM
STREAM_ARRAY_SIZE="${STREAM_ARRAY_SIZE:-10000000}"
STREAM_NTIMES="${STREAM_NTIMES:-10}"
STREAM_ARRAY_SIZE="$STREAM_ARRAY_SIZE" STREAM_NTIMES="$STREAM_NTIMES" \
  bash scripts/run_cpu_stream.sh "$OUTDIR/stream" >/dev/null

# 3) CPU DGEMM
if command -v gcc >/dev/null 2>&1 && ldconfig -p 2>/dev/null | grep -qi openblas; then
  DGEMM_N="${DGEMM_N:-2048}" DGEMM_REPS="${DGEMM_REPS:-5}" \
    bash scripts/run_cpu_dgemm_openblas.sh "$OUTDIR/dgemm_openblas" >/dev/null
else
  echo "OpenBLAS DGEMM not available; trying NumPy DGEMM..."
  python3 scripts/run_cpu_dgemm_numpy.py --n "${DGEMM_N:-1024}" --reps "${DGEMM_REPS:-5}" \
    | tee "$OUTDIR/dgemm_numpy.out"
fi

# 4) GPU DGEMM if NVIDIA present
if command -v nvidia-smi >/dev/null 2>&1 && command -v nvcc >/dev/null 2>&1; then
  GPU_GEMM_N="${GPU_GEMM_N:-8192}" GPU_GEMM_REPS="${GPU_GEMM_REPS:-10}" \
    bash scripts/run_gpu_cublas_gemm.sh "$OUTDIR/gpu_cublas" >/dev/null
else
  echo "No NVIDIA GPU toolchain detected; skipping GPU GEMM." | tee "$OUTDIR/gpu_skip.txt"
fi

echo "DONE. Results in: $OUTDIR"

