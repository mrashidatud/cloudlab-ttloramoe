#!/usr/bin/env bash
set -euo pipefail

# ---------- CONFIG ----------
REPO="${REPO:-/local/TTLoRAMoE-SC25}"
ENVNAME="${ENVNAME:-ttloramoe}"
GPUS="${GPUS:-2}"            # r7525 has 2x V100S
WORKERS="${WORKERS:-8}"
EPOCHS="${EPOCHS:-100}"
PATIENCE="${PATIENCE:-10}"

# Batch sizes per contribution
BS_C3="${BS_C3:-32}"         # C3: router compare on mixed datasets
BS_C4="${BS_C4:-32}"         # C4: single-dataset MoE retention
BS_C5="${BS_C5:-16}"         # C5: mixed-dataset MoE

# Preferred dataset for C4 (must be trained; will fall back)
C4_DATASET="${C4_DATASET:-sst2}"

# ---------- ENV (no installs; assume stages done) ----------
[ -f /etc/profile.d/ttloramoe-local.sh ] && . /etc/profile.d/ttloramoe-local.sh
[ -f /local/miniconda/etc/profile.d/conda.sh ] && . /local/miniconda/etc/profile.d/conda.sh
(conda activate "$ENVNAME" 2>/dev/null) || true

ARTDIR="$REPO/Artifact_1.3"
EXPERTS_DIR="$REPO/TTLoRA_Saved_Individual_Expert"
LOGROOT="/local/ttloramoe_logs"

if [ ! -d "$ARTDIR" ] || [ ! -f "$ARTDIR/moe_train.py" ]; then
  echo "ERROR: $ARTDIR/moe_train.py not found." >&2; exit 1
fi
if [ ! -d "$EXPERTS_DIR" ]; then
  echo "ERROR: $EXPERTS_DIR not found (train TT-LoRA experts in A1.2 first)." >&2; exit 1
fi

