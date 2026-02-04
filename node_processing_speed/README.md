**Benchmarking Kit** to calibrate your `processing_speed` (CPU/GPU) across **IoT / Edge / Cloud / HPC** nodes using simple, reproducible microbenchmarks.

Design goals:

* **Portable** (works from IoT to HPC)
* **Minimal dependencies** (fallbacks if BLAS/CUDA not available)
* Produces a **speed index** that can store in JSON as `processing_speed`

This includes **multiple options** (STREAM, DGEMM, HPL / HPL-AI), plus a **unified runner** and a **JSON generator**.

---

### Objective is to calibrate the processing speed of IoT, Edge, Cloud, and HPC node instead of guessing 

Use microbenchmark to get a per-node “effective speed index”:

* **CPU**: `HPL`, `STREAM`, or a fixed-size DGEMM
* **GPU**: `HPL-AI`, `cuda DGEMM`, or a fixed-size tensor/GEMM kernel

Then compute:

```math
$$
\text{processing\_speed}_i = \frac{\text{throughput} \times i}{\text{throughput} \times \text{baseline}}
$$
```

Store that ratio.

---


# Repository structure

```
bench/
  README.md
  env/
    requirements.txt
  scripts/
    detect_hw.sh
    run_cpu_stream.sh
    run_cpu_dgemm_openblas.sh
    run_cpu_dgemm_numpy.py
    run_cpu_hpl.sh
    run_gpu_cublas_gemm.cu
    run_gpu_cublas_gemm.sh
    run_gpu_hpl_ai.sh
    run_all.sh
    collect_to_json.py
  configs/
    baseline.json
  results/
    <node>_<timestamp>/
```

---


# Procedures per tier 

## IoT node (ARM, tiny memory)

**Goal:** CPU+memory index only.

1. Install:

```bash
sudo apt-get update
sudo apt-get install -y build-essential python3-pip
python3 -m pip install numpy
```

2. Run (smaller sizes):

```bash
export STREAM_ARRAY_SIZE=2000000
export DGEMM_N=512
bash scripts/run_all.sh
```

## Edge node

1. Install:

```bash
sudo apt-get update
sudo apt-get install -y build-essential libopenblas-dev python3-pip
python3 -m pip install numpy
```

2. Run:

```bash
export STREAM_ARRAY_SIZE=10000000
export DGEMM_N=1024
bash scripts/run_all.sh
```

## Cloud node

Same as Edge; use slightly larger DGEMM:

```bash
export DGEMM_N=2048
bash scripts/run_all.sh
```

## HPC CPU node

Prefer OpenBLAS/MKL modules; increase sizes:

```bash
module load gcc openblas   # example
export STREAM_ARRAY_SIZE=50000000
export DGEMM_N=4096
bash scripts/run_all.sh
```

## HPC GPU node (V100/A100/H100)

Load CUDA module, then:

```bash
module load cuda gcc
export GPU_GEMM_N=8192      # 16384 if memory allows
bash scripts/run_all.sh
```

---

## Optional: To integrate into MILP plugin system's input JSON format

Once you have baseline CPU GFLOP/s (say node_name), you can generate per-node calibration:

```bash
python scripts/collect_to_json.py \
  --result-dir results/<node>_<ts> \
  --baseline-cpu-gflops 250.0 \
  -o results/<node>_<ts>/calibration.json
```

Then set in nodes JSON:

```json
"processing_speed": {
  "CPU": <from calibration.json>,
  "GPU": <optional>
}
```

---

## Notes

* STREAM gives a **memory bandwidth index**; DGEMM gives a **compute throughput index**. Use DGEMM for `processing_speed` if your task `duration` is compute-dominated.
* If your workflows are **memory-bound**, consider using STREAM Triad to scale `duration` instead, or combine both via a weighted model (we can add this later, but keep the baseline simple first).
* For GPUs, cuBLAS DGEMM is an acceptable microbenchmark for a “speed index”; HPL-AI is closer to AI workloads but harder to deploy.

---



