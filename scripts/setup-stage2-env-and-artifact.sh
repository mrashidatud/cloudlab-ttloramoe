#!/usr/bin/env bash
set -euxo pipefail

LOGDIR=/var/log/cloudlab-setup
mkdir -p "$LOGDIR"
exec &> >(tee -a "$LOGDIR/stage2-env-and-artifact.log")

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
conda create -y -n "$ENVNAME" python=3.11 || true
conda activate "$ENVNAME"

# ---------- Python deps + CUDA wheels ----------
python -m pip install --upgrade pip wheel setuptools
python -m pip install pytorch-lightning pandas tensorly datasets transformers accelerate "transformers[torch]"
python -m pip install --index-url https://download.pytorch.org/whl/cu121 torch torchvision torchaudio

# ---------- Artifact to /local ----------
if [ ! -d "$ARTDIR" ]; then
  git clone https://github.com/kunwarpradip/TTLoRAMoE-SC25.git "$ARTDIR"
fi
apt-get -y install git-lfs
git -C "$ARTDIR" lfs install || true

cd "$ARTDIR"
python download_model.py || true

# Convenience runner (inherits /etc/profile.d vars)
cat >/usr/local/bin/run-ttloramoe.sh <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail
. /etc/profile.d/ttloramoe-local.sh
. /local/miniconda/etc/profile.d/conda.sh
conda activate ttloramoe
cd /local/TTLoRAMoE-SC25
python Artifact_1.1/inference_comparison.py --batchsize 8 --dataset qnli --test contraction --gpus 1 --workers 4
EOF
chmod +x /usr/local/bin/run-ttloramoe.sh

touch /opt/cloudlab-setup/COMPLETE
echo "Setup complete."
