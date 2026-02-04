#!/usr/bin/env bash
## Packages
## Debian/Ubuntu: sudo apt-get install -y build-essential
## Optional: numactl for HPC: sudo apt-get install -y numactl

set -euo pipefail

OUTDIR="${1:-results/stream_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

cat > stream.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#ifndef STREAM_ARRAY_SIZE
#define STREAM_ARRAY_SIZE 10000000
#endif

#ifndef NTIMES
#define NTIMES 10
#endif

static double mysecond() {
  struct timeval tp;
  gettimeofday(&tp, NULL);
  return (double) tp.tv_sec + (double) tp.tv_usec * 1.e-6;
}

int main() {
  size_t N = STREAM_ARRAY_SIZE;
  double *a = (double*) aligned_alloc(64, N*sizeof(double));
  double *b = (double*) aligned_alloc(64, N*sizeof(double));
  double *c = (double*) aligned_alloc(64, N*sizeof(double));
  if (!a || !b || !c) { printf("alloc failed\n"); return 1; }

  for (size_t i=0; i<N; i++) { a[i]=1.0; b[i]=2.0; c[i]=0.0; }

  double times[4][NTIMES];
  double scalar = 3.0;

  for (int k=0; k<NTIMES; k++) {
    double t0,t1;

    t0=mysecond();
    for (size_t i=0; i<N; i++) c[i]=a[i];
    t1=mysecond();
    times[0][k]=t1-t0;

    t0=mysecond();
    for (size_t i=0; i<N; i++) b[i]=scalar*c[i];
    t1=mysecond();
    times[1][k]=t1-t0;

    t0=mysecond();
    for (size_t i=0; i<N; i++) c[i]=a[i]+b[i];
    t1=mysecond();
    times[2][k]=t1-t0;

    t0=mysecond();
    for (size_t i=0; i<N; i++) a[i]=b[i]+scalar*c[i];
    t1=mysecond();
    times[3][k]=t1-t0;
  }

  // Ignore first iteration as warmup
  double best[4];
  for (int j=0;j<4;j++){
    best[j]=1e9;
    for (int k=1;k<NTIMES;k++) if (times[j][k] < best[j]) best[j]=times[j][k];
  }

  double bytes[4] = {
    2*sizeof(double)*N, // Copy: read a, write c
    2*sizeof(double)*N, // Scale: read c, write b
    3*sizeof(double)*N, // Add: read a,b write c
    3*sizeof(double)*N  // Triad: read b,c write a
  };

  const char* label[4]={"Copy","Scale","Add","Triad"};

  printf("STREAM_ARRAY_SIZE=%zu\n", N);
  printf("%-8s %12s\n", "Kernel", "Best MB/s");
  for (int j=0;j<4;j++){
    double mbps = (bytes[j]/best[j]) / 1.0e6;
    printf("%-8s %12.2f\n", label[j], mbps);
  }

  free(a); free(b); free(c);
  return 0;
}
EOF

# Adjust size based on node class (override via env)
ARRAY_SIZE="${STREAM_ARRAY_SIZE:-10000000}"
NTIMES="${STREAM_NTIMES:-10}"

echo "Compiling STREAM: ARRAY_SIZE=$ARRAY_SIZE NTIMES=$NTIMES"
gcc -O3 -march=native -DSTREAM_ARRAY_SIZE=$ARRAY_SIZE -DNTIMES=$NTIMES stream.c -o stream

echo "Running STREAM..."
./stream | tee stream.out

echo "Done: $OUTDIR/stream.out"

