#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------- Config (edit if you like) --------------------
ENVNAME="${ENVNAME:-ttloramoe}"
DATASET="${DATASET:-qnli}"
WORKERS="${WORKERS:-8}"
MAX_GPUS="${MAX_GPUS:-4}"
BATCH_SIZES="${BATCH_SIZES:-2 4 6 8 16 32 64 128}"

# Where the repo is; change if your path differs.
REPO_DIR="${REPO_DIR:-/local/TTLoRAMoE-SC25}"

# Logs go to /local if available, otherwise CWD
if [ -d /local ] && [ -w /local ]; then
  LOG_DIR="/local/ttloramoe_logs"
else
  LOG_DIR="$PWD/ttloramoe_logs"
fi
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_TXT="$LOG_DIR/A1_1_${STAMP}.txt"

# -------------------- Environment prep (no installs) ----------------
# If conda is present, activate the experiment env; otherwise continue.
if [ -f /local/miniconda/etc/profile.d/conda.sh ]; then
  # shellcheck disable=SC1091
  . /local/miniconda/etc/profile.d/conda.sh
  conda activate "$ENVNAME" || true
fi

# Caches (kept on /local if present)
export HF_HOME="${HF_HOME:-/local/.cache/huggingface}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-$HF_HOME/hub}"
export HF_DATASETS_CACHE="${HF_DATASETS_CACHE:-$HF_HOME/datasets}"
export TORCH_HOME="${TORCH_HOME:-/local/.cache/torch}"
mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE" "$TORCH_HOME" || true

# Repo sanity
if [ ! -d "$REPO_DIR/Artifact_1.1" ]; then
  echo "ERROR: Repo not found at $REPO_DIR (expecting Artifact_1.1/). Set REPO_DIR and retry." >&2
  exit 2
fi

# -------------------- GPU/worker selection -------------------------
detect_gpus() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    local n; n="$(nvidia-smi -L 2>/dev/null | wc -l | tr -d ' ')"
    [ -z "$n" ] && n=1
    [ "$n" -lt 1 ] && n=1
    if [ "$n" -gt "$MAX_GPUS" ]; then echo "$MAX_GPUS"; else echo "$n"; fi
  else
    echo 1
  fi
}
GPUS="$(detect_gpus)"

# -------------------- Log header -------------------------
{
  echo "=== TTLoRAMoE A1.1 (Table 3 sequence) @ ${STAMP} ==="
  echo "Repo: $REPO_DIR"
  echo "Env:  ${ENVNAME}  (activation attempted; no installs)"
  echo "GPU(s): ${GPUS} (capped at ${MAX_GPUS}); workers: ${WORKERS}; dataset: ${DATASET}"
  echo "Batch sizes: ${BATCH_SIZES}"
  echo
  echo "--- nvidia-smi ---"
  (command -v nvidia-smi >/dev/null && nvidia-smi) || echo "nvidia-smi not found."
  echo
  echo "--- git rev-parse ---"
  (cd "$REPO_DIR" && git rev-parse --short HEAD) || echo "no git info"
  echo
} | tee -a "$LOG_TXT"

# -------------------- Run sequence (Table 3) ------------------------
# Per the artifact: run both 'reconstruction' and 'contraction'
# for batch sizes [2,4,6,8,16,32,64,128] on qnli with gpus=4, workers=8.
# The program prints average inference time over 10 runs.  :contentReference[oaicite:2]{index=2}
cd "$REPO_DIR"

for TEST in reconstruction contraction; do
  echo "=== TEST: $TEST ===" | tee -a "$LOG_TXT"
  for BS in $BATCH_SIZES; do
    echo "[RUN] test=$TEST  bs=$BS  dataset=$DATASET  gpus=$GPUS  workers=$WORKERS" | tee -a "$LOG_TXT"
    # time the invocation; keep going even if one run fails (e.g., OOM)
    {
      echo "----- BEGIN RUN ($TEST, bs=$BS) -----"
      /usr/bin/time -f 'WALL_SECONDS=%e' \
        python Artifact_1.1/inference_comparison.py \
          --batchsize "$BS" \
          --dataset "$DATASET" \
          --test "$TEST" \
          --gpus "$GPUS" \
          --workers "$WORKERS"
      echo "----- END RUN ($TEST, bs=$BS) -----"
      echo
    } >>"$LOG_TXT" 2>&1 || {
      rc=$?
      echo "[WARN] run failed with exit code $rc (continuing)" | tee -a "$LOG_TXT"
      echo "EXIT_CODE=$rc" >>"$LOG_TXT"
      echo >>"$LOG_TXT"
    }
  done
done

echo "DONE. Full log saved to: $LOG_TXT"
