#!/usr/bin/env bash
set -euxo pipefail

LOGDIR=/var/log/cloudlab-setup
mkdir -p "$LOGDIR"
exec &> >(tee -a "$LOGDIR/stage2-env-and-artifact.log")

# Verify driver/GPU is visible
nvidia-smi

# ---------- paths on the big local FS ----------
BASE=/local
MINICONDA_DIR=$BASE/miniconda
ENVNAME=ttloramoe
ARTDIR=$BASE/TTLoRAMoE-SC25

# Caches to /local
mkdir -p $BASE/.cache/pip $BASE/.cache/huggingface $BASE/.cache/torch
cat >/etc/profile.d/ttloramoe-local.sh <<'EOF'
export HF_HOME=/local/.cache/huggingface
export TRANSFORMERS_CACHE=/local/.cache/huggingface/hub
export HF_DATASETS_CACHE=/local/.cache/huggingface/datasets
export TORCH_HOME=/local/.cache/torch
export PIP_CACHE_DIR=/local/.cache/pip
export PATH=/local/miniconda/bin:$PATH
EOF
. /etc/profile.d/ttloramoe-local.sh

# ---------- Miniconda to /local ----------
if [ ! -d "$MINICONDA_DIR" ]; then
  curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
  bash /tmp/mc.sh -b -p "$MINICONDA_DIR"
  rm -f /tmp/mc.sh
fi
. "$MINICONDA_DIR/etc/profile.d/conda.sh"

# Try Anaconda ToS acceptance so defaults work (no --yes)
/local/miniconda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
/local/miniconda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r    || true

create_env() {
  # If ToS still blocks, fall back to conda-forge
  if ! conda create -y -n "$ENVNAME" python=3.11; then
    conda config --system --remove-key default_channels || true
    conda config --system --add channels conda-forge
    conda config --system --set channel_priority strict
    conda create -y --override-channels -c conda-forge -n "$ENVNAME" python=3.11
  fi
}

env_exists=false
if conda info --envs | awk '{print $1}' | grep -Fxq "$ENVNAME"; then
  env_exists=true
  # Check the python minor version in the existing env
  PYV=$(conda run -n "$ENVNAME" python -c 'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))' 2>/dev/null || echo "NA")
  if [ "$PYV" != "3.11" ]; then
    # Recreate with Python 3.11
    conda env remove -n "$ENVNAME" -y || true
    create_env
  fi
else
  create_env
fi

# Activate the env (safe now)
conda activate "$ENVNAME"

# ---------- Python deps + CUDA wheels (ensure matching cu121 trio) ----------
python -m pip install --upgrade pip setuptools wheel

need_torch_install=1
python - <<'PY' && need_torch_install=0 || true
import sys
try:
    import importlib.metadata as M
    req = {"torch":"2.4.1","torchvision":"0.19.1","torchaudio":"2.4.1"}
    ok = all(M.version(k)==v for k,v in req.items())
    raise SystemExit(0 if ok else 1)
except Exception:
    raise SystemExit(1)
PY

if [ "$need_torch_install" -ne 0 ]; then
  python -m pip install --index-url https://download.pytorch.org/whl/cu121 \
    torch==2.4.1 torchvision==0.19.1 torchaudio==2.4.1
fi

# Rest of the stack (idempotent)
python -m pip install pytorch-lightning pandas tensorly datasets transformers accelerate "transformers[torch]"

# ---------- Artifact to /local ----------
if [ ! -d "$ARTDIR" ]; then
  git clone https://github.com/kunwarpradip/TTLoRAMoE-SC25.git "$ARTDIR"
fi
apt-get -y install git-lfs
git -C "$ARTDIR" lfs install || true

# Require Huggingface access token and gated repository to do so
cd "$ARTDIR"
python download_model.py || true

# Convenience runner (auto-detect GPU count)
cat >/usr/local/bin/run-ttloramoe.sh <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail
. /etc/profile.d/ttloramoe-local.sh
. /local/miniconda/etc/profile.d/conda.sh
conda activate ttloramoe
cd /local/TTLoRAMoE-SC25
GPU_CNT=$(nvidia-smi -L | wc -l || echo 1); [ -z "$GPU_CNT" ] && GPU_CNT=1
python Artifact_1.1/inference_comparison.py --batchsize 8 --dataset qnli --test contraction --gpus "$GPU_CNT" --workers 8
EOF
chmod +x /usr/local/bin/run-ttloramoe.sh

touch /opt/cloudlab-setup/COMPLETE
echo "Setup complete."
