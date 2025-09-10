#!/usr/bin/env bash
set -Eeuo pipefail

# -------- Config (override via env if needed) --------
ENVNAME="${ENVNAME:-ttloramoe}"
REPO_DIR="${REPO_DIR:-/local/TTLoRAMoE-SC25}"

# Keep authors' defaults for A1.2 runs:
WORKERS="${WORKERS:-8}"
GPUS_CAP="${GPUS_CAP:-4}"
EPOCHS="${EPOCHS:-100}"
PATIENCE="${PATIENCE:-10}"
BATCHSIZE="${BATCHSIZE:-32}"   # use 32 for *all* datasets per your request

# Supported datasets (17 in AD) minus: boolq, scitail, imdb, qqp
DATASETS=(
  mrpc cola sst2 rte cb sick csqa winogrande_l
  cosmosqa socialiqa hellaswag qnli mnli
)

# Where to log (prefer /local)
if [ -d /local ] && [ -w /local ]; then
  LOG_DIR="/local/ttloramoe_logs"
else
  LOG_DIR="$PWD/ttloramoe_logs"
fi
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_TXT="$LOG_DIR/A1_2_${STAMP}.txt"

# Try to activate env if available (no installs here)
if [ -f /local/miniconda/etc/profile.d/conda.sh ]; then
  . /local/miniconda/etc/profile.d/conda.sh
  conda activate "$ENVNAME" || true
fi

# Sanity checks
if [ ! -d "$REPO_DIR/Artifact_1.2" ]; then
  echo "ERROR: not found: $REPO_DIR/Artifact_1.2  (set REPO_DIR accordingly)" >&2
  exit 2
fi

detect_gpus() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    local n; n="$(nvidia-smi -L 2>/dev/null | wc -l | tr -d ' ')"
    [ -z "$n" ] && n=1
    [ "$n" -lt 1 ] && n=1
    [ "$n" -gt "$GPUS_CAP" ] && echo "$GPUS_CAP" || echo "$n"
  else
    echo 1
  fi
}
GPUS="$(detect_gpus)"

# Header
{
  echo "=== TTLoRAMoE A1.2 single-dataset training (LoRA / TT-LoRA / Adapters) ==="
  echo "Repo: $REPO_DIR"
  echo "Env : $ENVNAME (activation attempted; no installs)"
  echo "GPUs: $GPUS (cap $GPUS_CAP)  Workers: $WORKERS  Epochs: $EPOCHS  Patience: $PATIENCE"
  echo "Batchsize: $BATCHSIZE (forced for all datasets)"
  echo "Datasets: ${DATASETS[*]}"
  echo
  echo "--- nvidia-smi ---"
  (command -v nvidia-smi >/dev/null && nvidia-smi) || echo "nvidia-smi not found."
  echo
  echo "--- git rev-parse (repo state) ---"
  (cd "$REPO_DIR" && git rev-parse --short HEAD) || echo "no git info"
  echo
} | tee -a "$LOG_TXT"

cd "$REPO_DIR"

run_one() {
  local label="$1" script="$2" ds="$3"
  echo "[RUN] $label  dataset=$ds  bs=$BATCHSIZE  gpus=$GPUS  workers=$WORKERS  epochs=$EPOCHS  patience=$PATIENCE" | tee -a "$LOG_TXT"
  {
    echo "----- BEGIN $label ($ds) -----"
    /usr/bin/time -f 'WALL_SECONDS=%e' \
      python "Artifact_1.2/${script}" \
        --gpus "$GPUS" \
        --workers "$WORKERS" \
        --epochs "$EPOCHS" \
        --patience "$PATIENCE" \
        --batchsize "$BATCHSIZE" \
        --dataset "$ds"
    echo "----- END $label ($ds) -----"
    echo
  } >>"$LOG_TXT" 2>&1 || {
    rc=$?
    echo "[WARN] $label on $ds failed (exit $rc) — continuing" | tee -a "$LOG_TXT"
    echo "EXIT_CODE=$rc" >>"$LOG_TXT"
    echo >>"$LOG_TXT"
  }
}

# Loop datasets and methods (LoRA, TT-LoRA, Adapter)
for ds in "${DATASETS[@]}"; do
  run_one "LoRA"     "single_LoRA_training.py"      "$ds"
  run_one "TTLoRA"   "single_TTLoRA_training.py"    "$ds"
  run_one "Adapter"  "single_Adapter_training.py"   "$ds"
done

echo "DONE. Full log: $LOG_TXT"
echo "Per-method CSVs are in: LoRA_Experts_Results/, TTLoRA_Experts_Results/, Adapter_Experts_Results/"
