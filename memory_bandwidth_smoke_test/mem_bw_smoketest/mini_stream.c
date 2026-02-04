#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#ifdef _OPENMP
#include <omp.h>
#endif

static double now_sec() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

int main(int argc, char **argv) {
  // footprint in MiB (for 3 arrays of doubles)
  size_t mb = (argc > 1) ? (size_t)atoll(argv[1]) : 1024;
  int ntimes = (argc > 2) ? atoi(argv[2]) : 5;

  // 3 arrays of double => 3 * N * 8 bytes ~= mb MiB
  size_t N = (mb * 1024ULL * 1024ULL) / (3ULL * sizeof(double));
  N = (N / 64ULL) * 64ULL;
  if (N < 1000000ULL) N = 1000000ULL;

  double *a = NULL, *b = NULL, *c = NULL;
  if (posix_memalign((void**)&a, 64, N*sizeof(double)) ||
      posix_memalign((void**)&b, 64, N*sizeof(double)) ||
      posix_memalign((void**)&c, 64, N*sizeof(double))) {
    fprintf(stderr, "alloc failed\n");
    return 1;
  }

  #pragma omp parallel for
  for (size_t i=0;i<N;i++){ a[i]=1.0; b[i]=2.0; c[i]=0.0; }

  double best_copy=1e99, best_scale=1e99, best_add=1e99, best_triad=1e99;
  const double scalar = 3.0;

  for (int t=0;t<ntimes;t++) {
    double t0, t1;

    // Copy: c = a (read a, write c) => 16 bytes/elem
    t0 = now_sec();
    #pragma omp parallel for
    for (size_t i=0;i<N;i++) c[i] = a[i];
    t1 = now_sec();
    if (t1-t0 < best_copy) best_copy = t1-t0;

    // Scale: b = scalar*c (read c, write b) => 16 bytes/elem
    t0 = now_sec();
    #pragma omp parallel for
    for (size_t i=0;i<N;i++) b[i] = scalar * c[i];
    t1 = now_sec();
    if (t1-t0 < best_scale) best_scale = t1-t0;

    // Add: c = a + b (read a,b write c) => 24 bytes/elem
    t0 = now_sec();
    #pragma omp parallel for
    for (size_t i=0;i<N;i++) c[i] = a[i] + b[i];
    t1 = now_sec();
    if (t1-t0 < best_add) best_add = t1-t0;

    // Triad: a = b + scalar*c (read b,c write a) => 24 bytes/elem
    t0 = now_sec();
    #pragma omp parallel for
    for (size_t i=0;i<N;i++) a[i] = b[i] + scalar * c[i];
    t1 = now_sec();
    if (t1-t0 < best_triad) best_triad = t1-t0;
  }

  double copy_mb_s  = (16.0 * (double)N) / best_copy  / (1024.0*1024.0);
  double scale_mb_s = (16.0 * (double)N) / best_scale / (1024.0*1024.0);
  double add_mb_s   = (24.0 * (double)N) / best_add   / (1024.0*1024.0);
  double triad_mb_s = (24.0 * (double)N) / best_triad / (1024.0*1024.0);

  int threads = 1;
  #ifdef _OPENMP
  #pragma omp parallel
  { #pragma omp master threads = omp_get_num_threads(); }
  #endif

  printf("Mini-STREAM (footprint=%zu MiB, ntimes=%d, threads=%d)\n", mb, ntimes, threads);
  printf("Copy:  %.1f MB/s\n",  copy_mb_s);
  printf("Scale: %.1f MB/s\n",  scale_mb_s);
  printf("Add:   %.1f MB/s\n",  add_mb_s);
  printf("Triad: %.1f MB/s\n",  triad_mb_s);

  free(a); free(b); free(c);
  return 0;
}
