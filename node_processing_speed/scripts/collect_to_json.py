#!/usr/bin/env python3
import argparse, json, re
from pathlib import Path

def parse_gflops(text: str):
    # Matches: "GFLOP/s=123.45"
    m = re.search(r"GFLOP/s=([0-9]+(?:\.[0-9]+)?)", text)
    return float(m.group(1)) if m else None

def parse_stream_triad(text: str):
    # STREAM output line: "Triad      12345.67"
    for line in text.splitlines():
        if line.strip().lower().startswith("triad"):
            parts = line.split()
            try:
                return float(parts[-1])
            except Exception:
                pass
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--result-dir", required=True, help="results/<node>_<ts> directory")
    ap.add_argument("--baseline-cpu-gflops", type=float, required=True)
    ap.add_argument("--baseline-label", default="baseline_cpu")
    ap.add_argument("-o", "--output", default="node_calibration.json")
    args = ap.parse_args()

    root = Path(args.result_dir)

    cpu_gflops = None
    gpu_gflops = None
    triad = None

    # CPU DGEMM (OpenBLAS)
    p = root / "dgemm_openblas" / "dgemm.out"
    if p.exists():
        cpu_gflops = parse_gflops(p.read_text())

    # NumPy fallback
    p = root / "dgemm_numpy.out"
    if cpu_gflops is None and p.exists():
        cpu_gflops = parse_gflops(p.read_text())

    # STREAM Triad
    p = root / "stream" / "stream.out"
    if p.exists():
        triad = parse_stream_triad(p.read_text())

    # GPU GEMM
    p = root / "gpu_cublas" / "gpu_gemm.out"
    if p.exists():
        gpu_gflops = parse_gflops(p.read_text())

    if cpu_gflops is None:
        raise SystemExit("Could not parse CPU GFLOP/s from DGEMM outputs.")

    cpu_speed = cpu_gflops / args.baseline_cpu_gflops
    gpu_speed = (gpu_gflops / args.baseline_cpu_gflops) if gpu_gflops is not None else None

    out = {
        "result_dir": str(root),
        "baseline": {"label": args.baseline_label, "cpu_gflops": args.baseline_cpu_gflops},
        "measured": {"cpu_gflops": cpu_gflops, "gpu_gflops": gpu_gflops, "stream_triad_mbps": triad},
        "processing_speed": {"CPU": round(cpu_speed, 4)},
    }
    if gpu_speed is not None:
        out["processing_speed"]["GPU"] = round(gpu_speed, 4)

    Path(args.output).write_text(json.dumps(out, indent=2))
    print(f"✓ wrote {args.output}")

if __name__ == "__main__":
    main()

