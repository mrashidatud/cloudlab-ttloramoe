
# CloudLab Profile: TTLoRA-MoE on r7525 GPU (single node)

This profile provisions **one `r7525`** node (Ubuntu 22.04), installs an **NVIDIA driver**, creates a **Conda env**, installs **PyTorch (CUDA 12.1)**, HF/Lightning/TensorLy, clones the **TTLoRA-MoE** artifact repo, and pre-downloads the model.

Artifacts & required packages mirror the paper’s AD (Appendix) so you can immediately run their scripts (e.g., `Artifact_1.1/inference_comparison.py`, `Artifact_1.2/*`, `Artifact_1.3/*`). :contentReference[oaicite:1]{index=1}

## Use

1. Push this repo to GitHub.
2. In CloudLab → **Instantiate** → **Use a profile from a Git repository** → paste your repo URL.
3. Accept defaults; ensure **Hardware Type** = `r7525`.
4. Wait ~10–15 min; the node will reboot once after driver install.

Logs:
- `/var/log/cloudlab-setup/stage1-nvidia.log`
- `/var/log/cloudlab-setup/stage2-env-and-artifact.log`

Quick test after READY:
```bash
ssh yournode
run-ttloramoe.sh

