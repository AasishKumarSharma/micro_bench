## Packages
## CUDA toolkit on GPU nodes:
## Ubuntu: sudo apt-get install -y nvidia-cuda-toolkit (may be old)
## Better: install official CUDA or use cluster modules (module load CUDA)


#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>
#include <cublas_v2.h>

static void chk(cudaError_t e, const char* m){
  if(e!=cudaSuccess){ fprintf(stderr,"%s: %s\n", m, cudaGetErrorString(e)); exit(1); }
}
static void chkB(cublasStatus_t s, const char* m){
  if(s!=CUBLAS_STATUS_SUCCESS){ fprintf(stderr,"%s: cublas err %d\n", m, (int)s); exit(1); }
}

int main(int argc, char** argv){
  int N = (argc>1)? atoi(argv[1]) : 8192;
  int reps = (argc>2)? atoi(argv[2]) : 10;

  size_t bytes = (size_t)N*N*sizeof(double);
  double *dA,*dB,*dC;
  chk(cudaMalloc(&dA, bytes), "malloc A");
  chk(cudaMalloc(&dB, bytes), "malloc B");
  chk(cudaMalloc(&dC, bytes), "malloc C");
  chk(cudaMemset(dC, 0, bytes), "memset C");

  cublasHandle_t h;
  chkB(cublasCreate(&h), "cublasCreate");

  const double alpha=1.0, beta=0.0;
  // Warmup
  chkB(cublasDgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, N, N, N,
                   &alpha, dA, N, dB, N, &beta, dC, N), "warmup");
  chk(cudaDeviceSynchronize(), "sync");

  float best_ms = 1e30f;
  cudaEvent_t st, en;
  chk(cudaEventCreate(&st), "ev create");
  chk(cudaEventCreate(&en), "ev create");

  for(int r=0;r<reps;r++){
    chk(cudaEventRecord(st), "record st");
    chkB(cublasDgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, N, N, N,
                     &alpha, dA, N, dB, N, &beta, dC, N), "dgemm");
    chk(cudaEventRecord(en), "record en");
    chk(cudaEventSynchronize(en), "sync en");
    float ms;
    chk(cudaEventElapsedTime(&ms, st, en), "elapsed");
    if(ms < best_ms) best_ms = ms;
  }

  double best_s = best_ms / 1000.0;
  double gflops = (2.0 * N * (double)N * (double)N) / best_s / 1e9;

  printf("cuBLAS DGEMM N=%d best_s=%.6f GFLOP/s=%.2f\n", N, best_s, gflops);

  cublasDestroy(h);
  cudaFree(dA); cudaFree(dB); cudaFree(dC);
  return 0;
}

