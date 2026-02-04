#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-results/gpu_cublas_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

cp ../../scripts/run_gpu_cublas_gemm.cu gemm.cu

NVCC="${NVCC:-nvcc}"
echo "Compiling with $NVCC ..."
$NVCC -O3 -lineinfo gemm.cu -o gemm -lcublas

N="${GPU_GEMM_N:-8192}"
REPS="${GPU_GEMM_REPS:-10}"

echo "Running GPU DGEMM: N=$N reps=$REPS"
./gemm "$N" "$REPS" | tee gpu_gemm.out

