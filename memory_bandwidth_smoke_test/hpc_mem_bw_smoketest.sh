#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# hpc_mem_bw_smoketest.sh
#
# A portable, repeatable memory bandwidth smoke test for HPC / performance ops.
#
# - Primary mode: downloads STREAM source from UVA as a single C file (no tarball)
# - Fallback mode: builds Mini-STREAM locally (no network required)
# - Sweeps OMP_NUM_THREADS and logs Copy/Scale/Add/Triad MB/s + metadata to CSV
#
# Designed to be "share-ready" with a README and reproducible output.
# ==============================================================================

# -------------------------
# Config (override via env)
# -------------------------
WORKDIR="${WORKDIR:-$PWD/mem_bw_smoketest}"
STREAM_VERSION="${STREAM_VERSION:-5.10}"

CC_BIN="${CC_BIN:-cc}"                   # gcc/clang/icc/icx/cc
CFLAGS_EXTRA="${CFLAGS_EXTRA:--O3 -march=native}"
OPENMP_FLAG="${OPENMP_FLAG:--fopenmp}"   # GCC/Clang typically support -fopenmp (needs libomp for clang)
REPEATS="${REPEATS:-5}"                  # STREAM NTIMES
ARRAY_MB="${ARRAY_MB:-1024}"             # approx total footprint for 3 arrays (MiB)
OMP_THREADS_LIST="${OMP_THREADS_LIST:-1 2 4 8 16 32}"  # adjust to node size
CSV_OUT="${CSV_OUT:-$WORKDIR/results_mem_bw.csv}"

# Binding defaults (override if you know what you’re doing)
export OMP_PROC_BIND="${OMP_PROC_BIND:-true}"
export OMP_PLACES="${OMP_PLACES:-cores}"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# -------------------------
# Helpers
# -------------------------
log()  { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }
now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

require_cmd_or_hint() {
  local cmd="$1"
  local hint="$2"
  if ! have_cmd "$cmd"; then
    die "Missing required command: $cmd. Install hint: $hint"
  fi
}

# OS detection for install hints
os_hint_build_tools() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian)
        echo "sudo apt-get update && sudo apt-get install -y build-essential gcc g++ make python3 curl"
        ;;
      fedora|rhel|centos)
        echo "sudo dnf install -y gcc gcc-c++ make python3 curl"
        ;;
      arch)
        echo "sudo pacman -S --needed base-devel gcc python curl"
        ;;
      *)
        echo "Install a C compiler (gcc/clang), make, python3, and curl/wget via your OS package manager."
        ;;
    esac
  else
    echo "Install a C compiler (gcc/clang), make, python3, and curl/wget via your OS package manager."
  fi
}

os_hint_openmp_clang() {
  # clang often needs libomp-dev / libomp
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian)
        echo "sudo apt-get install -y libomp-dev"
        ;;
      fedora|rhel|centos)
        echo "sudo dnf install -y libomp"
        ;;
      arch)
        echo "sudo pacman -S --needed libomp"
        ;;
      *)
        echo "Install OpenMP runtime for clang (libomp)."
        ;;
    esac
  else
    echo "Install OpenMP runtime for clang (libomp)."
  fi
}

get_cpu_model() {
  if have_cmd lscpu; then
    lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}'
  elif [[ -r /proc/cpuinfo ]]; then
    awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo
  else
    echo "unknown"
  fi
}

get_total_mem_gb() {
  if [[ -r /proc/meminfo ]]; then
    awk '/MemTotal/ {printf "%.2f", $2/1024/1024}' /proc/meminfo
  else
    echo "unknown"
  fi
}

get_numa_nodes() {
  if have_cmd lscpu; then
    lscpu | awk -F: '/NUMA node\(s\)/ {gsub(/^[ \t]+/, "", $2); print $2; exit}'
  else
    echo "unknown"
  fi
}

get_governor() {
  local p="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
  [[ -r "$p" ]] && cat "$p" || echo "unknown"
}

get_mhz() {
  if have_cmd lscpu; then
    lscpu | awk -F: '/CPU MHz/ {gsub(/^[ \t]+/, "", $2); print $2; exit}'
  else
    echo "unknown"
  fi
}

