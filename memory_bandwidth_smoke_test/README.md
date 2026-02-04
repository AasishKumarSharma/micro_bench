# Memory Bandwidth Smoke Test (STREAM / Mini-STREAM)

This repo provides a portable **memory bandwidth smoke test** that HPC centers
(and any performance engineering workflow) can run repeatedly to detect regressions.

It is intentionally designed to work in:
- HPC login/compute nodes
- cloud VMs
- edge devices with restricted outbound network access


## Why this test is “must-run”

Many applications are ultimately limited by **sustained memory bandwidth** rather than peak FLOPs.
If memory bandwidth regresses due to BIOS changes, kernel upgrades, microcode updates, governors,
NUMA misconfiguration, or throttling — many workloads slow down.

This test answers:
> “How fast can this system move data between CPU cores and DRAM under realistic, sustained load?”
> “Is this system delivering expected sustained memory bandwidth today?”

This is the baseline property that limits a huge class of workloads.
The key headline number is usually **Triad MB/s**.


## Why memory bandwidth is fundamental (before any code)

In modern CPUs:
- CPU cores are extremely fast
- Memory (DRAM) is relatively slow
- Many applications spend most of their time waiting for data
This creates the **memory wall**.

If memory bandwidth is wrong:
- Partial Differential Equations (PDEs) solvers slow down
- Sparse linear algebra slows down
- Graph workloads slow down
- Preprocessing and data movement phases slow down
- Even many “CPU-bound” workloads quietly degrade
That is why HPC centers always baseline memory bandwidth.


## What the script does

`hpc_mem_bw_smoketest.sh`:
1. Attempts to fetch the official STREAM C source directly from UVA (no tarball required).
2. If UVA is blocked/unreachable, it falls back to an included Mini-STREAM implementation (offline).
3. Compiles with OpenMP.
4. Sweeps thread counts (`OMP_THREADS_LIST`).
5. Outputs a CSV with metadata + Copy/Scale/Add/Triad MB/s.

UVA’s public FTP code directories expose STREAM sources like `stream.c` and versioned files.  
(See UVA reference pages and directory listing.)  


## Requirements

### Minimal
- a C compiler (`gcc`/`clang`/`cc`)
- OpenMP support
- python3 (only used to compute a reasonable array size)
- curl or wget (optional; only for STREAM mode)


### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y build-essential gcc g++ make python3 curl

