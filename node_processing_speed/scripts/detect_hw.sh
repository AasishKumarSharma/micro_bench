#!/usr/bin/env bash
set -euo pipefail

echo "==== Host ===="
hostname || true
uname -a || true
echo

echo "==== CPU ===="
lscpu || true
echo

echo "==== Memory ===="
free -h || true
echo

echo "==== Disks ===="
lsblk || true
echo

echo "==== Network interfaces ===="
ip -br link || true
echo

echo "==== GPU ===="
nvidia-smi || echo "No NVIDIA GPU / nvidia-smi not available"