# STREAM array size (elements) for ~ARRAY_MB total footprint over 3 arrays of double.
# 3 * N * 8 bytes ~= ARRAY_MB MiB
calc_stream_array_size() {
  require_cmd_or_hint python3 "$(os_hint_build_tools)"
  python3 - <<PY
ARRAY_MB = float("${ARRAY_MB}")
N = int((ARRAY_MB * 1024 * 1024) / (3.0 * 8.0))
N = (N // 64) * 64
print(max(N, 1_000_000))
PY
}

# -------------------------
# Dependency checks (fail early with clear instructions)
# -------------------------
require_cmd_or_hint "$CC_BIN" "$(os_hint_build_tools)"
require_cmd_or_hint python3 "$(os_hint_build_tools)"

if ! have_cmd curl && ! have_cmd wget; then
  die "Need curl or wget for STREAM mode. Install hint: $(os_hint_build_tools)"
fi

# -------------------------
# STREAM: download a single source file from UVA (no tarball)
# -------------------------
STREAM_C="$WORKDIR/stream.c"
STREAM_BIN="$WORKDIR/stream_${STREAM_VERSION}.x"

# Official UVA directory provides stream.c and versioned stream.c.* files :contentReference[oaicite:1]{index=1}
# We try a small list of known-good URLs (first that works wins).
STREAM_URLS=(
  "https://www.cs.virginia.edu/stream/FTP/Code/stream.c"
  "https://www.cs.virginia.edu/stream/FTP/Code/Development/stream.c.${STREAM_VERSION}"
  "https://www.cs.virginia.edu/stream/FTP/Code/Versions/Old/stream.c.${STREAM_VERSION}"
)

download_to() {
  local url="$1"
  local out="$2"
  if have_cmd curl; then
    curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
  else
    wget --tries=3 --timeout=20 -O "$out" "$url"
  fi
}

looks_like_c_source() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  # crude but effective: must contain "STREAM" and "Copy:" tokens or header
  grep -q "STREAM" "$f" && grep -q "Copy" "$f"
}

try_prepare_stream() {
  rm -f "$STREAM_C"
  for u in "${STREAM_URLS[@]}"; do
    log "Trying STREAM source: $u"
    if download_to "$u" "$STREAM_C"; then
      if looks_like_c_source "$STREAM_C"; then
        log "STREAM source downloaded successfully."
        return 0
      else
        warn "Downloaded content does not look like STREAM C source (maybe HTML error page)."
        head -n 10 "$STREAM_C" >&2 || true
      fi
    else
      warn "Failed to download from: $u"
    fi
  done
  return 1
}

# -------------------------
# Mini-STREAM fallback (no network required)
# -------------------------
MINI_C="$WORKDIR/mini_stream.c"
MINI_BIN="$WORKDIR/mini_stream.x"

write_mini_stream_c() {
  cat > "$MINI_C" <<'C'
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
  {
    #pragma omp master
    threads = omp_get_num_threads();
  }
#endif

  printf("Mini-STREAM (footprint=%zu MiB, ntimes=%d, threads=%d)\n", mb, ntimes, threads);
  printf("Copy:  %.1f MB/s\n",  copy_mb_s);
  printf("Scale: %.1f MB/s\n",  scale_mb_s);
  printf("Add:   %.1f MB/s\n",  add_mb_s);
  printf("Triad: %.1f MB/s\n",  triad_mb_s);

  free(a); free(b); free(c);
  return 0;
}
C
}

build_mini_stream() {
  write_mini_stream_c
  log "Building Mini-STREAM fallback (no downloads)…"
  "${CC_BIN}" ${CFLAGS_EXTRA} ${OPENMP_FLAG} "$MINI_C" -o "$MINI_BIN" || {
    warn "Mini-STREAM build failed. If using clang, install OpenMP runtime: $(os_hint_openmp_clang)"
    die "Compilation failed."
  }
  [[ -x "$MINI_BIN" ]] || die "Failed to build Mini-STREAM."
}

# -------------------------
# Build target (STREAM or fallback)
# -------------------------
MODE="stream"
BIN=""
STREAM_ARRAY_SIZE="$(calc_stream_array_size)"

