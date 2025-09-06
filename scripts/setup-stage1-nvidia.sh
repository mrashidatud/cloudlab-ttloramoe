#!/usr/bin/env bash
set -euxo pipefail

LOGDIR=/var/log/cloudlab-setup
mkdir -p "$LOGDIR"
exec &> >(tee -a "$LOGDIR/stage1-nvidia.log")

# Ensure apt is happy
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y dist-upgrade
apt-get -y install build-essential dkms linux-headers-$(uname -r) curl wget ca-certificates gnupg lsb-release pciutils

# Disable nouveau if present
if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
  cat <<EOF >/etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
  update-initramfs -u
fi

# Install a recent production driver (V100S is fine with 535+)
apt-get -y install nvidia-driver-535

# Add a simple systemd unit that continues after reboot
cp /local/repository/scripts/cloudlab-continue.service /etc/systemd/system/cloudlab-continue.service
systemctl daemon-reload

# Flag file so stage2 knows stage1 completed
mkdir -p /opt/cloudlab-setup
touch /opt/cloudlab-setup/STAGE1_DONE

# Enable the continue unit to run stage 2 on next boot
systemctl enable cloudlab-continue.service

echo "Rebooting to load the NVIDIA kernel driver…"
sleep 2
reboot

