#!/usr/bin/env python3

## Packages
## python3 -m pip install numpy


import argparse, time
import numpy as np

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=1024)
    ap.add_argument("--reps", type=int, default=5)
    args = ap.parse_args()

    n = args.n
    A = np.ones((n,n), dtype=np.float64)
    B = np.ones((n,n), dtype=np.float64) * 2.0

    # Warmup
    C = A @ B

    best = 1e9
    for _ in range(args.reps):
        t0 = time.perf_counter()
        C = A @ B
        t1 = time.perf_counter()
        best = min(best, t1-t0)

    gflops = (2.0*n*n*n)/best/1e9
    print(f"NumPy DGEMM n={n} best_s={best:.6f} GFLOP/s={gflops:.2f}")

if __name__ == "__main__":
    main()