# ---------- DISCOVER TRAINED TT-LoRA EXPERTS ----------
CANDIDATES=(sst2 qqp mrpc cola winogrande_l rte)
AVAILABLE=()
for d in "${CANDIDATES[@]}"; do
  if [ -d "$EXPERTS_DIR/$d" ] && ls "$EXPERTS_DIR/$d"/*.ckpt >/dev/null 2>&1; then
    AVAILABLE+=("$d")
  fi
done

if [ ${#AVAILABLE[@]} -lt 2 ]; then
  echo "ERROR: Need at least two TT-LoRA experts with checkpoints in $EXPERTS_DIR" >&2
  exit 1
fi

# Default dataset to satisfy utils.py config["dataset_name"] even for mixed runs
DEFAULT_DATASET="sst2"
if [[ ! " ${AVAILABLE[*]} " =~ " ${DEFAULT_DATASET} " ]]; then
  DEFAULT_DATASET="${AVAILABLE[0]}"
fi

# C4 dataset preference
if [[ ! " ${AVAILABLE[*]} " =~ " ${C4_DATASET} " ]]; then
  C4_DATASET="${DEFAULT_DATASET}"
fi

# ---------- LOG SETUP ----------
TS=$(date +'%Y%m%d-%H%M%S')
OUT="$LOGROOT/A1.3-$TS"
mkdir -p "$OUT"

echo "=== TTLoRA A1.3 (TT-LoRA only) ==="
echo "Repo:     $REPO"
echo "Experts:  ${AVAILABLE[*]}"
echo "C4 dataset: $C4_DATASET  (default=$DEFAULT_DATASET)"
echo "Logs ->   $OUT"
echo

REV=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")

# ---------- HELPERS ----------
to_py_list() { local s="["; for x in "$@"; do s+="'$x',"; done; printf "%s" "${s%,}]"; }
AVAILABLE_PY="$(to_py_list "${AVAILABLE[@]}")"

# Create a wrapper INSIDE Artifact_1.3 that sets globals,
# then CHDIR to repo root before running moe_train.py so relative paths work.
make_wrapper() {
  local dataload_type="$1"   # "single" or "multiple"
  local out_py="$2"
  {
    cat <<'PYHDR'
#!/usr/bin/env python
import os, sys, runpy
ARTDIR = os.path.dirname(__file__)
REPOROOT = os.path.abspath(os.path.join(ARTDIR, '..'))
# ensure imports from Artifact_1.3/ keep working
sys.path.insert(0, ARTDIR)
# switch CWD to repo root so TTLoRA_Saved_Individual_Expert/ is found
os.chdir(REPOROOT)
PYHDR
    echo f"dataload_type = '{dataload_type}'"
    echo "experts_list = ${AVAILABLE_PY}"
    if [ "$dataload_type" = "multiple" ]; then
      echo "multiple_datasets = ${AVAILABLE_PY}"
    else
      echo "multiple_datasets = ${AVAILABLE_PY}  # unused in single mode"
    fi
    cat <<'PYRUN'
# run the unmodified training script
runpy.run_path(os.path.join(ARTDIR, 'moe_train.py'), run_name='__main__')
PYRUN
  } > "$out_py"
  chmod +x "$out_py"
}

runlog() { local log="$1"; shift; echo "[RUN] $*" | tee -a "$log"; ( "$@" 2>&1 | tee -a "$log" ); }

# ---------- C3: Router comparison (mixed datasets) ----------
echo "--- C3: Routers on mixed datasets ---"
WRAP_C3="$ARTDIR/.moe_train_c3_${TS}.py"
make_wrapper "multiple" "$WRAP_C3"

for ROUTER in llm single_layer multi_layer; do
  LOG="$OUT/C3_router_${ROUTER}.log"
  {
    echo "=== TTLoRA A1.3 – C3 (router=${ROUTER}) ==="
    echo "git rev: ${REV}"
    echo "experts: ${AVAILABLE[*]}"
    nvidia-smi || true
  } > "$LOG"
  # NOTE: run from the repo root so relative paths resolve
  ( cd "$REPO" && \
    runlog "$LOG" python "$WRAP_C3" \
      --batchsize "$BS_C3" --epochs "$EPOCHS" --patience "$PATIENCE" \
      --workers "$WORKERS" --gpus "$GPUS" --router "$ROUTER" \
      --dataset "$DEFAULT_DATASET" || true )
done
rm -f "$WRAP_C3"

# ---------- C4: Single-dataset retention ----------
echo "--- C4: Single dataset retention (dataset=${C4_DATASET}) ---"
WRAP_C4="$ARTDIR/.moe_train_c4_${TS}.py"
make_wrapper "single" "$WRAP_C4"
LOG="$OUT/C4_single_${C4_DATASET}.log"
{
  echo "=== TTLoRA A1.3 – C4 (dataset=${C4_DATASET}) ==="
  echo "git rev: ${REV}"
  echo "experts: ${AVAILABLE[*]}"
  nvidia-smi || true
} > "$LOG"
( cd "$REPO" && \
  runlog "$LOG" python "$WRAP_C4" \
    --batchsize "$BS_C4" --epochs "$EPOCHS" --patience "$PATIENCE" \
    --workers "$WORKERS" --gpus "$GPUS" --dataset "$C4_DATASET" --router llm || true )
rm -f "$WRAP_C4"

# ---------- C5: Mixed dataset (TT-LoRA MoE) ----------
echo "--- C5: Mixed dataset (experts: ${AVAILABLE[*]}) ---"
WRAP_C5="$ARTDIR/.moe_train_c5_${TS}.py"
make_wrapper "multiple" "$WRAP_C5"
LOG="$OUT/C5_mixed_ttloRA.log"
{
  echo "=== TTLoRA A1.3 – C5 (mixed datasets) ==="
  echo "git rev: ${REV}"
  echo "experts: ${AVAILABLE[*]}"
  nvidia-smi || true
} > "$LOG"
( cd "$REPO" && \
  runlog "$LOG" python "$WRAP_C5" \
    --batchsize "$BS_C5" --epochs "$EPOCHS" --patience "$PATIENCE" \
    --workers "$WORKERS" --gpus "$GPUS" --router llm --dataset "$DEFAULT_DATASET" || true )
rm -f "$WRAP_C5"

echo
echo "All A1.3 TTLoRA runs finished."
echo "Logs:"
ls -1 "$OUT"
