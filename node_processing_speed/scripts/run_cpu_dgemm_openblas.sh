#!/usr/bin/env bash
## Packages
## sudo apt-get install -y build-essential libopenblas-dev

set -euo pipefail

OUTDIR="${1:-results/dgemm_openblas_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

cat > dgemm.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <cblas.h>

static double now() {
  struct timeval tp; gettimeofday(&tp,NULL);
  return (double)tp.tv_sec + (double)tp.tv_usec*1e-6;
}

int main(int argc, char** argv) {
  int N = (argc>1)? atoi(argv[1]) : 2048;
  int reps = (argc>2)? atoi(argv[2]) : 5;

  double *A=(double*)aligned_alloc(64, (size_t)N*N*sizeof(double));
  double *B=(double*)aligned_alloc(64, (size_t)N*N*sizeof(double));
  double *C=(double*)aligned_alloc(64, (size_t)N*N*sizeof(double));
  if(!A||!B||!C){printf("alloc failed\n"); return 1;}

  for(size_t i=0;i<(size_t)N*N;i++){A[i]=1.0;B[i]=2.0;C[i]=0.0;}

  // Warmup
  cblas_dgemm(CblasRowMajor,CblasNoTrans,CblasNoTrans,N,N,N,1.0,A,N,B,N,0.0,C,N);

  double best=1e9;
  for(int r=0;r<reps;r++){
    double t0=now();
    cblas_dgemm(CblasRowMajor,CblasNoTrans,CblasNoTrans,N,N,N,1.0,A,N,B,N,0.0,C,N);
    double t1=now();
    double dt=t1-t0;
    if(dt<best) best=dt;
  }

  // DGEMM FLOP count: 2*N^3
  double gflops = (2.0*N*N*N)/best/1e9;
  printf("DGEMM N=%d best_s=%.6f GFLOP/s=%.2f\n", N, best, gflops);

  free(A); free(B); free(C);
  return 0;
}
EOF

echo "Compiling DGEMM (OpenBLAS)..."
gcc -O3 -march=native dgemm.c -o dgemm -lopenblas

# Tier defaults
N="${DGEMM_N:-2048}"
REPS="${DGEMM_REPS:-5}"

echo "Running DGEMM: N=$N reps=$REPS"
./dgemm "$N" "$REPS" | tee dgemm.out
echo "Done: $OUTDIR/dgemm.out"