if try_prepare_stream; then
  MODE="stream"
  log "Building STREAM (UVA source) with STREAM_ARRAY_SIZE=${STREAM_ARRAY_SIZE} elements (~${ARRAY_MB} MiB footprint for 3 arrays)."

  "${CC_BIN}" ${CFLAGS_EXTRA} -DSTREAM_ARRAY_SIZE="${STREAM_ARRAY_SIZE}" -DNTIMES="${REPEATS}" \
    ${OPENMP_FLAG} "$STREAM_C" -o "$STREAM_BIN" || {
      warn "STREAM build failed. If using clang, install OpenMP runtime: $(os_hint_openmp_clang)"
      warn "You can also force fallback by setting: STREAM_FORCE_FALLBACK=1"
      die "Compilation failed."
    }

  BIN="$STREAM_BIN"
else
  MODE="mini"
  warn "Could not fetch STREAM source from UVA; falling back to Mini-STREAM (offline mode)."
  build_mini_stream
  BIN="$MINI_BIN"
fi

log "Mode: $MODE"
log "Binary: $BIN"

# -------------------------
# Prepare CSV output
# -------------------------
if [[ ! -f "$CSV_OUT" ]]; then
  cat > "$CSV_OUT" <<'CSV'
timestamp_utc,mode,hostname,kernel,cpu_model,sockets,cores_per_socket,threads_total,numa_nodes,mem_total_gb,cpu_mhz,governor,compiler,array_mb,ntimes,omp_threads,copy_mb_s,scale_mb_s,add_mb_s,triad_mb_s
CSV
fi

HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
KERNEL="$(uname -r)"
CPU_MODEL="$(get_cpu_model)"
SOCKETS="$(have_cmd lscpu && lscpu | awk -F: '/Socket\(s\)/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "unknown")"
CORES_PER_SOCKET="$(have_cmd lscpu && lscpu | awk -F: '/Core\(s\) per socket/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "unknown")"
THREADS_TOTAL="$(have_cmd lscpu && lscpu | awk -F: '/CPU\(s\)/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "unknown")"
NUMA_NODES="$(get_numa_nodes)"
MEM_GB="$(get_total_mem_gb)"
CPU_MHZ="$(get_mhz)"
GOV="$(get_governor)"
COMPILER="$("${CC_BIN}" --version 2>/dev/null | head -n1 | tr ',' ' ' | tr -s ' ')"

# -------------------------
# Run loop
# -------------------------
log "Running memory bandwidth sweep: OMP_THREADS_LIST=${OMP_THREADS_LIST}"
log "Writing CSV: $CSV_OUT"

for T in ${OMP_THREADS_LIST}; do
  export OMP_NUM_THREADS="$T"
  TS="$(now_utc)"
  OUT="$WORKDIR/out_${MODE}_T${T}.txt"

  log "RUN: OMP_NUM_THREADS=$T"
  if [[ "$MODE" == "stream" ]]; then
    "$BIN" | tee "$OUT" >/dev/null
  else
    "$BIN" "${ARRAY_MB}" "${REPEATS}" | tee "$OUT" >/dev/null
  fi

  COPY="$(awk '/^Copy:/  {print $2; exit}' "$OUT" || true)"
  SCALE="$(awk '/^Scale:/ {print $2; exit}' "$OUT" || true)"
  ADD="$(awk '/^Add:/   {print $2; exit}' "$OUT" || true)"
  TRIAD="$(awk '/^Triad:/ {print $2; exit}' "$OUT" || true)"
  [[ -n "${TRIAD}" ]] || die "Failed to parse output for T=$T. See $OUT"

  echo "${TS},${MODE},${HOSTNAME},${KERNEL},\"${CPU_MODEL}\",${SOCKETS},${CORES_PER_SOCKET},${THREADS_TOTAL},${NUMA_NODES},${MEM_GB},${CPU_MHZ},${GOV},\"${COMPILER}\",${ARRAY_MB},${REPEATS},${T},${COPY},${SCALE},${ADD},${TRIAD}" >> "$CSV_OUT"
done

log "DONE. Headline metric: TRIAD MB/s."
log "Results: $CSV_OUT"

